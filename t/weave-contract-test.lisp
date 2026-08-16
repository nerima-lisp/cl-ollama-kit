(in-package #:ollama-kit/test)

(describe "declarative endpoint relations"
          (it
           "queries streaming endpoint facts through a declarative logic rule"
           (let ((program
                  (cl-weave:logic-program (:endpoint :native "/generate" :json)
                                          (:endpoint :openai
                                                     "/chat/completions"
                                                     :stream)
                                          (:endpoint :anthropic
                                                     "/messages"
                                                     :stream)
                                          (:- (:streaming ?api ?path)
                                              (:endpoint ?api ?path :stream)))))
             (assert
              (equal
               '(((?api . :openai) (?path . "/chat/completions"))
                 ((?api . :anthropic) (?path . "/messages")))
               (cl-weave:logic-run program (:streaming ?api ?path)))))))
