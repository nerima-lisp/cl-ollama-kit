(in-package #:ollama-kit/test)

(describe "endpoint stream callback contracts"
          (it "requires an event callback from every endpoint family"
              (let ((client (make-client)))
                (unwind-protect
                    (dolist
                        (thunk
                         (list
                          (lambda ()
                            (generate-stream client "test" "prompt" nil))
                          (lambda ()
                            (openai-chat-completions-stream client
                                                            (json-object "model"
                                                                         "test")
                                                            nil))
                          (lambda ()
                            (anthropic-messages-stream client
                                                       (json-object "model"
                                                                    "test"
                                                                    "max_tokens"
                                                                    1
                                                                    "messages"
                                                                    #())
                                                       nil))))
                      (assert
                       (handler-case (progn
                                       (funcall thunk)
                                       nil)
                         (ollama-argument-error ()
                           t))))
                  (close-client client)))))
