#.(progn (in-package :ollama-kit) nil)

(defun %stream-response-success-p (status)
  (<= 200 status 299))

(defun %make-stream-error-body-buffer (limit)
  (make-array (min limit 4096)
              :element-type
              (quote (unsigned-byte 8))
              :adjustable
              t
              :fill-pointer
              0))

(defun %append-stream-error-body (buffer chunk limit)
  (unless (%octet-vector-p chunk)
    (error (quote ollama-protocol-error)
           :message
           "Streaming HTTP body chunks must be octet vectors."
           :detail
           (type-of chunk)))
  (when (> (+ (length buffer) (length chunk)) limit)
    (error (quote ollama-protocol-error)
           :message
           "HTTP response body exceeds the configured limit."
           :detail
           limit))
  (loop for octet across chunk
        do (vector-push-extend octet buffer))
  buffer)

(defun %call-with-event-stream (client method
                                       path
                                       wire-format
                                       event-function
                                       accept
                                       options)
  (unless (client-p client)
    (error (quote ollama-argument-error)
           :message
           "CLIENT must be an Ollama client."))
  (unless (functionp event-function)
    (error (quote ollama-argument-error)
           :message
           "EVENT-FUNCTION must be a function."))
  (%validate-keyword-options options
                             (quote
                              (:body :timeout
                                     :headers
                                     :cancel-token
                                     :response-timeout
                                     :idle-timeout)))
  (let* ((body-supplied-p (%keyword-option-supplied-p options :body))
         (body (%keyword-option options :body nil))
         (encoded-body
          (when body-supplied-p
            (%encode-json body (client-max-request-length client))))
         (timeout (%keyword-option options :timeout +timeout-unspecified+))
         (response-timeout-supplied-p
          (%keyword-option-supplied-p options :response-timeout))
         (response-timeout
          (%keyword-option options :response-timeout +timeout-unspecified+))
         (idle-timeout-supplied-p
          (%keyword-option-supplied-p options :idle-timeout))
         (idle-timeout
          (%keyword-option options :idle-timeout +timeout-unspecified+))
         (headers (%keyword-option options :headers nil))
         (cancel-token
          (or (%keyword-option options :cancel-token nil)
              (http-kit/client:make-http-cancellation-token)))
         (request
          (%make-network-request client
                                 method
                                 path
                                 body-supplied-p
                                 encoded-body
                                 t
                                 headers
                                 +json-unspecified+
                                 accept))
         (max-input-bytes (client-max-input-length client))
         (parser
          (%make-stream-parser wire-format max-input-bytes event-function))
         (response-status nil)
         (response-headers-received-p nil)
         (error-body nil)
         (self-cancelled-p nil)
         (response nil))
    (when response-timeout-supplied-p
      (%validate-timeout response-timeout))
    (when idle-timeout-supplied-p
      (%validate-timeout idle-timeout))
    (progn
      (handler-case (setf response (apply (function send-http-request)
                                          client
                                          request
                                          :timeout
                                          (%request-timeout client timeout)
                                          :cancel-token
                                          cancel-token
                                          :collect-body-p
                                          nil
                                          :on-response-headers
                                          (lambda (status response-headers)
                                            (declare (ignore
                                                      response-headers))
                                            (setf response-status status
                                                  response-headers-received-p t)
                                            (unless
                                                (%stream-response-success-p
                                                 status)
                                              (setf error-body (%make-stream-error-body-buffer
                                                                max-input-bytes))))
                                          :on-body-chunk
                                          (lambda (chunk)
                                            (unless
                                                response-headers-received-p
                                              (error
                                               (quote ollama-protocol-error)
                                               :message
                                               "HTTP body arrived before response headers."))
                                            (if (%stream-response-success-p
                                                 response-status)
                                                (when
                                                    (eq :stop
                                                        (%feed-stream-parser
                                                         parser
                                                         chunk))
                                                  (setf self-cancelled-p t)
                                                  (http-kit/client:http-client-cancel-request
                                                   cancel-token))
                                              (%append-stream-error-body
                                               error-body
                                               chunk
                                               max-input-bytes)))
                                          (append
                                           (when response-timeout-supplied-p
                                             (list :response-timeout
                                                   response-timeout))
                                           (when idle-timeout-supplied-p
                                             (list :idle-timeout
                                                   idle-timeout)))))
        (ollama-cancelled (condition)
                          (if self-cancelled-p
                              (return-from %call-with-event-stream
                                           nil)
                            (error condition)))
        (http-kit/client:http-client-request-cancelled (condition)
                                                       (if self-cancelled-p
                                                           (return-from %call-with-event-stream
                                                                        nil)
                                                         (error (quote ollama-cancelled)
                                                                :message
                                                                "The Ollama stream was cancelled."
                                                                :cause
                                                                condition))))
      (unless (http-response-p response)
        (error (quote ollama-protocol-error)
               :message
               "HTTP transport did not return a response."
               :detail
               response))
      (unless response-headers-received-p
        (error (quote ollama-protocol-error)
               :message
               "HTTP transport omitted the response header callback."
               :detail
               response))
      (if (%stream-response-success-p response-status)
          (unless self-cancelled-p
            (when (eq :stop (%finish-stream-parser parser))
              (setf self-cancelled-p t)
              (http-kit/client:http-client-cancel-request cancel-token)))
        (setf (http-response-body response) error-body))
      (%ensure-success response client)
      response)))
