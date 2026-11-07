(defun %call-with-http-timeout-monitor (cancel-token response-timeout
                                                     idle-timeout
                                                     on-response-headers
                                                     on-body-chunk
                                                     send-thunk)
  (let* ((monitor-p (or response-timeout idle-timeout))
         (monitor-lock
          (when monitor-p
            (cl-concurrent-kit:make-lock :name
                                         "cl-ollama-kit HTTP timeout monitor")))
         (monitor-condition
          (when monitor-p
            (cl-concurrent-kit:make-condition-variable :name
                                                       "cl-ollama-kit HTTP timeout monitor")))
         (response-deadline
          (and response-timeout
               (+ (get-internal-real-time)
                  (ceiling (* response-timeout internal-time-units-per-second)))))
         (idle-deadline nil)
         (headers-received-p nil)
         (monitor-stopped-p nil)
         (monitor-timeout-kind nil)
         (monitor-thread nil)
         (callback-condition nil)
         (send-condition nil)
         (response nil)
         (send-returned-p nil))
    (labels ((deadline-after (seconds)
               (+ (get-internal-real-time)
                  (ceiling (* seconds internal-time-units-per-second))))
             (monitor-timeouts ()
               (loop (let ((stopped-p nil)
                           (expired-kind nil))
                       (cl-concurrent-kit:with-lock-held (monitor-lock)
                                                         (setf stopped-p monitor-stopped-p)
                                                         (unless stopped-p
                                                           (let* ((deadline
                                                                   (if headers-received-p
                                                                       idle-deadline
                                                                       response-deadline))
                                                                  (remaining
                                                                   (and deadline
                                                                        (/
                                                                         (float
                                                                          (-
                                                                           deadline
                                                                           (get-internal-real-time))
                                                                          1d0)
                                                                         internal-time-units-per-second))))
                                                             (if (and remaining
                                                                      (<=
                                                                       remaining
                                                                       0))
                                                                 (setf expired-kind (if headers-received-p
                                                                                        :idle
                                                                                        :response))
                                                                 (cl-concurrent-kit:condition-wait
                                                                  monitor-condition
                                                                  monitor-lock
                                                                  :timeout
                                                                  remaining)))))
                       (when stopped-p
                         (return))
                       (when expired-kind
                         (when
                             (http-kit/client:http-client-cancel-request
                              cancel-token)
                           (cl-concurrent-kit:with-lock-held (monitor-lock)
                                                             (setf monitor-timeout-kind expired-kind)))
                         (return)))))
             (record-response-headers ()
               (when monitor-p
                 (cl-concurrent-kit:with-lock-held (monitor-lock)
                                                   (setf headers-received-p t
                                                         idle-deadline (and
                                                                        idle-timeout
                                                                        (deadline-after
                                                                         idle-timeout)))
                                                   (cl-concurrent-kit:condition-notify
                                                    monitor-condition))))
             (record-body-chunk ()
               (when monitor-p
                 (cl-concurrent-kit:with-lock-held (monitor-lock)
                                                   (when headers-received-p
                                                     (setf idle-deadline (and
                                                                          idle-timeout
                                                                          (deadline-after
                                                                           idle-timeout))))
                                                   (cl-concurrent-kit:condition-notify
                                                    monitor-condition))))
             (call-callback (callback arguments)
               (when callback
                 (let ((returned-p nil))
                   (unwind-protect
                       (prog1
                         (handler-bind ((error
                                         (lambda (condition)
                                           (setf callback-condition condition))))
                           (apply callback arguments))
                         (setf returned-p t))
                     (if returned-p
                         (setf callback-condition nil)
                         (http-kit/client:http-client-cancel-request
                          cancel-token))))))
             (stop-monitor ()
               (when monitor-thread
                 (cl-concurrent-kit:with-lock-held (monitor-lock)
                                                   (setf monitor-stopped-p t)
                                                   (cl-concurrent-kit:condition-notify
                                                    monitor-condition))
                 (cl-concurrent-kit:join-thread monitor-thread)))
             (response-header-callback ()
               (when (or monitor-p on-response-headers)
                 (lambda (status headers)
                   (record-response-headers)
                   (call-callback on-response-headers (list status headers)))))
             (body-chunk-callback ()
               (when (or monitor-p on-body-chunk)
                 (lambda (chunk)
                   (record-body-chunk)
                   (call-callback on-body-chunk (list chunk))))))
      (setf monitor-thread (when monitor-p
                             (cl-concurrent-kit:make-thread #'monitor-timeouts
                                                            :name
                                                            "cl-ollama-kit HTTP timeout monitor")))
      (unwind-protect
          (handler-case (progn
                          (setf response (funcall send-thunk
                                                  (response-header-callback)
                                                  (body-chunk-callback)))
                          (setf send-returned-p t))
            (error (condition)
              (setf send-condition condition)))
        (unwind-protect (stop-monitor)
          (unless send-returned-p
            (http-kit/client:http-client-cancel-request cancel-token))))
      (cond
        (callback-condition (error callback-condition))
        ((eq monitor-timeout-kind :response)
         (error 'ollama-response-timeout
                :message
                "HTTP response headers were not received before the response timeout."
                :cause
                send-condition))
        ((eq monitor-timeout-kind :idle)
         (error 'ollama-idle-timeout
                :message
                "No HTTP body chunk arrived before the idle timeout."
                :cause
                send-condition))
        ((and send-condition
              (typep send-condition
                     'http-kit/client:http-client-request-cancelled))
         (error 'ollama-cancelled
                :message
                "The HTTP request was cancelled by the caller."
                :cause
                send-condition))
        ((and send-condition (typep send-condition 'ollama-error))
         (error send-condition))
        (send-condition
         (error 'ollama-transport-error
                :message
                "The HTTP client failed while sending a request."
                :cause
                send-condition))
        (t response)))))
