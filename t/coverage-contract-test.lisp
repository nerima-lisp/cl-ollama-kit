(in-package #:ollama-kit/test)

(describe "argument and continuation contracts"
          (it "rejects unsafe OpenAI model names"
              (let ((client
                     (client-with-request-function
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
           (let* ((client
                   (client-with-request-function
                    (lambda (request &key timeout)
                      (declare (ignore request timeout))
                      (response-with-text "{}"))))
                  (error-client
                   (client-with-request-function
                    (lambda (request &key timeout)
                      (declare (ignore request timeout))
                      (response-with-text "{\"error\":\"no\"}" :status 400))))
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
                             (call-with-json client
                                             :get
                                             "/version"
                                             #'identity
                                             nil)
                             (assert nil))
               (ollama-argument-error ()
                 (setf rejected t)))
             (assert rejected)
             (let ((response nil))
               (handler-case (progn
                               (call-with-json client
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
               (assert (http-message-kit:http-response-p response)))
             (handler-case (progn
                             (call-with-json error-client
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
                         (simple-condition-format-control condition))))))))

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
                              (progn
                                (assert
                                 (equal
                                  '(client body
                                           event-function
                                           &key
                                           timeout
                                           headers
                                           (response-timeout
                                            ollama-kit::+timeout-unspecified+)
                                           (idle-timeout
                                            ollama-kit::+timeout-unspecified+)
                                           cancel-token)
                                  (ollama-kit::%validate-stream-endpoint-lambda-list
                                   '(client body
                                            event-function
                                            &key
                                            timeout
                                            headers
                                            (response-timeout
                                             ollama-kit::+timeout-unspecified+)
                                            (idle-timeout
                                             ollama-kit::+timeout-unspecified+)
                                            cancel-token))))
                                (ollama-kit::%validate-stream-endpoint-lambda-list
                                 '(client &key timeout headers)))
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
                   '((ollama-kit::define-json-endpoint ollama-kit::%request-json-value :endpoint
                                                              (client &key
                                                                      timeout
                                                                      headers)
                                                              :get
                                                              "/version")
                     (ollama-kit::define-json-endpoint ollama-kit::%request-json-value endpoint
                                                              (&key timeout
                                                                    headers)
                                                              :get
                                                              "/version")
                     (ollama-kit::define-json-endpoint ollama-kit::%request-json-value endpoint
                                                              (client &key
                                                                      timeout
                                                                      headers)
                                                              get
                                                              "/version")
                     (ollama-kit::define-json-endpoint ollama-kit::%request-json-value endpoint
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
               (let ((expansion
                      (macroexpand-1
                       '(ollama-kit::define-native-stream-pair
                         generated-endpoint
                         generated-stream
                         (client &key timeout headers)
                         :post
                         "/generate"
                         (lambda (stream-p)
                           (if stream-p
                               :stream
                               :json))))))
                 (and (not (coverage-tree-contains-symbol-p expansion 'funcall))
                      (coverage-tree-contains-symbol-p expansion
                                                       'call-with-ollama-stream)
                      (coverage-tree-contains-symbol-p expansion
                                                       'ollama-kit::event-function)
                      (coverage-tree-contains-symbol-p expansion
                                                       'ollama-kit::response-timeout)
                      (coverage-tree-contains-symbol-p expansion
                                                       'ollama-kit::idle-timeout)
                      (coverage-tree-contains-symbol-p expansion
                                                       'ollama-kit::cancel-token))))
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
                                                         event-function
                                                         &key
                                                         timeout
                                                         headers
                                                         response-timeout
                                                         idle-timeout
                                                         cancel-token)
                                                 :post
                                                 "/stream"
                                                 nil)))
                                (assert nil))
                  (program-error ()
                    t)))))

(describe "coverage boundary contracts"
          (it "executes inline input, JSON, and native option helpers"
              (locally
                (declare (notinline ollama-kit::%utf8-character-octets
                                    ollama-kit::%utf8-octet-length
                                    ollama-kit::%json-supplied-p
                                    ollama-kit::%json-enum
                                    ollama-kit::%json-array
                                    ollama-kit::%optional-json-pair
                                    ollama-kit::%stream-option-pair
                                    ollama-kit::%native-bool
                                    ollama-kit::%native-think))
                (assert
                 (= 1 (ollama-kit::%utf8-character-octets (code-char #x41))))
                (assert
                 (= 2 (ollama-kit::%utf8-character-octets (code-char #xe9))))
                (assert
                 (= 3 (ollama-kit::%utf8-character-octets (code-char #x20ac))))
                (assert
                 (= 4 (ollama-kit::%utf8-character-octets (code-char #x1d11e))))
                (assert
                 (= 10
                    (ollama-kit::%utf8-octet-length
                     (coerce
                      (list (code-char #x41)
                            (code-char #xe9)
                            (code-char #x20ac)
                            (code-char #x1d11e))
                      'string))))
                (assert
                 (not
                  (ollama-kit::%json-supplied-p ollama-kit::+json-unspecified+)))
                (assert (ollama-kit::%json-supplied-p nil))
                (assert (equal "user" (ollama-kit::%json-enum :user)))
                (assert (equal "value" (ollama-kit::%json-enum "value")))
                (let ((vector #(1 2 3)))
                  (assert (eq vector (ollama-kit::%json-array vector))))
                (assert (equalp #(1 2 3) (ollama-kit::%json-array '(1 2 3))))
                (assert (eql 7 (ollama-kit::%json-array 7)))
                (assert
                 (null
                  (ollama-kit::%optional-json-pair "missing"
                                                   ollama-kit::+json-unspecified+)))
                (assert
                 (equal '("value" . 7)
                        (ollama-kit::%optional-json-pair "value" 7)))
                (assert
                 (equal '("value" . 8)
                        (ollama-kit::%optional-json-pair "value" 7 #'1+)))
                (assert
                 (equal '("stream" . t) (ollama-kit::%stream-option-pair t)))
                (assert
                 (eq json-kit:+json-false+
                     (cdr (ollama-kit::%stream-option-pair nil))))
                (assert
                 (eq json-kit:+json-false+ (ollama-kit::%native-bool nil)))
                (assert
                 (eq json-kit:+json-false+
                     (ollama-kit::%native-bool json-kit:+json-false+)))
                (assert (eq t (ollama-kit::%native-bool t)))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%native-bool 7))))
                (assert (equal "low" (ollama-kit::%json-enum :low)))
                (assert (equal "low" (ollama-kit::%json-enum "low")))
                (assert (equal "low" (ollama-kit::%native-think :low)))
                (assert (equal "low" (ollama-kit::%native-think "low")))
                (assert
                 (eq json-kit:+json-false+ (ollama-kit::%native-think nil)))
                (assert (eq t (ollama-kit::%native-think t)))
                (assert
                 (eq json-kit:+json-false+
                     (ollama-kit::%native-think json-kit:+json-false+)))))
          (it
           "rejects native stream pairs without a keyword lambda-list section"
           (handler-case (progn
                           (macroexpand-1
                            '(ollama-kit::define-native-stream-pair endpoint
                                                                    endpoint-stream
                                                                    (client)
                                                                    :post
                                                                    "/generate"
                                                                    (lambda
                                                                        (stream-p)
                                                                      stream-p)))
                           (assert nil))
             (program-error ()
               t))))
