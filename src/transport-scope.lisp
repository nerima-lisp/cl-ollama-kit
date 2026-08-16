(defmacro with-http-response ((response-form) &body body)
  "Evaluate RESPONSE-FORM and close its HTTP response after BODY.

The response is closed even when BODY signals.  Cleanup failures are reported
as warnings so that they do not replace the primary result or condition."
  (let ((response (gensym "RESPONSE-")))
    `(let ((,response ,response-form))
       (unwind-protect
           (progn
             ,@body)
         (%close-response-safely ,response)))))

(defmacro with-json-response ((value-var response-var request-form) &body body)
  "Bind parsed JSON and its response, then close the response after BODY.

REQUEST-FORM must return parsed JSON as its first value and an HTTP response as
its second value, as REQUEST-JSON does."
  (let ((value (gensym "VALUE-"))
        (response (gensym "RESPONSE-")))
    `(multiple-value-bind (,value ,response) ,request-form
       (let ((,value-var ,value)
             (,response-var ,response))
         (unwind-protect
             (progn
               ,@body)
           (%close-response-safely ,response-var))))))
