(in-package #:ollama-kit/test)

(describe "SSE grammar contract"
          (it "keeps incremental decoding aligned with the finite SSE oracle"
              (let* ((wire
                      (format nil
                              "event: message~%id: 7~%data: {\"value\":1}~%~%"))
                     (oracle (sse-kit:parse-http-sse-events wire))
                     (stream nil)
                     (client
                      (openai-client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore request timeout))
                         (make-http-response :status
                                             200
                                             :headers
                                             '(("content-type" .
                                                               "text/event-stream"))
                                             :stream
                                             (make-string-input-stream wire))))))
                (unwind-protect
                    (progn
                      (setf stream (open-openai-stream client
                                                       :post
                                                       "/chat/completions"
                                                       :body
                                                       (json-object "stream" t)))
                      (assert (= 1 (length oracle)))
                      (let ((oracle-event (first oracle)))
                        (assert
                         (equal "message"
                                (sse-kit:http-sse-event-event oracle-event)))
                        (assert
                         (equal "7" (sse-kit:http-sse-event-id oracle-event)))
                        (assert
                         (equal "{\"value\":1}"
                                (sse-kit:http-sse-event-data oracle-event))))
                      (multiple-value-bind (event present-p)
                          (stream-next stream)
                        (assert present-p)
                        (assert (= 1 (gethash "value" event))))
                      (multiple-value-bind (event present-p)
                          (stream-next stream)
                        (declare (ignore event))
                        (assert (not present-p))))
                  (when stream
                    (stream-close stream))))))
