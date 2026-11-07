(in-package #:ollama-kit/test)

(describe "stream callback option edge cases"
          (it-each
           (("Ollama response" call-with-ollama-stream :response-timeout)
            ("Ollama idle" call-with-ollama-stream :idle-timeout)
            ("OpenAI response" call-with-openai-stream :response-timeout)
            ("OpenAI idle" call-with-openai-stream :idle-timeout)
            ("Anthropic response" call-with-anthropic-stream :response-timeout)
            ("Anthropic idle" call-with-anthropic-stream :idle-timeout))
           "rejects invalid ~A timeout before transport"
           (name stream-function timeout-option)
           (let ((client (make-client)))
             (unwind-protect
                 (assert
                  (handler-case (progn
                                  (funcall stream-function
                                           client
                                           :post
                                           "/stream"
                                           (function identity)
                                           timeout-option
                                           -1)
                                  nil)
                    (ollama-argument-error ()
                      t)))
               (close-client client)))))

(describe "stream callback HTTP lifecycle"
          (it "releases the HTTP connection when the callback returns :stop"
              (let* ((body
                      (cl-codec-kit:string-to-octets
                       (format nil
                               "{\"response\":\"fixture\",\"done\":false}~%")
                       :encoding
                       :utf-8))
                     (server (make-loopback-http-server :chunks (list body)))
                     (client
                      (make-client :base-url (loopback-http-server-url server)))
                     (callback-count 0))
                (unwind-protect
                    (progn
                      (generate-stream client
                                       "test"
                                       "prompt"
                                       (lambda (event)
                                         (declare (ignore event))
                                         (incf callback-count)
                                         :stop))
                      (assert (= 1 callback-count))
                      (assert (loopback-http-server-await-eof server 1.5)))
                  (close-client client)
                  (close-loopback-http-server server))
                (assert (loopback-http-server-thread-joined-p server))
                (assert (loopback-http-server-listener-closed-p server))))
          (it "collects and exposes a non-success stream response body"
              (let* ((body-text "{\"error\":\"model missing\"}")
                     (server
                      (make-loopback-http-server :status
                                                 503
                                                 :body
                                                 (cl-codec-kit:string-to-octets
                                                  body-text
                                                  :encoding
                                                  :utf-8)))
                     (client
                      (make-client :base-url (loopback-http-server-url server)))
                     (condition nil))
                (unwind-protect
                    (progn
                      (setf condition (handler-case (progn
                                                      (generate-stream client
                                                                       "test"
                                                                       "prompt"
                                                                       (function
                                                                        identity))
                                                      nil)
                                        (ollama-http-error (condition)
                                          condition)))
                      (assert (typep condition 'ollama-api-error))
                      (assert (= 503 (ollama-http-error-status condition)))
                      (assert
                       (string= body-text (ollama-http-error-body condition)))
                      (assert
                       (string= "model missing"
                                (gethash "error"
                                         (ollama-api-error-data condition))))
                      (assert
                       (http-message-kit:http-response-p
                        (ollama-http-error-response condition))))
                  (close-client client)
                  (close-loopback-http-server server))
                (assert (loopback-http-server-thread-joined-p server))
                (assert (loopback-http-server-listener-closed-p server))))
          (it "enforces the input limit on a non-success stream response body"
              (let* ((body
                      (cl-codec-kit:string-to-octets "error-payload-too-long"
                                                     :encoding
                                                     :utf-8))
                     (server (make-loopback-http-server :status 502 :body body))
                     (client
                      (make-client :base-url
                                   (loopback-http-server-url server)
                                   :max-input-length
                                   8))
                     (condition nil))
                (unwind-protect
                    (progn
                      (setf condition (handler-case (progn
                                                      (generate-stream client
                                                                       "test"
                                                                       "prompt"
                                                                       (function
                                                                        identity))
                                                      nil)
                                        (ollama-protocol-error (condition)
                                          condition)))
                      (assert (typep condition 'ollama-protocol-error))
                      (assert
                       (and (= 8 (ollama-protocol-error-detail condition))
                            (string=
                             "HTTP response body exceeds the configured limit."
                             (ollama-error-message condition)))))
                  (close-client client)
                  (close-loopback-http-server server))
                (assert (loopback-http-server-thread-joined-p server))
                (assert (loopback-http-server-listener-closed-p server))))
          (it "honors :stop for a final NDJSON record without a newline"
              (let* ((body
                      (cl-codec-kit:string-to-octets
                       "{\"response\":\"final\",\"done\":true}"
                       :encoding
                       :utf-8))
                     (server (make-loopback-http-server :body body))
                     (client
                      (make-client :base-url (loopback-http-server-url server)))
                     (events nil)
                     (response nil))
                (unwind-protect
                    (setf response (generate-stream client
                                                    "test"
                                                    "prompt"
                                                    (lambda (event)
                                                      (push event events)
                                                      :stop)))
                  (close-client client)
                  (close-loopback-http-server server))
                (assert (http-message-kit:http-response-p response))
                (assert (= 1 (length events)))
                (assert (string= "final" (gethash "response" (first events))))
                (assert (gethash "done" (first events)))
                (assert (loopback-http-server-thread-joined-p server))
                (assert (loopback-http-server-listener-closed-p server)))))
