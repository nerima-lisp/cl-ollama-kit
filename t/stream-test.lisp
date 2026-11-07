(in-package #:ollama-kit/test)

(describe "generic stream callback contracts"
          (it "rejects an invalid client and event callbacks"
              (let ((client (make-client)))
                (unwind-protect
                    (progn
                      (assert
                       (handler-case (progn
                                       (call-with-ollama-stream nil
                                                                :post
                                                                "/stream"
                                                                (function
                                                                 identity))
                                       nil)
                         (ollama-argument-error ()
                           t)))
                      (dolist
                          (thunk
                           (list
                            (lambda ()
                              (call-with-ollama-stream client
                                                       :post
                                                       "/stream"
                                                       nil))
                            (lambda ()
                              (call-with-openai-stream client
                                                       :post
                                                       "/stream"
                                                       nil))
                            (lambda ()
                              (call-with-anthropic-stream client
                                                          :post
                                                          "/stream"
                                                          nil))))
                        (assert
                         (handler-case (progn
                                         (funcall thunk)
                                         nil)
                           (ollama-argument-error ()
                             t)))))
                  (close-client client)))))
