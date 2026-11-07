(in-package #:ollama-kit/test)

(describe "stream callback option edge cases"
          (it "rejects invalid response and idle timeouts before transport"
              (let ((client (make-client)))
                (unwind-protect
                    (dolist
                        (thunk
                         (list
                          (lambda ()
                            (call-with-ollama-stream client
                                                     :post
                                                     "/stream"
                                                     (function identity)
                                                     :response-timeout
                                                     -1))
                          (lambda ()
                            (call-with-ollama-stream client
                                                     :post
                                                     "/stream"
                                                     (function identity)
                                                     :idle-timeout
                                                     -1))
                          (lambda ()
                            (call-with-openai-stream client
                                                     :post
                                                     "/stream"
                                                     (function identity)
                                                     :response-timeout
                                                     -1))
                          (lambda ()
                            (call-with-openai-stream client
                                                     :post
                                                     "/stream"
                                                     (function identity)
                                                     :idle-timeout
                                                     -1))
                          (lambda ()
                            (call-with-anthropic-stream client
                                                        :post
                                                        "/stream"
                                                        (function identity)
                                                        :response-timeout
                                                        -1))
                          (lambda ()
                            (call-with-anthropic-stream client
                                                        :post
                                                        "/stream"
                                                        (function identity)
                                                        :idle-timeout
                                                        -1))))
                      (assert
                       (handler-case (progn
                                       (funcall thunk)
                                       nil)
                         (ollama-argument-error ()
                           t))))
                  (close-client client)))))
