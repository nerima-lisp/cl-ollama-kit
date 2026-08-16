(in-package #:ollama-kit/test)

(describe "argument and continuation contracts"
          (it "rejects unsafe OpenAI model names"
              (let ((client
                     (openai-client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{}"))))
                    (invalid-models
                     (list nil
                           ""
                           "model name"
                           "model?"
                           "model#"
                           "model%"
                           "/model"
                           "\\model"
                           "."
                           ".."
                           (string (code-char 127))))
                    (rejected 0))
                (dolist (model invalid-models)
                  (handler-case (openai-model client model)
                    (ollama-argument-error ()
                      (incf rejected))))
                (assert (= (length invalid-models) rejected))))
          (it
           "validates continuation functions and propagates continuation errors"
           (let ((client (queued-client (response-with-text "{}")))
                 (rejected nil))
             (handler-case (progn
                             (call-with-json client
                                             :get
                                             "/version"
                                             nil
                                             #'identity)
                             (assert nil))
               (ollama-argument-error ()
                 (setf rejected t)))
             (assert rejected)
             (setf rejected nil)
             (handler-case (progn
                             (call-with-json
                              (queued-client (response-with-text "{}"))
                              :get
                              "/version"
                              #'identity
                              nil)
                             (assert nil))
               (ollama-argument-error ()
                 (setf rejected t)))
             (assert rejected))
           (let ((response nil))
             (handler-case (progn
                             (call-with-json
                              (queued-client (response-with-text "{}"))
                              :get
                              "/version"
                              (lambda (value returned-response)
                                (declare (ignore value))
                                (setf response returned-response)
                                (error "success continuation"))
                              (lambda (condition)
                                (declare (ignore condition))
                                (error "failure continuation")))
                             (assert nil))
               (simple-error (condition)
                 (assert
                  (equal "success continuation"
                         (simple-condition-format-control condition)))))
             (close-http-response response))
           (handler-case (progn
                           (call-with-json
                            (queued-client
                             (response-with-text "{\"error\":\"no\"}"
                                                 :status
                                                 400))
                            :get
                            "/version"
                            (lambda (&rest values)
                              (declare (ignore values)))
                            (lambda (condition)
                              (declare (ignore condition))
                              (error "failure continuation")))
                           (assert nil))
             (simple-error (condition)
               (assert
                (equal "failure continuation"
                       (simple-condition-format-control condition))))))
          (it "dispatches stream continuations and validates their contracts"
              (with-continuation-values (values next called-p)
                                        (call-with-stream #'open-ollama-stream
                                                          (queued-client
                                                           (coverage-stream-response))
                                                          :post
                                                          "/generate"
                                                          (lambda (stream)
                                                            (next stream))
                                                          (lambda (condition)
                                                            (next condition)))
                                        (assert called-p)
                                        (let ((stream (first values)))
                                          (assert (ollama-stream-p stream))
                                          (stream-close stream)))
              (with-continuation-values (values next called-p)
                                        (call-with-stream #'open-ollama-stream
                                                          (queued-client
                                                           (response-with-text
                                                            "{\"error\":\"missing\"}"
                                                            :status
                                                            404))
                                                          :post
                                                          "/generate"
                                                          (lambda
                                                              (&rest ignored)
                                                            (declare (ignore
                                                                      ignored))
                                                            (error
                                                             "stream success continuation must not run"))
                                                          (lambda (condition)
                                                            (next condition)))
                                        (assert called-p)
                                        (assert
                                         (typep (first values)
                                                'ollama-api-error)))
              (flet ((reject (opener success failure)
                       (handler-case (progn
                                       (call-with-stream opener
                                                         (queued-client
                                                          (coverage-stream-response))
                                                         :get
                                                         "/version"
                                                         success
                                                         failure)
                                       nil)
                         (ollama-argument-error ()
                           t))))
                (assert (reject nil #'identity #'identity))
                (assert (reject #'open-ollama-stream nil #'identity))
                (assert (reject #'open-ollama-stream #'identity nil)))))

(describe "HTTP data contracts"
          (it "accepts valid request and response representations"
              (let ((request
                     (make-http-request :method
                                        'post
                                        :url
                                        "http://localhost:11434/api/version"
                                        :headers
                                        '((content-type . "text/plain"))
                                        :body
                                        "hello"
                                        :stream-p
                                        t))
                    (response
                     (make-http-response :status
                                         204
                                         :headers
                                         '((content-type . "text/plain"))
                                         :body
                                         ""))
                    (default-request
                     (make-http-request :url
                                        "http://localhost:11434/api/version")))
                (assert (eq :post (http-request-method request)))
                (assert (eq :get (http-request-method default-request)))
                (assert (http-request-stream-p request))
                (assert (response-success-p response))
                (close-http-response response)))
          (it "rejects malformed HTTP request and response values"
              (dolist
                  (thunk
                   (list
                    (lambda ()
                      (make-http-request :url nil))
                    (lambda ()
                      (make-http-request :url "ftp://localhost/path"))
                    (lambda ()
                      (make-http-request :url "http://localhost/path#fragment"))
                    (lambda ()
                      (make-http-request :url "http://user@localhost/path"))
                    (lambda ()
                      (make-http-request :url "http://localhost/../path"))
                    (lambda ()
                      (make-http-request :url "http://localhost/path" :body 42))
                    (lambda ()
                      (make-http-request :url
                                         "http://localhost/path"
                                         :headers
                                         '(("bad name" . "value"))))
                    (lambda ()
                      (make-http-response :status 99))
                    (lambda ()
                      (make-http-response :status
                                          200
                                          :body
                                          "a"
                                          :stream
                                          (make-string-input-stream "")))
                    (lambda ()
                      (make-http-response :status 200 :stream 42))
                    (lambda ()
                      (make-http-response :status 200 :close-function 42))))
                (handler-case (progn
                                (funcall thunk)
                                (assert nil))
                  (ollama-argument-error ()
                    t)))))

(describe "endpoint macro lambda-list helpers"
          (it "handles supported spec shapes and rejects incomplete endpoints"
              (assert (ollama-kit::%valid-endpoint-name-p 'endpoint))
              (assert (not (ollama-kit::%valid-endpoint-name-p :endpoint)))
              (assert (not (ollama-kit::%valid-endpoint-name-p 42)))
              (assert
               (ollama-kit::%valid-endpoint-lambda-list-p
                '(client &key timeout headers)))
              (assert
               (not
                (ollama-kit::%valid-endpoint-lambda-list-p
                 '(&key timeout headers))))
              (assert (not (ollama-kit::%valid-endpoint-lambda-list-p 42)))
              (assert (ollama-kit::%valid-endpoint-method-p :post))
              (assert (not (ollama-kit::%valid-endpoint-method-p 'post)))
              (assert (ollama-kit::%valid-endpoint-path-p "/generate"))
              (assert (not (ollama-kit::%valid-endpoint-path-p nil)))
              (assert (not (ollama-kit::%valid-endpoint-path-p "")))
              (assert (not (ollama-kit::%valid-endpoint-path-p "generate")))
              (assert
               (not
                (ollama-kit::%valid-endpoint-path-p "/generate?stream=true")))
              (assert
               (not (ollama-kit::%valid-endpoint-path-p "/generate#fragment")))
              (multiple-value-bind (name lambda-list method path stream-name)
                  (ollama-kit::%validate-endpoint-declaration 'endpoint
                                                              '(client &key
                                                                       timeout
                                                                       headers)
                                                              :post
                                                              "/generate"
                                                              'endpoint-stream)
                (assert (eq 'endpoint name))
                (assert (equal '(client &key timeout headers) lambda-list))
                (assert (eq :post method))
                (assert (string= "/generate" path))
                (assert (eq 'endpoint-stream stream-name)))
              (handler-case (progn
                              (ollama-kit::%validate-endpoint-declaration
                               'endpoint
                               '(client &key timeout headers)
                               :post
                               "/generate"
                               :endpoint-stream)
                              (assert nil))
                (program-error ()
                  t))
              (handler-case (progn
                              (ollama-kit::%validate-stream-endpoint-lambda-list
                               '(client &key timeout headers))
                              (assert nil))
                (program-error ()
                  t))
              (handler-case (progn
                              (ollama-kit::%validate-stream-endpoint-lambda-list
                               '(&key timeout headers))
                              (assert nil))
                (program-error ()
                  t))
              (dolist
                  (declaration
                   '((ollama-kit::define-native-json-endpoint :endpoint
                                                              (client &key
                                                                      timeout
                                                                      headers)
                                                              :get
                                                              "/version")
                     (ollama-kit::define-native-json-endpoint endpoint
                                                              (&key timeout
                                                                    headers)
                                                              :get
                                                              "/version")
                     (ollama-kit::define-native-json-endpoint endpoint
                                                              (client &key
                                                                      timeout
                                                                      headers)
                                                              get
                                                              "/version")
                     (ollama-kit::define-native-json-endpoint endpoint
                                                              (client &key
                                                                      timeout
                                                                      headers)
                                                              :get
                                                              "version")
                     (ollama-kit::define-openai-stream-endpoint endpoint
                                                                (client &key
                                                                        timeout
                                                                        headers)
                                                                :get
                                                                "/models")
                     (ollama-kit::define-native-stream-pair endpoint
                                                            nil
                                                            (client &key
                                                                    timeout
                                                                    headers)
                                                            :post
                                                            "/generate"
                                                            nil)))
                (handler-case (progn
                                (macroexpand-1 declaration)
                                (assert nil))
                  (program-error ()
                    t)))
              (assert
               (eq 'timeout
                   (ollama-kit::%lambda-list-spec-variable
                    '((:timeout timeout) nil))))
              (assert
               (eq 'timeout
                   (ollama-kit::%lambda-list-spec-variable '(timeout nil))))
              (assert (null (ollama-kit::%lambda-list-spec-variable 42)))
              (assert
               (null
                (ollama-kit::%endpoint-keyword-variable '(client) "TIMEOUT")))
              (assert
               (null
                (ollama-kit::%endpoint-keyword-variable
                 '(client &key ((:other 42) nil))
                 "TIMEOUT")))
              (handler-case (progn
                              (ollama-kit::%endpoint-keyword-variables
                               '(client &key timeout))
                              (assert nil))
                (program-error ()
                  t))
              (assert
               (equal
                '(let ((stream-p nil))
                   (if stream-p
                       :stream
                       :json))
                (ollama-kit::%inline-stream-body-form
                 '(lambda (stream-p)
                    (if stream-p
                        :stream
                        :json))
                 nil)))
              (assert
               (not
                (coverage-tree-contains-symbol-p
                 (macroexpand-1
                  '(ollama-kit::define-native-stream-pair generated-endpoint
                                                          generated-stream
                                                          (client &key
                                                                  timeout
                                                                  headers)
                                                          :post
                                                          "/generate"
                                                          (lambda (stream-p)
                                                            (if stream-p
                                                                :stream
                                                                :json))))
                 'funcall)))
              (assert
               (not
                (coverage-tree-contains-symbol-p
                 (macroexpand-1
                  '(ollama-kit::define-native-stream-pair generated-endpoint
                                                          generated-stream
                                                          (client &key
                                                                  timeout
                                                                  headers)
                                                          :post
                                                          "/generate"
                                                          (lambda (stream-p)
                                                            (if stream-p
                                                                :stream
                                                                :json))
                                                          :stream-body-form
                                                          (lambda (stream-p)
                                                            (if stream-p
                                                                :explicit-stream
                                                                :explicit-json))))
                 'funcall)))
              (dolist
                  (body-form
                   '(42 (quote not-a-lambda)
                        (lambda (stream-p extra)
                          stream-p)
                        (lambda (:stream-p)
                          stream-p)
                        (lambda stream-p
                          stream-p)))
                (handler-case (progn
                                (ollama-kit::%inline-stream-body-form body-form
                                                                      nil)
                                (assert nil))
                  (program-error ()
                    t)))
              (dolist (arguments '((42 stream-transformer) (stream-opener 42)))
                (handler-case (progn
                                (apply #'ollama-kit::%expand-stream-endpoint
                                       (append arguments
                                               '(generated-stream-endpoint
                                                 (client body
                                                         &key
                                                         timeout
                                                         headers)
                                                 :post
                                                 "/stream"
                                                 nil)))
                                (assert nil))
                  (program-error ()
                    t)))))
