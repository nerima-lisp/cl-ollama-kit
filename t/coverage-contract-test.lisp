(in-package #:ollama-kit/test)

(describe "generated endpoint macro contracts"
          (it "defines JSON endpoints and rejects non-symbol request functions"
              (eval
               '(ollama-kit::define-json-endpoint
                 ollama-kit::%request-json-value
                 generated-json-endpoint
                 (ollama-kit::client &key
                                     ollama-kit::timeout
                                     ollama-kit::headers)
                 :post
                 "/coverage"
                 :documentation
                 "Generated JSON endpoint."))
              (let* ((lambda-list-function
                      (progn
                        (require :sb-introspect)
                        (symbol-function
                         (find-symbol "FUNCTION-LAMBDA-LIST" "SB-INTROSPECT"))))
                     (sent-request nil)
                     (sent-timeout nil)
                     (client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (setf sent-request request
                               sent-timeout timeout)
                         (response-with-text "{\"event\":\"observed\"}"))
                       :base-url
                       "http://localhost"))
                     (result nil))
                (unwind-protect
                    (progn
                      (assert (fboundp 'generated-json-endpoint))
                      (assert
                       (equal '("CLIENT" "&KEY" "TIMEOUT" "HEADERS")
                              (mapcar #'symbol-name
                                      (funcall lambda-list-function
                                               (fdefinition
                                                'generated-json-endpoint)))))
                      (setf result (funcall
                                    (fdefinition 'generated-json-endpoint)
                                    client
                                    :timeout
                                    17
                                    :headers
                                    '(("x-coverage" . "json-endpoint"))))
                      (assert (http-message-kit:http-request-p sent-request))
                      (assert
                       (string= "POST"
                                (http-message-kit:http-request-method
                                 sent-request)))
                      (assert
                       (string= "/coverage"
                                (http-message-kit:http-request-target
                                 sent-request)))
                      (assert (= 17 sent-timeout))
                      (assert
                       (string= "json-endpoint"
                                (http-message-kit:http-header-value
                                 (http-message-kit:http-request-headers
                                  sent-request)
                                 "x-coverage")))
                      (assert (equal "observed" (gethash "event" result))))
                  (close-client client)))
              (handler-case (progn
                              (macroexpand-1
                               '(ollama-kit::define-json-endpoint
                                 (function list)
                                 generated-invalid-endpoint
                                 (ollama-kit::client &key
                                                     ollama-kit::timeout
                                                     ollama-kit::headers)
                                 :get
                                 "/invalid"))
                              (assert nil))
                (program-error ()
                  t)))
          (it "defines each event stream wrapper with its declared behavior"
              (let ((lambda-list-function
                     (progn
                       (require :sb-introspect)
                       (symbol-function
                        (find-symbol "FUNCTION-LAMBDA-LIST" "SB-INTROSPECT")))))
                (dolist
                    (contract
                     '((ollama-kit::call-with-openai-stream :sse
                                                            "text/event-stream")
                       (ollama-kit::call-with-ollama-stream :ndjson
                                                            "application/x-ndjson")
                       (ollama-kit::call-with-anthropic-stream :sse
                                                               "text/event-stream")))
                  (destructuring-bind (name wire-format accept) contract
                    (macroexpand-1
                     `(ollama-kit::define-event-stream-consumer ,name
                                                                ,wire-format
                                                                ,accept
                                                                "Generated event stream consumer."))
                    (let* ((sent-request nil)
                           (events nil)
                           (client
                            (client-with-request-function
                             (lambda (request &key timeout)
                               (declare (ignore timeout))
                               (setf sent-request request)
                               (response-with-text
                                (if (eq wire-format :ndjson)
                                    (format nil "{\"event\":\"observed\"}~%")
                                    (format nil
                                            "data: {\"event\":\"observed\"}~%~%"))))
                             :base-url
                             "http://localhost")))
                      (unwind-protect
                          (progn
                            (assert (fboundp name))
                            (assert
                             (equal
                              '("CLIENT" "METHOD"
                                         "PATH"
                                         "EVENT-FUNCTION"
                                         "&REST"
                                         "OPTIONS")
                              (mapcar #'symbol-name
                                      (funcall lambda-list-function
                                               (fdefinition name)))))
                            (funcall (fdefinition name)
                                     client
                                     :post
                                     "/stream"
                                     (lambda (event)
                                       (push event events)
                                       :stop))
                            (assert
                             (http-message-kit:http-request-p sent-request))
                            (assert
                             (string= "POST"
                                      (http-message-kit:http-request-method
                                       sent-request)))
                            (assert
                             (string= "/stream"
                                      (http-message-kit:http-request-target
                                       sent-request)))
                            (assert
                             (string= accept
                                      (http-message-kit:http-header-value
                                       (http-message-kit:http-request-headers
                                        sent-request)
                                       "Accept")))
                            (assert (= 1 (length events)))
                            (assert
                             (equal "observed" (gethash "event" (first events)))))
                        (close-client client))))))))

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
                   '((ollama-kit::define-json-endpoint
                      ollama-kit::%request-json-value
                      :endpoint
                      (client &key timeout headers)
                      :get
                      "/version")
                     (ollama-kit::define-json-endpoint
                      ollama-kit::%request-json-value
                      endpoint
                      (&key timeout headers)
                      :get
                      "/version")
                     (ollama-kit::define-json-endpoint
                      ollama-kit::%request-json-value
                      endpoint
                      (client &key timeout headers)
                      get
                      "/version")
                     (ollama-kit::define-json-endpoint
                      ollama-kit::%request-json-value
                      endpoint
                      (client &key timeout headers)
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
              (let* ((lambda-list '(client &key timeout headers))
                     (body-form
                      '(lambda (stream-p)
                         (ollama-kit::%json-object
                          (cons "body-mode"
                                (if stream-p
                                    "stream"
                                    "json")))))
                     (form
                      (list 'ollama-kit::define-native-stream-pair
                            'generated-endpoint
                            'generated-stream
                            lambda-list
                            :post
                            "/generate"
                            body-form))
                     (expansion (macroexpand-1 form))
                     (json-definition (second expansion))
                     (stream-definition (third expansion)))
                (assert (eq 'progn (first expansion)))
                (assert (eq 'defun (first json-definition)))
                (assert (eq 'generated-endpoint (second json-definition)))
                (assert (equal lambda-list (third json-definition)))
                (assert (eq 'defun (first stream-definition)))
                (assert (eq 'generated-stream (second stream-definition)))
                (assert
                 (equal
                  '(client ollama-kit::event-function
                           &key
                           timeout
                           headers
                           (ollama-kit::response-timeout
                            ollama-kit::+timeout-unspecified+)
                           (ollama-kit::idle-timeout
                            ollama-kit::+timeout-unspecified+)
                           ollama-kit::cancel-token)
                  (third stream-definition)))
                (eval
                 '(ollama-kit::define-native-stream-pair generated-endpoint
                                                         generated-stream
                                                         (client &key
                                                                 timeout
                                                                 headers)
                                                         :post
                                                         "/generate"
                                                         (lambda (stream-p)
                                                           (ollama-kit::%json-object
                                                            (cons "body-mode"
                                                                  (if stream-p
                                                                      "stream"
                                                                      "json"))))))
                (let* ((json-body (make-hash-table :test (quote equal)))
                       (stream-body (make-hash-table :test (quote equal)))
                       (stream-event (make-hash-table :test (quote equal)))
                       (client
                        (client-with-request-function
                         (lambda (request &key timeout)
                           (declare (ignore timeout))
                           (let ((body (request-json-object request)))
                             (if (equal "stream" (gethash "body-mode" body))
                                 (setf stream-body body)
                                 (setf json-body body)))
                           (response-with-text
                            (format nil "{\"event\":\"observed\"}~%"))))))
                  (unwind-protect
                      (progn
                        (let ((json-result
                               (funcall (symbol-function 'generated-endpoint)
                                        client
                                        :timeout
                                        5
                                        :headers
                                        nil)))
                          (assert
                           (equal "observed" (gethash "event" json-result))))
                        (funcall (symbol-function 'generated-stream)
                                 client
                                 (lambda (event)
                                   (setf stream-event event)
                                   :stop)
                                 :timeout
                                 5
                                 :headers
                                 nil
                                 :response-timeout
                                 5
                                 :idle-timeout
                                 5
                                 :cancel-token
                                 (http-kit/client:make-http-cancellation-token))
                        (assert (equal "json" (gethash "body-mode" json-body)))
                        (assert
                         (equal "stream" (gethash "body-mode" stream-body)))
                        (assert
                         (equal "observed" (gethash "event" stream-event))))
                    (close-client client))))
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
                    t))))
          (it-each
           (("event function position"
             ollama-kit::%stream-endpoint-lambda-list-error
             (client body
                     &key
                     timeout
                     headers
                     cancel-token
                     response-timeout
                     idle-timeout)
             "Stream endpoint lambda list requires an event function before &key.")
            ("missing &key" ollama-kit::%stream-endpoint-lambda-list-error
                            (client body
                                    event-function
                                    timeout
                                    headers
                                    cancel-token
                                    response-timeout
                                    idle-timeout)
                            "Stream endpoint lambda list requires &key.")
            ("missing CANCEL-TOKEN"
             ollama-kit::%stream-endpoint-lambda-list-error
             (client body
                     event-function
                     &key
                     timeout
                     headers
                     response-timeout
                     idle-timeout)
             "Stream endpoint lambda list requires CANCEL-TOKEN."))
           "rejects ~A lambda lists for native stream endpoint macros"
           (reason expected-condition-type lambda-list expected-message)
           (dolist
               (macro
                '(ollama-kit::define-openai-stream-endpoint
                  ollama-kit::define-anthropic-stream-endpoint))
             (let ((condition nil))
               (handler-case (macroexpand-1
                              (list macro
                                    'generated-invalid-stream-endpoint
                                    lambda-list
                                    :post
                                    "/stream"))
                 (ollama-kit::%stream-endpoint-lambda-list-error (caught)
                   (setf condition caught)))
               (assert (typep condition expected-condition-type))
               (assert (typep condition 'program-error))
               (assert (string= expected-message (princ-to-string condition))))))
          (it-each
           (("RESPONSE-TIMEOUT"
             (client body
                     event-function
                     &key
                     timeout
                     headers
                     idle-timeout
                     cancel-token))
            ("IDLE-TIMEOUT"
             (client body
                     event-function
                     &key
                     timeout
                     headers
                     response-timeout
                     cancel-token)))
           "rejects native stream endpoints without ~A"
           (missing-timeout lambda-list)
           (dolist
               (macro
                (quote
                 (ollama-kit::define-openai-stream-endpoint
                  ollama-kit::define-anthropic-stream-endpoint)))
             (let ((condition nil))
               (handler-case (macroexpand-1
                              (list macro
                                    (quote generated-invalid-stream-endpoint)
                                    lambda-list
                                    :post
                                    "/stream"))
                 (program-error (caught)
                   (setf condition caught)))
               (assert (typep condition (quote program-error))))))
          (it-each
           ((ollama-kit::define-openai-stream-endpoint generated-openai-stream
                                                       (client body
                                                               event-function
                                                               &key
                                                               timeout
                                                               response-timeout
                                                               idle-timeout
                                                               headers
                                                               cancel-token))
            (ollama-kit::define-anthropic-stream-endpoint
             generated-anthropic-stream
             (client body
                     event-function
                     &key
                     timeout
                     response-timeout
                     idle-timeout
                     headers
                     cancel-token)))
           "expands ~A stream endpoint names and lambda lists"
           (macro expected-name lambda-list)
           (let ((expansion
                  (macroexpand-1
                   (list macro expected-name lambda-list :post "/stream"))))
             (assert (eq 'defun (first expansion)))
             (assert (eq expected-name (second expansion)))
             (assert (equal lambda-list (third expansion))))))

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
