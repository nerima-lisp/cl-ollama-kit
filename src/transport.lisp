(defun %validate-request-body (body-supplied-p body)
  (when
      (and body-supplied-p
           body
           (not (or (stringp body) (%octet-vector-p body))))
    (error 'ollama-argument-error
           :message
           "HTTP request body must be a string or octet vector."
           :detail
           (type-of body)))
  body)

(defun %validate-request-body-length (client body-supplied-p body)
  (when body-supplied-p
    (let ((body-length (%request-body-length body)))
      (when (and body-length (> body-length (client-max-request-length client)))
        (error 'ollama-argument-error
               :message
               "HTTP request body exceeds the configured limit."
               :detail
               (client-max-request-length client)))))
  body)

(defun %request-content-type-headers (headers body-supplied-p content-type)
  (cond
    ((and body-supplied-p (eq content-type +json-unspecified+))
     (%ensure-header headers "Content-Type" "application/json; charset=utf-8"))
    ((and body-supplied-p content-type)
     (%force-header headers "Content-Type" content-type))
    (t headers)))

(defun %request-accept-headers (headers stream-p accept)
  (cond
    ((eq accept +json-unspecified+)
     (%ensure-header headers
                     "Accept"
                     (if stream-p
                         "application/x-ndjson"
                         "application/json")))
    (accept (%force-header headers "Accept" accept))
    (t headers)))

(defun %request-headers (client body-supplied-p
                                stream-p
                                headers
                                content-type
                                accept)
  (let* ((request-headers (%normalize-headers headers))
         (authorization-override-p
          (%header-present-p "Authorization" request-headers))
         (all-headers (append request-headers (client-headers client)))
         (all-headers
          (%request-content-type-headers all-headers
                                         body-supplied-p
                                         content-type))
         (all-headers (%request-accept-headers all-headers stream-p accept)))
    (values all-headers authorization-override-p)))

(defun %request-timeout (client timeout)
  (if (eq timeout +timeout-unspecified+)
      (client-timeout client)
      (progn
        (%validate-timeout timeout)
        timeout)))

(defun %request-option-values (options)
  (values (%keyword-option-supplied-p options :body)
          (%keyword-option options :body nil)
          (%keyword-option options :stream-p nil)
          (%keyword-option options :timeout +timeout-unspecified+)
          (%keyword-option options :headers nil)
          (%keyword-option options :content-type +json-unspecified+)
          (%keyword-option options :accept +json-unspecified+)))

(defun %make-network-request (client method
                                     path
                                     body-supplied-p
                                     body
                                     stream-p
                                     headers
                                     content-type
                                     accept)
  (multiple-value-bind (all-headers authorization-override-p)
      (%request-headers client
                        body-supplied-p
                        stream-p
                        headers
                        content-type
                        accept)
    (let* ((normalized-method (%normalize-method method))
           (request-body
             (when body-supplied-p
               (if (stringp body)
                   (cl-codec-kit:string-to-octets body :encoding :utf-8)
                   body)))
           (request
             (make-http-request
              :method
              (if (symbolp normalized-method)
                  (symbol-name normalized-method)
                  normalized-method)
              :uri
              (%join-url (client-base-url client) path)
              :headers
              all-headers
              :body
              request-body)))
      (when (and (client-api-key-p client) authorization-override-p)
        (error 'ollama-argument-error
               :message "Do not override a configured API-KEY per request."))
      request)))

