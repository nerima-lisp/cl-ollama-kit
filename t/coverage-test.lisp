(in-package #:ollama-kit/test)

(defun coverage-tree-contains-symbol-p (tree symbol)
  (cond
    ((eq tree symbol) t)
    ((consp tree)
     (or (coverage-tree-contains-symbol-p (car tree) symbol)
         (coverage-tree-contains-symbol-p (cdr tree) symbol)))
    (t nil)))

(defun coverage-stream-response (&optional (payload (format nil "{}~%"))
                                   (content-type "application/x-ndjson"))
  (make-http-response
   :status 200
   :headers `(("content-type" . ,content-type))
   :stream (make-string-input-stream payload)))

(defun coverage-json-call (operation)
  (let ((value (funcall operation)))
    (assert (hash-table-p value))))

(defun coverage-stream-call (operation)
  (let ((stream (funcall operation)))
      (unwind-protect
         (multiple-value-bind (event present-p) (stream-next stream)
           (assert (hash-table-p event))
           (assert present-p))
      (stream-close stream))))

(defun coverage-path-p (request path)
  (assert (http-request-p request))
  (assert (stringp path))
  (let* ((url (http-request-url request))
         (authority-start (+ (or (search "://" url) -3) 3))
         (path-start (or (position #\/ url :start authority-start)
                         (length url)))
         (path-end (or (position #\? url :start path-start)
                       (position #\# url :start path-start)
                       (length url))))
    (string= path (subseq url path-start path-end))))

(describe "native endpoint families"
  (it "covers JSON and streaming endpoint declarations"
    (let* ((captured (list nil))
          (json-client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf (car captured) request)
               (response-with-text "{}"))))
          (stream-client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf (car captured) request)
               (coverage-stream-response)))))
      (coverage-json-call
       (lambda ()
         (chat json-client "model"
               (list (make-message "user" "hello")))))
      (assert (coverage-path-p (car captured) "/api/chat"))
      (coverage-json-call
       (lambda () (embed json-client "model" '("one" "two"))))
      (assert (coverage-path-p (car captured) "/api/embed"))
      (coverage-json-call
       (lambda () (show-model json-client "model")))
      (assert (coverage-path-p (car captured) "/api/show"))
      (coverage-json-call
       (lambda () (copy-model json-client "source" "destination")))
      (assert (coverage-path-p (car captured) "/api/copy"))
      (coverage-json-call
       (lambda () (delete-model json-client "model")))
      (assert (coverage-path-p (car captured) "/api/delete"))
      (coverage-json-call
       (lambda () (pull-model json-client "model")))
      (assert (coverage-path-p (car captured) "/api/pull"))
      (coverage-json-call
       (lambda () (push-model json-client "model")))
      (assert (coverage-path-p (car captured) "/api/push"))
      (coverage-stream-call
       (lambda () (chat-stream stream-client "model" #())))
      (assert (coverage-path-p (car captured) "/api/chat"))
      (coverage-json-call
       (lambda () (embed json-client "model" '("one" "two")
                          :dimensions 768
                          :keep-alive "5m")))
      (assert (coverage-path-p (car captured) "/api/embed"))
      (coverage-stream-call
       (lambda () (create-model-stream stream-client "model")))
      (assert (coverage-path-p (car captured) "/api/create"))
      (coverage-stream-call
       (lambda () (pull-model-stream stream-client "model")))
      (assert (coverage-path-p (car captured) "/api/pull"))
      (coverage-stream-call
       (lambda () (push-model-stream stream-client "model")))
      (assert (coverage-path-p (car captured) "/api/push")))))

(describe "web endpoint families"
  (it "covers search and fetch operations"
    (let* ((captured (list nil))
           (client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (response-with-text "{}")))))
      (coverage-json-call (lambda () (web-search client "query")))
      (assert (coverage-path-p (car captured) "/api/web_search"))
      (coverage-json-call
       (lambda () (web-search client "query" :max-results 5)))
      (assert (coverage-path-p (car captured) "/api/web_search"))
      (coverage-json-call
       (lambda () (web-fetch client "https://example.com")))
      (assert (coverage-path-p (car captured) "/api/web_fetch")))))

(describe "OpenAI-compatible endpoint families"
  (it "covers model, completion, embedding, response, and image operations"
    (let* ((captured (list nil))
          (client
            (openai-client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf (car captured) request)
               (response-with-text "{}"))))
          (body (json-object "model" "model")))
      (coverage-json-call (lambda () (openai-models client)))
      (assert (coverage-path-p (car captured) "/v1/models"))
      (coverage-json-call (lambda () (openai-model client "model")))
      (assert (coverage-path-p (car captured) "/v1/models/model"))
      (coverage-json-call (lambda () (openai-chat-completions client body)))
      (assert (coverage-path-p (car captured) "/v1/chat/completions"))
      (coverage-json-call (lambda () (openai-completions client body)))
      (assert (coverage-path-p (car captured) "/v1/completions"))
      (coverage-json-call (lambda () (openai-embeddings client body)))
      (assert (coverage-path-p (car captured) "/v1/embeddings"))
      (coverage-json-call (lambda () (openai-responses client body)))
      (assert (coverage-path-p (car captured) "/v1/responses"))
      (coverage-json-call (lambda () (openai-images client body)))
      (assert (coverage-path-p (car captured) "/v1/images/generations")))))

  (it "forces stream mode for every OpenAI streaming operation"
    (let* ((captured (list nil))
          (client
            (openai-client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf (car captured) request)
               (make-http-response
                :status 200
                :headers '(("content-type" . "text/event-stream"))
                :stream (make-string-input-stream
                         (format nil "data: {}~%~%data: [DONE]~%~%"))))))
          (body (json-object "model" "model")))
      (coverage-stream-call
       (lambda () (openai-chat-completions-stream client body)))
      (assert (coverage-path-p (car captured) "/v1/chat/completions"))
      (assert (eq t (gethash "stream" (request-json-object (car captured)))))
      (coverage-stream-call
       (lambda () (openai-completions-stream client body)))
      (assert (coverage-path-p (car captured) "/v1/completions"))
      (coverage-stream-call
       (lambda () (openai-responses-stream client body)))
      (assert (coverage-path-p (car captured) "/v1/responses"))))

(describe "argument and continuation contracts"
  (it "rejects unsafe OpenAI model names"
    (let ((client
            (openai-client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (response-with-text "{}"))))
          (invalid-models
            (list nil "" "model name" "model?" "model#" "model%"
                  "/model" "\\model" "." ".."
                  (string (code-char 127))))
          (rejected 0))
      (dolist (model invalid-models)
        (handler-case
            (openai-model client model)
          (ollama-argument-error () (incf rejected))))
      (assert (= (length invalid-models) rejected))))

  (it "validates continuation functions and propagates continuation errors"
    (let ((client (queued-client (response-with-text "{}")))
          (rejected nil))
      (handler-case
          (progn
            (call-with-json client :get "/version" nil #'identity)
            (assert nil))
        (ollama-argument-error () (setf rejected t)))
      (assert rejected)
      (setf rejected nil)
      (handler-case
          (progn
            (call-with-json (queued-client (response-with-text "{}"))
                            :get "/version" #'identity nil)
            (assert nil))
        (ollama-argument-error () (setf rejected t)))
      (assert rejected))
    (let ((response nil))
      (handler-case
          (progn
            (call-with-json
             (queued-client (response-with-text "{}"))
             :get "/version"
             (lambda (value returned-response)
               (declare (ignore value))
               (setf response returned-response)
               (error "success continuation"))
             (lambda (condition)
               (declare (ignore condition))
               (error "failure continuation")))
            (assert nil))
        (simple-error (condition)
          (assert (equal "success continuation"
                         (simple-condition-format-control condition)))))
      (close-http-response response))
  (handler-case
        (progn
          (call-with-json
           (queued-client (response-with-text "{\"error\":\"no\"}" :status 400))
           :get "/version"
           (lambda (&rest values) (declare (ignore values)))
           (lambda (condition)
             (declare (ignore condition))
             (error "failure continuation")))
          (assert nil))
      (simple-error (condition)
        (assert (equal "failure continuation"
                       (simple-condition-format-control condition))))))

  (it "dispatches stream continuations and validates their contracts"
    (with-continuation-values
        (values next called-p)
        (call-with-stream
         #'open-ollama-stream
         (queued-client (coverage-stream-response))
         :post "/generate"
         (lambda (stream)
           (next stream))
         (lambda (condition)
           (next condition)))
      (assert called-p)
      (let ((stream (first values)))
        (assert (ollama-stream-p stream))
        (stream-close stream)))
    (with-continuation-values
        (values next called-p)
        (call-with-stream
         #'open-ollama-stream
         (queued-client
          (response-with-text "{\"error\":\"missing\"}" :status 404))
         :post "/generate"
         (lambda (&rest ignored)
           (declare (ignore ignored))
           (error "stream success continuation must not run"))
         (lambda (condition)
           (next condition)))
      (assert called-p)
      (assert (typep (first values) 'ollama-api-error)))
    (flet ((reject (opener success failure)
             (handler-case
                 (progn
                   (call-with-stream
                    opener
                    (queued-client (coverage-stream-response))
                    :get "/version"
                    success
                    failure)
                   nil)
               (ollama-argument-error () t))))
      (assert (reject nil #'identity #'identity))
      (assert (reject #'open-ollama-stream nil #'identity))
      (assert (reject #'open-ollama-stream #'identity nil)))))
 (describe "HTTP data contracts"
  (it "accepts valid request and response representations"
    (let ((request
            (make-http-request
             :method 'post
             :url "http://localhost:11434/api/version"
             :headers '((content-type . "text/plain"))
             :body "hello"
             :stream-p t))
          (response
            (make-http-response
             :status 204
             :headers '((content-type . "text/plain"))
             :body ""))
          (default-request
            (make-http-request
             :url "http://localhost:11434/api/version")))
      (assert (eq :post (http-request-method request)))
      (assert (eq :get (http-request-method default-request)))
      (assert (http-request-stream-p request))
      (assert (response-success-p response))
      (close-http-response response)))

  (it "rejects malformed HTTP request and response values"
    (dolist (thunk
              (list
               (lambda () (make-http-request :url nil))
               (lambda () (make-http-request :url "ftp://localhost/path"))
               (lambda () (make-http-request
                            :url "http://localhost/path#fragment"))
               (lambda () (make-http-request
                            :url "http://user@localhost/path"))
               (lambda () (make-http-request
                            :url "http://localhost/../path"))
               (lambda () (make-http-request
                            :url "http://localhost/path" :body 42))
               (lambda () (make-http-request
                            :url "http://localhost/path"
                            :headers '(("bad name" . "value"))))
               (lambda () (make-http-response :status 99))
               (lambda () (make-http-response :status 200
                                               :body "a"
                                               :stream (make-string-input-stream "")))
               (lambda () (make-http-response :status 200 :stream 42))
               (lambda () (make-http-response :status 200 :close-function 42))))
      (handler-case
          (progn (funcall thunk) (assert nil))
        (ollama-argument-error () t)))))

(describe "endpoint macro lambda-list helpers"
  (it "handles supported spec shapes and rejects incomplete endpoints"
    (assert (eq 'timeout
                (ollama-kit::%lambda-list-spec-variable
                 '((:timeout timeout) nil))))
    (assert (eq 'timeout
                (ollama-kit::%lambda-list-spec-variable '(timeout nil))))
    (assert (null
             (ollama-kit::%lambda-list-spec-variable 42)))
    (assert (null
             (ollama-kit::%endpoint-keyword-variable '(client) "TIMEOUT")))
    (assert (null
             (ollama-kit::%endpoint-keyword-variable
              '(client &key ((:other 42) nil))
              "TIMEOUT")))
    (handler-case
        (progn
          (ollama-kit::%endpoint-keyword-variables
           '(client &key timeout))
          (assert nil))
      (program-error () t))
    (assert (equal
             '(let ((stream-p nil))
                (if stream-p :stream :json))
             (ollama-kit::%inline-stream-body-form
              '(lambda (stream-p)
                 (if stream-p :stream :json))
              nil)))
    (assert
     (not
      (coverage-tree-contains-symbol-p
       (macroexpand-1
       '(ollama-kit::define-native-stream-pair generated-endpoint
            generated-stream
            (client &key timeout headers)
            :post "/generate"
            (lambda (stream-p)
              (if stream-p :stream :json))))
       'funcall)))
    (assert
     (not
      (coverage-tree-contains-symbol-p
       (macroexpand-1
        '(ollama-kit::define-native-stream-pair generated-endpoint
            generated-stream
            (client &key timeout headers)
            :post "/generate"
            (lambda (stream-p)
              (if stream-p :stream :json))
            :stream-body-form
            (lambda (stream-p)
              (if stream-p :explicit-stream :explicit-json))))
       'funcall)))
    (dolist (body-form '(42
                         (quote not-a-lambda)
                         (lambda (stream-p extra) stream-p)
                         (lambda (:stream-p) stream-p)
                         (lambda stream-p stream-p)))
      (handler-case
          (progn
            (ollama-kit::%inline-stream-body-form body-form nil)
            (assert nil))
        (program-error () t)))))
