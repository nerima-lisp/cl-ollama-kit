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

(describe "NDJSON response streams"
          (it "decodes events in wire order and accepts a final record at EOF"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text
                        (format nil "{\"response\":\"A\"}~%{\"done\":true}")
                        :status
                        200))
                      :post
                      "/generate")))
                (multiple-value-bind (first present-p) (stream-next stream)
                  (assert present-p)
                  (assert (equal "A" (gethash "response" first))))
                (multiple-value-bind (second present-p) (stream-next stream)
                  (assert present-p)
                  (assert (eq t (gethash "done" second))))
                (multiple-value-bind (eof present-p) (stream-next stream)
                  (declare (ignore eof))
                  (assert (not present-p)))
                (assert (stream-closed-p stream))))
          (it "ignores blank lines and decodes UTF-8 octets"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text
                        (format nil
                                "~%  ~%{\"content\":\"日本😀\"}~C~%"
                                #\Return)))
                      :post
                      "/chat")))
                (multiple-value-bind (event present-p) (stream-next stream)
                  (assert present-p)
                  (assert (equal "日本😀" (gethash "content" event))))
                (multiple-value-bind (event present-p) (stream-next stream)
                  (declare (ignore event))
                  (assert (not present-p)))))
          (it "signals malformed NDJSON instead of returning a partial event"
              (let ((stream
                     (open-ollama-stream
                      (queued-client (response-with-text "{\"broken\":"))
                      :post
                      "/chat"))
                    (signalled nil))
                (handler-case (stream-next stream)
                  (ollama-protocol-error ()
                    (setf signalled t)))
                (assert signalled)))
          (it "rejects scalar NDJSON events and closes the response"
              (let ((stream
                     (open-ollama-stream
                      (queued-client (response-with-text (format nil "[]~%")))
                      :post
                      "/chat"))
                    (signalled nil))
                (handler-case (stream-next stream)
                  (ollama-protocol-error ()
                    (setf signalled t)))
                (assert signalled)
                (assert (stream-closed-p stream))))
          (it "stops after a bounded event collection"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text
                        (format nil "{\"n\":1}~%{\"n\":2}~%")))
                      :post
                      "/chat")))
                (assert (= 1 (length (stream-events stream :limit 1))))
                (assert (stream-closed-p stream))))
          (it "bounds the total data in one SSE event"
              (let ((stream
                     (open-openai-stream
                      (openai-client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore request timeout))
                         (make-http-response :status
                                             200
                                             :headers
                                             '(("content-type" .
                                                               "text/event-stream"))
                                             :stream
                                             (make-string-input-stream
                                              (format nil
                                                      "data: {\"aaaaa\":~%data: 123456}~%~%"))))
                       :max-input-length
                       16)
                      :post
                      "/chat/completions"
                      :body
                      (json-object "stream" t)))
                    (signalled nil))
                (handler-case (stream-next stream)
                  (ollama-protocol-error ()
                    (setf signalled t)))
                (assert signalled)
                (assert (stream-closed-p stream))))
          (it "uses the default channel buffer size"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text (format nil "{\"n\":1}~%")))
                      :post
                      "/chat")))
                (multiple-value-bind (channel completion)
                    (stream-channel stream)
                  (multiple-value-bind (event present-p)
                      (cl-concurrent-kit:recv channel)
                    (assert present-p)
                    (assert (= 1 (gethash "n" event))))
                  (cl-concurrent-kit:await completion)
                  (multiple-value-bind (eof present-p)
                      (cl-concurrent-kit:recv channel)
                    (declare (ignore eof))
                    (assert (not present-p))))))
          (it "bridges a stream to a cl-concurrent-kit channel"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text
                        (format nil "{\"n\":1}~%{\"n\":2}~%")))
                      :post
                      "/chat")))
                (multiple-value-bind (channel completion)
                    (stream-channel stream :buffer-size 2)
                  (multiple-value-bind (first first-p)
                      (cl-concurrent-kit:recv channel)
                    (assert first-p)
                    (assert (= 1 (gethash "n" first))))
                  (multiple-value-bind (second second-p)
                      (cl-concurrent-kit:recv channel)
                    (assert second-p)
                    (assert (= 2 (gethash "n" second))))
                  (cl-concurrent-kit:await completion)
                  (multiple-value-bind (eof present-p)
                      (cl-concurrent-kit:recv channel)
                    (declare (ignore eof))
                    (assert (not present-p)))))))
