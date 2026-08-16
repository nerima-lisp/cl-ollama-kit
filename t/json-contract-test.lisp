(in-package #:ollama-kit/test)

(describe "JSON data contracts"
          (it
           "normalizes values and supports the accepted object representations"
           (let ((vector #(1 2 3))
                 (hash (make-hash-table :test #'equal)))
             (setf (gethash "answer" hash) 42)
             (assert (equal "user" (ollama-kit::%json-enum :user)))
             (assert (equal "value" (ollama-kit::%json-enum "value")))
             (assert
              (eq json-kit:+json-false+
                  (ollama-kit::%native-bool json-kit:+json-false+)))
             (assert (eq t (ollama-kit::%native-bool t)))
             (let ((client
                    (client-with-request-function
                     (lambda (request &key timeout)
                       (declare (ignore request timeout))
                       (response-with-text "{}")))))
               (assert
                (%signals-p 'ollama-argument-error
                            (lambda ()
                              (generate client "model" "prompt" :raw 1)))))
             (assert (eq vector (ollama-kit::%json-array vector)))
             (assert (equalp #(1 2 3) (ollama-kit::%json-array '(1 2 3))))
             (assert (eql 7 (ollama-kit::%json-array 7)))
             (assert (equal "name" (ollama-kit::%json-key :name)))
             (assert (equal "name" (ollama-kit::%json-key "name")))
             (assert
              (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%json-key 7))))
             (multiple-value-bind (value present-p)
                 (ollama-kit::%json-field hash "answer")
               (assert present-p)
               (assert (= 42 value)))
             (multiple-value-bind (value present-p)
                 (ollama-kit::%json-field '(("answer" . 42)) "answer")
               (assert present-p)
               (assert (= 42 value)))
             (multiple-value-bind (value present-p)
                 (ollama-kit::%json-field '(not-an-object) "answer")
               (declare (ignore value))
               (assert (not present-p)))
             (multiple-value-bind (value present-p)
                 (ollama-kit::%json-field nil "answer")
               (declare (ignore value))
               (assert (not present-p)))
             (multiple-value-bind (value present-p)
                 (ollama-kit::%json-field 7 "answer")
               (declare (ignore value))
               (assert (not present-p)))
             (let ((object (json-object "answer" 42)))
               (multiple-value-bind (value present-p)
                   (ollama-kit::%json-field object "answer")
                 (assert present-p)
                 (assert (= 42 value)))
               (multiple-value-bind (value present-p)
                   (ollama-kit::%json-field object "missing")
                 (declare (ignore value))
                 (assert (not present-p)))
               (assert (consp (ollama-kit::%json-object-members object))))
             (let ((ordered (json-kit:make-json-object '(("answer" . 42)))))
               (multiple-value-bind (value present-p)
                   (ollama-kit::%json-field ordered "missing")
                 (declare (ignore value))
                 (assert (not present-p))))
             (assert (consp (ollama-kit::%json-object-members hash)))
             (assert
              (equal '(("answer" . 42))
                     (ollama-kit::%json-object-members '(("answer" . 42)))))
             (assert
              (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%json-object-members 7))))
             (let ((updated
                    (ollama-kit::%json-object-with-field
                     '(("answer" . 1) ("other" . 2))
                     "answer"
                     42)))
               (multiple-value-bind (value present-p)
                   (ollama-kit::%json-field updated "answer")
                 (assert present-p)
                 (assert (= 42 value))))))
          (it
           "constructs optional message fields without guessing absent values"
           (let ((message
                  (make-message :user
                                "Hello"
                                :name
                                "Ada"
                                :tool-calls
                                '("tool-call")
                                :thinking
                                t
                                :images
                                '("base64-image"))))
             (multiple-value-bind (role role-p)
                 (ollama-kit::%json-field message "role")
               (assert role-p)
               (assert (equal "user" role)))
             (multiple-value-bind (images images-p)
                 (ollama-kit::%json-field message "images")
               (assert images-p)
               (assert (vectorp images)))
             (assert
              (%signals-p 'ollama-argument-error
                          (lambda ()
                            (json-object "odd")))))))
