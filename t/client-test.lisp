(in-package #:ollama-kit/test)

(describe "client and transport boundary"
          (it "serializes UTF-8 JSON through an injected boundary"
              (let ((captured nil)
                    (client nil))
                (setf client (client-with-request-function
                              (lambda (request &key timeout)
                                (declare (ignore timeout))
                                (setf captured request)
                                (response-with-text "{\"ok\":true}"))))
                (multiple-value-bind (value http-response)
                    (request-json client
                                  :post
                                  "/chat"
                                  :body
                                  (json-object "model" "tiny" "prompt" "日本😀"))
                  (assert (http-response-p http-response))
                  (assert (hash-table-p value))
                  (assert (eq t (gethash "ok" value)))
                  (assert (equal :post (http-request-method captured)))
                  (assert
                   (equal "http://localhost:11434/api/chat"
                          (http-request-url captured)))
                  (let ((payload
                         (json-kit:parse
                          (cl-codec-kit:octets-to-string
                           (http-request-body captured)
                           :encoding
                           :utf-8))))
                    (assert (equal "日本😀" (gethash "prompt" payload)))))))
          (it "adds authentication and JSON headers at the boundary"
              (let ((captured nil))
                (let ((client
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (response-with-text "{}"))
                        :api-key
                        "secret")))
                  (request-json client
                                :post
                                "/generate"
                                :body
                                (json-object "x" 1)))
                (assert
                 (equal "Bearer secret"
                        (cdr
                         (assoc "Authorization"
                                (http-request-headers captured)
                                :test
                                #'string-equal))))
                (assert
                 (equal "application/json; charset=utf-8"
                        (cdr
                         (assoc "Content-Type"
                                (http-request-headers captured)
                                :test
                                #'string-equal))))
                (assert
                 (equal "application/json"
                        (cdr
                         (assoc "Accept"
                                (http-request-headers captured)
                                :test
                                #'string-equal))))))
          (it "keeps raw request bodies and transfers response ownership"
              (let* ((body
                      (make-array 3
                                  :element-type
                                  '(unsigned-byte 8)
                                  :initial-contents
                                  '(1 2 3)))
                     (captured nil)
                     (close-count 0)
                     (response
                      (request-raw
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (make-http-response :status
                                              201
                                              :body
                                              "created"
                                              :close-function
                                              (lambda ()
                                                (incf close-count)))))
                       :post
                       "/blobs/sha256:abc"
                       :body
                       body
                       :content-type
                       "application/octet-stream"
                       :accept
                       "application/octet-stream")))
                (assert (= 201 (http-response-status response)))
                (assert (equalp body (http-request-body captured)))
                (assert
                 (equal "application/octet-stream"
                        (cdr
                         (assoc "Content-Type"
                                (http-request-headers captured)
                                :test
                                #'string-equal))))
                (assert
                 (equal "application/octet-stream"
                        (cdr
                         (assoc "Accept"
                                (http-request-headers captured)
                                :test
                                #'string-equal))))
                (assert (zerop close-count))
                (close-http-response response)
                (close-http-response response)
                (assert (= 1 close-count))))
          (it "checks and uploads blobs through the raw API boundary"
              (let ((captured nil))
                (let ((client
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (make-http-response :status 200 :body "ok")))))
                  (assert (blob-exists-p client "sha256:present"))
                  (assert (equal :head (http-request-method captured)))
                  (assert
                   (equal "http://localhost:11434/api/blobs/sha256:present"
                          (http-request-url captured))))
                (assert
                 (not
                  (blob-exists-p
                   (queued-client (response-with-text "missing" :status 404))
                   "sha256:missing")))
                (let ((captured nil)
                      (body
                       (make-array 2
                                   :element-type
                                   '(unsigned-byte 8)
                                   :initial-contents
                                   '(10 11))))
                  (let ((response
                         (push-blob
                          (client-with-request-function
                           (lambda (request &key timeout)
                             (declare (ignore timeout))
                             (setf captured request)
                             (make-http-response :status 201 :body "uploaded")))
                          "sha256:uploaded"
                          body)))
                    (unwind-protect
                        (progn
                          (assert (= 201 (http-response-status response)))
                          (assert (equal :post (http-request-method captured)))
                          (assert (equalp body (http-request-body captured)))
                          (assert
                           (equal "application/octet-stream"
                                  (cdr
                                   (assoc "Content-Type"
                                          (http-request-headers captured)
                                          :test
                                          #'string-equal))))
                          (assert
                           (null
                            (assoc "Accept"
                                   (http-request-headers captured)
                                   :test
                                   #'string-equal))))
                      (close-http-response response))))))
          (it "signals structured API errors and preserves the raw body"
              (let ((condition nil))
                (handler-case (request-json
                               (queued-client
                                (response-with-text
                                 "{\"error\":\"model missing\"}"
                                 :status
                                 404))
                               :get
                               "/tags")
                  (ollama-api-error (caught)
                    (setf condition caught)))
                (assert (typep condition 'ollama-http-error))
                (assert (= 404 (ollama-http-error-status condition)))
                (assert
                 (equal "model missing" (ollama-error-message condition)))
                (assert
                 (search "model missing" (ollama-http-error-body condition)))
                (assert (hash-table-p (ollama-api-error-data condition)))))
          (it "treats redirects and plain error bodies as failures"
              (dolist
                  (fixture
                   (list (cons 302 "redirect") (cons 500 "server error")))
                (let ((condition nil))
                  (handler-case (request-json
                                 (queued-client
                                  (response-with-text (cdr fixture)
                                                      :status
                                                      (car fixture)))
                                 :get
                                 "/version")
                    (ollama-http-error (caught)
                      (setf condition caught)))
                  (assert condition)
                  (assert
                   (= (car fixture) (ollama-http-error-status condition)))
                  (assert
                   (equal (cdr fixture) (ollama-http-error-body condition))))))
          (it "rejects a client without a transport boundary"
              (let ((signalled nil))
                (handler-case (make-client)
                  (ollama-argument-error ()
                    (setf signalled t)))
                (assert signalled)))
          (it "rejects unsafe HTTP header names and values"
              (dolist
                  (headers
                   (list (list (cons "Bad Header" "value"))
                         (list
                          (cons "X-Test"
                                (format nil
                                        "ok~C~CInjected: yes"
                                        #\Return
                                        #\Linefeed)))))
                (let ((signalled nil))
                  (handler-case (client-with-request-function
                                 (lambda (request &key timeout)
                                   (declare (ignore request timeout))
                                   (response-with-text "{}"))
                                 :headers
                                 headers)
                    (ollama-argument-error ()
                      (setf signalled t)))
                  (assert signalled))))
          (it "normalizes endpoint slashes without changing the base URL"
              (let ((captured nil))
                (let ((client
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (response-with-text "{}"))
                        :base-url
                        "http://127.0.0.1:11434/api/")))
                  (request-json client :get "//version"))
                (assert
                 (equal "http://127.0.0.1:11434/api/version"
                        (http-request-url captured)))))
          (it "rejects unsafe endpoints and ambiguous authorization"
              (dolist
                  (base-url
                   (list "http:///api"
                         "http://[::1/api"
                         "http://:11434/api"
                         "http://localhost:bad/api"
                         "http://localhost:1:2/api"
                         "http://[::1]:/api"
                         "http://[::1]:65536/api"
                         "http://localhost:11434/api/../secret"))
                (let ((signalled nil))
                  (handler-case (client-with-request-function
                                 (lambda (request &key timeout)
                                   (declare (ignore request timeout))
                                   (response-with-text "{}"))
                                 :base-url
                                 base-url
                                 :allow-insecure-http
                                 t)
                    (ollama-argument-error ()
                      (setf signalled t)))
                  (assert signalled)))
              (let ((signalled nil))
                (handler-case (client-with-request-function
                               (lambda (request &key timeout)
                                 (declare (ignore request timeout))
                                 (response-with-text "{}"))
                               :base-url
                               "http://example.test/api")
                  (ollama-argument-error ()
                    (setf signalled t)))
                (assert signalled))
              (let ((signalled nil)
                    (client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{}"))
                      :api-key
                      "secret")))
                (handler-case (request-json client
                                            :get
                                            "/version"
                                            :headers
                                            '(("Authorization" . "Basic bad")))
                  (ollama-argument-error ()
                    (setf signalled t)))
                (assert signalled))
              (dolist (path (list "/../secret" "\\secret"))
                (let ((signalled nil))
                  (handler-case (request-json
                                 (client-with-request-function
                                  (lambda (request &key timeout)
                                    (declare (ignore request timeout))
                                    (response-with-text "{}")))
                                 :get
                                 path)
                    (ollama-argument-error ()
                      (setf signalled t)))
                  (assert signalled))))
          (it "enforces request and response size limits"
              (let* ((called nil)
                     (client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore timeout))
                         (setf called request)
                         (response-with-text "{}"))
                       :max-request-length
                       4)))
                (handler-case (request-json client
                                            :post
                                            "/chat"
                                            :body
                                            (json-object "x" "123"))
                  (ollama-argument-error ()
                    nil))
                (handler-case (perform-request client
                                               :post
                                               "/chat"
                                               :body
                                               '(:unsupported-body-type))
                  (ollama-argument-error ()
                    nil))
                (assert (null called)))
              (let ((condition nil))
                (handler-case (request-json
                               (client-with-request-function
                                (lambda (request &key timeout)
                                  (declare (ignore request timeout))
                                  (response-with-text "{\"ok\":true}"))
                                :max-input-length
                                4)
                               :get
                               "/version")
                  (ollama-protocol-error (caught)
                    (setf condition caught)))
                (assert condition)))
          (it "reports malformed JSON and invalid UTF-8 as protocol errors"
              (let ((invalid-utf8
                     (make-array 1
                                 :element-type
                                 '(unsigned-byte 8)
                                 :initial-element
                                 255)))
                (dolist
                    (response
                     (list (response-with-text "{broken")
                           (make-http-response :status 200 :body invalid-utf8)))
                  (let ((condition nil))
                    (handler-case (request-json (queued-client response)
                                                :get
                                                "/version")
                      (ollama-protocol-error (caught)
                        (setf condition caught)))
                    (assert condition))))))
