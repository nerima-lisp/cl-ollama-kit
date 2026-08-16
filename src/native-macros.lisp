(defun %lambda-list-spec-variable (spec)
  (cond
    ((symbolp spec) spec)
    ((and (consp spec) (consp (first spec))) (second (first spec)))
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

(defun %valid-endpoint-name-p (name)
  (and (symbolp name) (not (keywordp name))))

(defun %valid-endpoint-lambda-variable-p (name)
  (and (%valid-endpoint-name-p name)
       (not
        (member name
                '(&optional &rest
                            &body
                            &key
                            &allow-other-keys
                            &aux
                            &whole
                            &environment)
                :test
                #'eq))))

(defun %valid-endpoint-lambda-list-p (lambda-list)
  (and (listp lambda-list)
       (%valid-endpoint-lambda-variable-p (first lambda-list))))

(defun %valid-endpoint-method-p (method)
  (keywordp method))

(defun %valid-endpoint-path-p (path)
  (and (stringp path)
       (plusp (length path))
       (char= (char path 0) #\/)
       (not (find #\? path))
       (not (find #\# path))))

(defun %validate-endpoint-declaration (name lambda-list
                                            method
                                            path
                                            &optional
                                            (stream-name nil
                                                         stream-name-supplied-p))
  (unless (%valid-endpoint-name-p name)
    (error 'program-error))
  (unless (%valid-endpoint-lambda-list-p lambda-list)
    (error 'program-error))
  (unless (%valid-endpoint-method-p method)
    (error 'program-error))
  (unless (%valid-endpoint-path-p path)
    (error 'program-error))
  (when (and stream-name-supplied-p (not (%valid-endpoint-name-p stream-name)))
    (error 'program-error))
  (values name lambda-list method path stream-name))

(defun %validate-stream-endpoint-lambda-list (lambda-list)
  (unless
      (and (%valid-endpoint-lambda-list-p lambda-list)
           (%valid-endpoint-lambda-variable-p (second lambda-list)))
    (error 'program-error))
  lambda-list)

(defun %inline-stream-body-form (body-form stream-value)
  "Inline a literal stream BODY-FORM with STREAM-VALUE bound to its flag.

Native endpoint declarations use a one-argument lambda as a small compile-time
data/logic boundary.  Expanding that lambda into a LET keeps endpoint calls
declarative and removes a runtime closure and FUNCALL from every request."
  (unless (and (consp body-form) (eq (first body-form) 'lambda))
    (error 'program-error))
  (let ((lambda-list (second body-form)))
    (unless
        (and (consp lambda-list)
             (null (cdr lambda-list))
             (%valid-endpoint-lambda-variable-p (first lambda-list)))
      (error 'program-error))
    `(let ((,(first lambda-list) ,stream-value))
       ,@(cddr body-form))))

(defun %expand-json-endpoint (request-function name
                                               lambda-list
                                               method
                                               path
                                               body-form
                                               body-form-supplied-p
                                               documentation)
  (%validate-endpoint-declaration name lambda-list method path)
  (let ((client-var (first lambda-list)))
    (multiple-value-bind (timeout-var headers-var)
        (%endpoint-keyword-variables lambda-list)
      `(defun ,name ,lambda-list
         ,@(when documentation
             (list documentation))
         ,(if body-form-supplied-p
              `(,request-function ,client-var
                                  ',method
                                  ',path
                                  :body
                                  ,body-form
                                  :timeout
                                  ,timeout-var
                                  :headers
                                  ,headers-var)
              `(,request-function ,client-var
                                  ',method
                                  ',path
                                  :timeout
                                  ,timeout-var
                                  :headers
                                  ,headers-var))))))

(defmacro define-native-json-endpoint (name lambda-list
                                            method
                                            path
                                            &key
                                            (body-form nil body-form-supplied-p)
                                            documentation)
  "Define a native JSON endpoint from its request contract.

The first lambda-list variable is the client.  TIMEOUT and HEADERS are the
standard endpoint keyword variables.  Keeping the transport invocation in
this macro makes endpoint declarations describe data while REQUEST-JSON
continues to own validation and encoding; the generated helper closes the
successful response before returning its decoded value."
  (%expand-json-endpoint '%request-json-value
                         name
                         lambda-list
                         method
                         path
                         body-form
                         body-form-supplied-p
                         documentation))

(defmacro define-openai-json-endpoint (name lambda-list
                                            method
                                            path
                                            &key
                                            (body-form nil body-form-supplied-p)
                                            documentation)
  "Define an OpenAI-compatible JSON endpoint from its request contract."
  (%expand-json-endpoint '%request-json-value
                         name
                         lambda-list
                         method
                         path
                         body-form
                         body-form-supplied-p
                         documentation))

(defun %expand-stream-endpoint (stream-opener body-transformer
                                              name
                                              lambda-list
                                              method
                                              path
                                              documentation)
  (unless (and (symbolp stream-opener) (symbolp body-transformer))
    (error 'program-error))
  (%validate-endpoint-declaration name lambda-list method path)
  (%validate-stream-endpoint-lambda-list lambda-list)
  (let ((client-var (first lambda-list))
        (body-var (second lambda-list)))
    (multiple-value-bind (timeout-var headers-var)
        (%endpoint-keyword-variables lambda-list)
      `(defun ,name ,lambda-list
         ,@(when documentation
             (list documentation))
         (,stream-opener ,client-var
                         ',method
                         ',path
                         :body
                         (,body-transformer ,body-var)
                         :timeout
                         ,timeout-var
                         :headers
                         ,headers-var)))))

(defun %expand-openai-stream-endpoint (name lambda-list
                                            method
                                            path
                                            documentation)
  (%expand-stream-endpoint 'open-openai-stream
                           '%openai-stream-body
                           name
                           lambda-list
                           method
                           path
                           documentation))

(defmacro define-openai-stream-endpoint (name lambda-list
                                              method
                                              path
                                              &key
                                              documentation)
  "Define an OpenAI-compatible SSE endpoint with forced stream mode."
  (%expand-openai-stream-endpoint name lambda-list method path documentation))

(defmacro define-anthropic-json-endpoint (name lambda-list
                                               method
                                               path
                                               &key
                                               (body-form nil
                                                          body-form-supplied-p)
                                               documentation)
  "Define an Anthropic-compatible JSON endpoint from its request contract."
  (%expand-json-endpoint '%request-json-value
                         name
                         lambda-list
                         method
                         path
                         body-form
                         body-form-supplied-p
                         documentation))

(defmacro define-anthropic-stream-endpoint (name lambda-list
                                                 method
                                                 path
                                                 &key
                                                 documentation)
  "Define an Anthropic-compatible SSE endpoint with forced stream mode."
  (%expand-stream-endpoint 'open-anthropic-stream
                           '%anthropic-stream-body
                           name
                           lambda-list
                           method
                           path
                           documentation))

(defun %expand-native-stream-pair (name stream-name
                                        lambda-list
                                        method
                                        path
                                        body-form
                                        documentation
                                        stream-documentation
                                        stream-body-form
                                        stream-body-form-supplied-p)
  (%validate-endpoint-declaration name lambda-list method path stream-name)
  (let* ((client-var (first lambda-list))
         (effective-stream-body-form
          (if stream-body-form-supplied-p
              stream-body-form
              body-form))
         (body-expansion (%inline-stream-body-form body-form nil))
         (stream-body-expansion
          (%inline-stream-body-form effective-stream-body-form t)))
    (multiple-value-bind (timeout-var headers-var)
        (%endpoint-keyword-variables lambda-list)
      `(progn
         (defun ,name ,lambda-list
           ,@(when documentation
               (list documentation))
           (%request-json-value ,client-var
                                ',method
                                ',path
                                :body
                                ,body-expansion
                                :timeout
                                ,timeout-var
                                :headers
                                ,headers-var))
         (defun ,stream-name ,lambda-list
           ,@(when stream-documentation
               (list stream-documentation))
           (open-ollama-stream ,client-var
                               ',method
                               ',path
                               :body
                               ,stream-body-expansion
                               :timeout
                               ,timeout-var
                               :headers
                               ,headers-var))))))

(defmacro define-native-stream-pair (name stream-name
                                          lambda-list
                                          method
                                          path
                                          body-form
                                          &key
                                          documentation
                                          stream-documentation
                                          (stream-body-form nil
                                                            stream-body-form-supplied-p))
  "Define the JSON and streaming forms of one native endpoint.

BODY-FORM must be a literal one-argument lambda accepting a boolean stream
flag.  Its body is inlined with NIL for NAME and T for STREAM-NAME.
STREAM-BODY-FORM can replace it when the non-streaming request must omit a
field instead of sending its false value."
  (%expand-native-stream-pair name
                              stream-name
                              lambda-list
                              method
                              path
                              body-form
                              documentation
                              stream-documentation
                              stream-body-form
                              stream-body-form-supplied-p))
