#.(progn (in-package :ollama-kit) nil)

(defun %lambda-list-spec-variable (spec)
  (cond
    ((symbolp spec) spec)
    ((and (consp spec) (consp (first spec)))
     (second (first spec)))
    ((consp spec) (first spec))
    (t nil)))

(defun %endpoint-keyword-variable (lambda-list name)
  (let ((key-position (position '&key lambda-list)))
    (when key-position
      (loop for spec in (nthcdr (1+ key-position) lambda-list)
            for variable = (%lambda-list-spec-variable spec)
            when (and (symbolp variable)
                      (string-equal (symbol-name variable) name))
              return variable))))

(defun %endpoint-keyword-variables (lambda-list)
  (let ((timeout-var (%endpoint-keyword-variable lambda-list "TIMEOUT"))
        (headers-var (%endpoint-keyword-variable lambda-list "HEADERS")))
    (unless (and timeout-var headers-var)
      (error 'program-error))
    (values timeout-var headers-var)))

(defun %inline-stream-body-form (body-form stream-value)
  "Inline a literal stream BODY-FORM with STREAM-VALUE bound to its flag.

Native endpoint declarations use a one-argument lambda as a small compile-time
data/logic boundary.  Expanding that lambda into a LET keeps endpoint calls
declarative and removes a runtime closure and FUNCALL from every request."
  (unless (and (consp body-form)
               (eq (first body-form) 'lambda))
    (error 'program-error))
  (let ((lambda-list (second body-form)))
    (unless (and (listp lambda-list)
                 (= (length lambda-list) 1)
                 (symbolp (first lambda-list))
                 (not (keywordp (first lambda-list))))
      (error 'program-error))
    `(let ((,(first lambda-list) ,stream-value))
       ,@(cddr body-form))))

(defun %expand-json-endpoint
    (request-function name lambda-list method path body-form
     body-form-supplied-p documentation)
  (let ((client-var (first lambda-list)))
    (multiple-value-bind (timeout-var headers-var)
        (%endpoint-keyword-variables lambda-list)
      `(defun ,name ,lambda-list
         ,@(when documentation (list documentation))
         ,(if body-form-supplied-p
              `(,request-function ,client-var ',method ',path
                                  :body ,body-form
                                  :timeout ,timeout-var
                                  :headers ,headers-var)
              `(,request-function ,client-var ',method ',path
                                  :timeout ,timeout-var
                                  :headers ,headers-var))))))

(defmacro define-native-json-endpoint
    (name lambda-list method path
     &key (body-form nil body-form-supplied-p) documentation)
  "Define a native JSON endpoint from its request contract.

The first lambda-list variable is the client.  TIMEOUT and HEADERS are the
standard endpoint keyword variables.  Keeping the transport invocation in
this macro makes endpoint declarations describe data while REQUEST-JSON
continues to own validation and encoding; the generated helper closes the
successful response before returning its decoded value."
  (%expand-json-endpoint
   '%request-json-value name lambda-list method path body-form
   body-form-supplied-p documentation))

(defmacro define-openai-json-endpoint
    (name lambda-list method path
     &key (body-form nil body-form-supplied-p) documentation)
  "Define an OpenAI-compatible JSON endpoint from its request contract."
  (%expand-json-endpoint
   '%request-json-value name lambda-list method path body-form
   body-form-supplied-p documentation))

(defun %expand-openai-stream-endpoint
    (name lambda-list method path documentation)
  (let ((client-var (first lambda-list))
        (body-var (second lambda-list)))
    (multiple-value-bind (timeout-var headers-var)
        (%endpoint-keyword-variables lambda-list)
      `(defun ,name ,lambda-list
         ,@(when documentation (list documentation))
         (open-openai-stream
          ,client-var ',method ',path
          :body (%openai-stream-body ,body-var)
          :timeout ,timeout-var
          :headers ,headers-var)))))

(defmacro define-openai-stream-endpoint
    (name lambda-list method path &key documentation)
  "Define an OpenAI-compatible SSE endpoint with forced stream mode."
  (%expand-openai-stream-endpoint name lambda-list method path documentation))

(defun %expand-native-stream-pair
    (name stream-name lambda-list method path body-form documentation
     stream-documentation stream-body-form stream-body-form-supplied-p)
  (let* ((client-var (first lambda-list))
         (effective-stream-body-form
           (if stream-body-form-supplied-p stream-body-form body-form))
         (body-expansion (%inline-stream-body-form body-form nil))
         (stream-body-expansion
           (%inline-stream-body-form effective-stream-body-form t)))
    (multiple-value-bind (timeout-var headers-var)
        (%endpoint-keyword-variables lambda-list)
      `(progn
         (defun ,name ,lambda-list
           ,@(when documentation (list documentation))
           (%request-json-value ,client-var ',method ',path
                                :body ,body-expansion
                                :timeout ,timeout-var
                                :headers ,headers-var))
         (defun ,stream-name ,lambda-list
           ,@(when stream-documentation (list stream-documentation))
           (open-ollama-stream ,client-var ',method ',path
                               :body ,stream-body-expansion
                               :timeout ,timeout-var
                               :headers ,headers-var))))))

(defmacro define-native-stream-pair
    (name stream-name lambda-list method path body-form
     &key documentation stream-documentation
       (stream-body-form nil stream-body-form-supplied-p))
  "Define the JSON and streaming forms of one native endpoint.

BODY-FORM must be a literal one-argument lambda accepting a boolean stream
flag.  Its body is inlined with NIL for NAME and T for STREAM-NAME.
STREAM-BODY-FORM can replace it when the non-streaming request must omit a
field instead of sending its false value."
  (%expand-native-stream-pair
   name stream-name lambda-list method path body-form documentation
   stream-documentation stream-body-form stream-body-form-supplied-p))
(defmacro with-http-response ((response-form) &body body)
  "Evaluate RESPONSE-FORM and close its HTTP response after BODY."
  (let ((response (gensym "RESPONSE-")))
    `(let ((,response ,response-form))
       (unwind-protect
            (progn ,@body)
         (%close-response-safely ,response)))))

(defmacro with-json-response ((value-var response-var request-form) &body body)
  "Bind parsed JSON and its response, then close the response after BODY."
  (let ((value (gensym "VALUE-"))
        (response (gensym "RESPONSE-")))
    `(multiple-value-bind (,value ,response) ,request-form
       (let ((,value-var ,value)
             (,response-var ,response))
         (unwind-protect
              (progn ,@body)
           (%close-response-safely ,response-var))))))
