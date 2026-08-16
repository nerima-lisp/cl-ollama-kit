(in-package #:ollama-kit/test)

(describe "generative data contracts"
          (it-property "preserves message content and role"
                       ((content (gen-integer :min -100000 :max 100000)))
                       (let ((message (make-message :user content)))
                         (expect (gethash "role" message) :to-equal "user")
                         (expect (gethash "content" message) :to-equal content)))
          (it-fuzz "constructs messages for varied scalar content"
                   ((content (gen-integer :min -100000 :max 100000)))
                   (:trials 32 :timeout-per-trial 1)
                   (let ((message (make-message :user content)))
                     (expect (gethash "role" message) :to-equal "user")
                     (expect (gethash "content" message) :to-equal content))))
