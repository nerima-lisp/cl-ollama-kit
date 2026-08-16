(in-package #:ollama-kit/test)

(describe "stream lifecycle and error contracts"
          (it "runs an HTTP close callback at most once"
              (let ((close-count 0)
                    (stream nil))
                (setf stream (open-ollama-stream
                              (client-with-request-function
                               (lambda (request &key timeout)
                                 (declare (ignore request timeout))
                                 (make-http-response :status
                                                     200
                                                     :headers
                                                     '(("content-type" .
                                                                       "application/x-ndjson"))
                                                     :stream
                                                     (make-string-input-stream
                                                      "")
                                                     :close-function
                                                     (lambda ()
                                                       (incf close-count)))))
                              :post
                              "/chat"))
                (stream-close stream)
                (stream-close stream)
                (assert (stream-closed-p stream))
                (assert (= 1 close-count))))
          (it "raises a structured condition for a streamed API error"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text
                        (format nil "{\"error\":\"model failed\"}~%")))
                      :post
                      "/chat"))
                    (condition nil))
                (handler-case (stream-next stream)
                  (ollama-stream-error (caught)
                    (setf condition caught)))
                (assert condition)
                (assert (equal "model failed" (ollama-error-message condition)))
                (assert (= 1 (ollama-stream-error-line condition)))
                (assert (hash-table-p (ollama-stream-error-event condition)))
                (assert (stream-closed-p stream))))
          (it "preserves streamed HTTP error bodies and releases the response"
              (let ((close-count 0)
                    (condition nil))
                (handler-case (open-ollama-stream
                               (client-with-request-function
                                (lambda (request &key timeout)
                                  (declare (ignore request timeout))
                                  (make-http-response :status
                                                      404
                                                      :headers
                                                      '(("content-type" .
                                                                        "application/x-ndjson"))
                                                      :stream
                                                      (make-string-input-stream
                                                       (format nil
                                                               "{\"error\":\"model missing\"}~%"))
                                                      :close-function
                                                      (lambda ()
                                                        (incf close-count)))))
                               :post
                               "/chat")
                  (ollama-api-error (caught)
                    (setf condition caught)))
                (assert condition)
                (assert
                 (search "model missing" (ollama-http-error-body condition)))
                (assert (hash-table-p (ollama-api-error-data condition)))
                (assert (= 1 close-count))))
          (it "releases an unexpected streaming response from a JSON request"
              (let ((close-count 0)
                    (condition nil))
                (handler-case (request-json
                               (client-with-request-function
                                (lambda (request &key timeout)
                                  (declare (ignore request timeout))
                                  (make-http-response :status
                                                      200
                                                      :stream
                                                      (make-string-input-stream
                                                       "{}")
                                                      :close-function
                                                      (lambda ()
                                                        (incf close-count)))))
                               :get
                               "/version")
                  (ollama-protocol-error (caught)
                    (setf condition caught)))
                (assert condition)
                (assert (= 1 close-count)))))