(defun perform-request (client method path &rest options)
  "Send a raw HTTP request using CLIENT's configured HTTP client.

BODY is a string or octet vector when supplied. The returned value is an
HTTP-MESSAGE-KIT:HTTP-RESPONSE. JSON-aware callers should use REQUEST-JSON.

When CONTENT-TYPE or ACCEPT is explicitly supplied, its value replaces any
header with the same name. NIL suppresses the default header."
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options options
                             '(:body :stream-p
                                     :timeout
                                     :headers
                                     :content-type
                                     :accept))
  (multiple-value-bind (body-supplied-p body
                                        stream-p
                                        timeout
                                        headers
                                        content-type
                                        accept)
      (%request-option-values options)
    (%validate-boolean stream-p "STREAM-P")
    (%validate-request-body body-supplied-p body)
    (%validate-request-body-length client body-supplied-p body)
    (let* ((max-input-length (client-max-input-length client))
           (response-body
             (make-array 0
                         :element-type '(unsigned-byte 8)
                         :adjustable t
                         :fill-pointer 0))
           (response-status nil))
      (labels ((append-response-chunk (chunk)
                 (let* ((used (length response-body))
                        (available (- max-input-length used))
                        (accepted (min available (length chunk)))
                        (new-size (+ used accepted))
                        (capacity (array-dimension response-body 0)))
                   (when (> new-size capacity)
                     (let* ((growth (min 4096 (- max-input-length capacity)))
                            (new-capacity
                              (min max-input-length
                                   (max new-size (+ capacity growth)))))
                       (setf response-body
                             (adjust-array response-body
                                           new-capacity
                                           :fill-pointer used))))
                   (setf (fill-pointer response-body) new-size)
                   (replace response-body chunk
                            :start1 used
                            :end1 new-size
                            :end2 accepted)
                   (> (length chunk) accepted)))
               (response-with-body (response)
                 (make-http-response
                  :protocol-version (http-response-protocol-version response)
                  :status (http-response-status response)
                  :reason (http-response-reason response)
                  :headers (http-response-headers response)
                  :trailers (http-response-trailers response)
                  :body response-body)))
        (let* ((request (%make-network-request client
                                               method
                                               path
                                               body-supplied-p
                                               body
                                               stream-p
                                               headers
                                               content-type
                                               accept))
               (response
                 (send-http-request
                  client
                  request
                  :timeout (%request-timeout client timeout)
                  :collect-body-p nil
                  :on-response-headers
                  (lambda (status response-headers)
                    (declare (ignore response-headers))
                    (setf response-status status))
                  :on-body-chunk
                  (lambda (chunk)
                    (let ((overflow-p (append-response-chunk chunk)))
                      (when
                          (and overflow-p
                               (or (null response-status)
                                   (<= 200 response-status 299)))
                        (error 'ollama-protocol-error
                               :message
                               "HTTP response body exceeds the configured limit."
                               :detail
                               max-input-length)))))))
          (response-with-body response))))))

(defun %perform-request-with-optional-body (client method
                                                   path
                                                   body-supplied-p
                                                   body
                                                   &rest
                                                   options)
  "Call PERFORM-REQUEST while preserving omitted versus explicit NIL BODY."
  (apply #'perform-request
         client
         method
         path
         (append
          (when body-supplied-p
            (list :body body))
          options)))

