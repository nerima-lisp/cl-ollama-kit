(in-package #:ollama-kit/test)

(describe "continuation-passing JSON API"
          (it "dispatches successful values and API errors to continuations"
              (let ((success-value nil)
                    (success-response nil)
                    (failure-condition nil))
                (call-with-json
                 (queued-client (response-with-text "{\"ok\":true}"))
                 :get
                 "/version"
                 (lambda (value response)
                   (setf success-value (gethash "ok" value)
                         success-response response))
                 (lambda (condition)
                   (setf failure-condition condition)))
                (unwind-protect
                    (with-soft-assertions (expect success-value :to-be t)
                                          (expect failure-condition :to-be nil))
                  (close-http-response success-response)))
              (let ((failure-condition nil))
                (call-with-json
                 (queued-client
                  (response-with-text "{\"error\":\"missing\"}" :status 404))
                 :get
                 "/version"
                 (lambda (&rest values)
                   (declare (ignore values))
                   (error "The success continuation must not run."))
                 (lambda (condition)
                   (setf failure-condition condition)))
                (expect failure-condition
                        :to-satisfy
                        (lambda (condition)
                          (and (typep condition 'ollama-api-error)
                               (equal "missing"
                                      (ollama-error-message condition))))))))

(describe "continuation macro"
          (it
           "evaluates continuation expressions once and forwards multiple values"
           (let ((success-evaluations 0)
                 (failure-evaluations 0)
                 (success-values nil)
                 (failure-value :unset))
             (with-ollama-continuations
              ((progn
                 (incf success-evaluations)
                 (lambda (&rest values)
                   (setf success-values values)))
               (progn
                 (incf failure-evaluations)
                 (lambda (condition)
                   (setf failure-value condition))))
              (values :left :right))
             (with-soft-assertions (expect success-evaluations :to-be 1)
                                   (expect failure-evaluations :to-be 1)
                                   (expect success-values
                                           :to-equal
                                           '(:left :right))
                                   (expect failure-value :to-be :unset))))
          (it "rejects non-function continuations before running the body"
              (with-soft-assertions
               (expect
                (%signals-p 'ollama-argument-error
                            (lambda ()
                              (with-ollama-continuations
                               (nil
                                (lambda (condition)
                                  (declare (ignore condition))))
                               (error "body must not run"))))
                :to-be
                t)
               (expect
                (%signals-p 'ollama-argument-error
                            (lambda ()
                              (with-ollama-continuations
                               ((lambda (&rest values)
                                  (declare (ignore values))) nil)
                               (error "body must not run"))))
                :to-be
                t))))