(defun send-http-request
    (client request &key
                    (timeout +timeout-unspecified+)
                    cancel-token
                    (collect-body-p t)
                    on-response-headers
                    on-body-chunk
                    (response-timeout +timeout-unspecified+)
                    (idle-timeout +timeout-unspecified+))
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-boolean collect-body-p "COLLECT-BODY-P")
  (when (and on-response-headers (not (functionp on-response-headers)))
    (error 'ollama-argument-error
           :message "ON-RESPONSE-HEADERS must be a function."))
  (when (and on-body-chunk (not (functionp on-body-chunk)))
    (error 'ollama-argument-error
           :message "ON-BODY-CHUNK must be a function."))
  (let* ((timeout (if (eq timeout +timeout-unspecified+)
                      (client-timeout client)
                      timeout))
         (response-timeout
           (if (eq response-timeout +timeout-unspecified+)
               (client-response-timeout client)
               response-timeout))
         (idle-timeout
           (if (eq idle-timeout +timeout-unspecified+)
               (client-idle-timeout client)
               idle-timeout))
         (http-client (client-http-client client))
         (cancel-token
           (or cancel-token
               (http-kit/client:make-http-cancellation-token)))
         (monitor-p (or response-timeout idle-timeout))
         (monitor-lock
           (when monitor-p
             (cl-concurrent-kit:make-lock
              :name "cl-ollama-kit HTTP timeout monitor")))
         (monitor-condition
           (when monitor-p
             (cl-concurrent-kit:make-condition-variable
              :name "cl-ollama-kit HTTP timeout monitor")))
         (response-deadline
           (and response-timeout
                (+ (get-internal-real-time)
                   (ceiling (* response-timeout
                               internal-time-units-per-second)))))
         (idle-deadline nil)
         (headers-received-p nil)
         (monitor-stopped-p nil)
         (monitor-timeout-kind nil)
         (monitor-thread nil)
         (callback-condition nil)
         (send-condition nil)
         (response nil))
    (%validate-timeout timeout)
    (labels ((deadline-after (seconds)
               (+ (get-internal-real-time)
                  (ceiling (* seconds internal-time-units-per-second))))
             (monitor-timeouts ()
               (loop
                 (let ((stopped-p nil)
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
                                     (/ (float (- deadline
                                                  (get-internal-real-time))
                                               1d0)
                                        internal-time-units-per-second))))
                         (if (and remaining (<= remaining 0))
                             (setf expired-kind
                                   (if headers-received-p :idle :response))
                             (cl-concurrent-kit:condition-wait
                              monitor-condition monitor-lock
                              :timeout remaining)))))
                   (when stopped-p
                     (return))
                   (when expired-kind
                     (when (http-kit/client:http-client-cancel-request
                            cancel-token)
                       (cl-concurrent-kit:with-lock-held (monitor-lock)
                         (setf monitor-timeout-kind expired-kind)))
                     (return)))))
             (record-response-headers ()
               (when monitor-p
                 (cl-concurrent-kit:with-lock-held (monitor-lock)
                   (setf headers-received-p t
                         idle-deadline
                         (and idle-timeout
                              (deadline-after idle-timeout)))
                   (cl-concurrent-kit:condition-notify monitor-condition))))
             (record-body-chunk ()
               (when monitor-p
                 (cl-concurrent-kit:with-lock-held (monitor-lock)
                   (when headers-received-p
                     (setf idle-deadline
                           (and idle-timeout
                                (deadline-after idle-timeout))))
                   (cl-concurrent-kit:condition-notify monitor-condition))))
             (call-callback (callback arguments)
               (when callback
                 (let ((returned-p nil))
                   (unwind-protect
                        (prog1
                            (handler-bind
                                ((error
                                   (lambda (condition)
                                     (setf callback-condition condition))))
                             (apply callback arguments))
                          (setf returned-p t))
                     (when returned-p
                       (setf callback-condition nil))))))
             (stop-monitor ()
               (when monitor-thread
                 (cl-concurrent-kit:with-lock-held (monitor-lock)
                   (setf monitor-stopped-p t)
                   (cl-concurrent-kit:condition-notify monitor-condition))
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
      (setf monitor-thread
            (when monitor-p
              (cl-concurrent-kit:make-thread
               #'monitor-timeouts
               :name "cl-ollama-kit HTTP timeout monitor")))
      (unwind-protect
           (handler-case
               (setf response
                     (http-kit/client:http-client-send
                      http-client request
                      :timeout timeout
                      :cancel-token cancel-token
                      :collect-body-p collect-body-p
                      :on-response-headers (response-header-callback)
                      :on-body-chunk (body-chunk-callback)))
             (error (condition)
               (setf send-condition condition)))
        (stop-monitor))
      (cond
        (callback-condition
         (error callback-condition))
        ((eq monitor-timeout-kind :response)
         (error 'ollama-response-timeout
                :message "HTTP response headers were not received before the response timeout."
                :cause send-condition))
        ((eq monitor-timeout-kind :idle)
         (error 'ollama-idle-timeout
                :message "No HTTP body chunk arrived before the idle timeout."
                :cause send-condition))
        ((and send-condition
              (typep send-condition
                     'http-kit/client:http-client-request-cancelled))
         (error 'ollama-cancelled
                :message "The HTTP request was cancelled by the caller."
                :cause send-condition))
        ((and send-condition (typep send-condition 'ollama-error))
         (error send-condition))
        (send-condition
         (error 'ollama-transport-error
                :message "The HTTP client failed while sending a request."
                :cause send-condition))
        (t response)))))
