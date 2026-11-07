(in-package #:ollama-kit/test)

(describe "client and HTTP transport contracts"
          (it "sends UTF-8 JSON through a supplied HTTP client"
              (let* ((server
                      (make-loopback-http-server :body
                                                 (cl-codec-kit:string-to-octets
                                                  "{\"ok\":true}"
                                                  :encoding
                                                  :utf-8)))
                     (http-client
                      (http-kit/client:make-http-client :default-timeout nil))
                     (client
                      (make-client :http-client
                                   http-client
                                   :base-url
                                   (loopback-http-server-url server))))
                (unwind-protect
                    (multiple-value-bind (value response)
                        (request-json client
                                      :post
                                      "/api/chat"
                                      :body
                                      (json-object "model"
                                                   "tiny"
                                                   "prompt"
                                                   "日本😀"))
                      (let* ((request (loopback-http-server-request server))
                             (payload
                              (json-kit:parse
                               (cl-codec-kit:octets-to-string
                                (http-message-kit:http-request-body request)
                                :encoding
                                :utf-8))))
                        (assert (http-message-kit:http-request-p request))
                        (assert (http-message-kit:http-response-p response))
                        (assert
                         (= 200
                            (http-message-kit:http-response-status response)))
                        (assert (hash-table-p value))
                        (assert (eq t (gethash "ok" value)))
                        (assert
                         (string-equal "POST"
                                       (http-message-kit:http-request-method
                                        request)))
                        (assert
                         (equal "/api/chat"
                                (http-message-kit:http-request-target request)))
                        (assert (equal "日本😀" (gethash "prompt" payload))))
                      (http-kit/client:http-client-clear-connections
                       http-client)))))
          (it "adds authentication and JSON headers"
              (let* ((server
                      (make-loopback-http-server :body
                                                 (cl-codec-kit:string-to-octets
                                                  "{}"
                                                  :encoding
                                                  :utf-8)))
                     (client
                      (make-client :base-url
                                   (loopback-http-server-url server)
                                   :api-key
                                   "secret")))
                (unwind-protect
                    (request-json client
                                  :post
                                  "/api/generate"
                                  :body
                                  (json-object "x" 1))
                  (close-client client))
                (let* ((request (loopback-http-server-request server))
                       (headers (http-message-kit:http-request-headers request)))
                  (assert
                   (string= "Bearer secret"
                            (http-message-kit:http-header-value headers
                                                                "Authorization")))
                  (assert
                   (string= "application/json; charset=utf-8"
                            (http-message-kit:http-header-value headers
                                                                "Content-Type")))
                  (assert
                   (string= "application/json"
                            (http-message-kit:http-header-value headers
                                                                "Accept"))))))
          (it "preserves raw request bytes in the HTTP messages"
              (let* ((body
                      (make-array 3
                                  :element-type
                                  '(unsigned-byte 8)
                                  :initial-contents
                                  '(1 2 3)))
                     (server
                      (make-loopback-http-server :status
                                                 201
                                                 :body
                                                 (cl-codec-kit:string-to-octets
                                                  "created"
                                                  :encoding
                                                  :utf-8)))
                     (client
                      (make-client :base-url (loopback-http-server-url server))))
                (unwind-protect
                    (let* ((response
                            (request-raw client
                                         :post
                                         "/blobs/sha256:abc"
                                         :body
                                         body
                                         :content-type
                                         "application/octet-stream"
                                         :accept
                                         "application/octet-stream"))
                           (request (loopback-http-server-request server))
                           (headers
                            (http-message-kit:http-request-headers request)))
                      (assert (http-message-kit:http-request-p request))
                      (assert (http-message-kit:http-response-p response))
                      (assert
                       (= 201 (http-message-kit:http-response-status response)))
                      (assert
                       (equalp
                        (cl-codec-kit:string-to-octets "created"
                                                       :encoding
                                                       :utf-8)
                        (http-message-kit:http-response-body response)))
                      (assert
                       (equalp body
                               (http-message-kit:http-request-body request)))
                      (assert
                       (string= "application/octet-stream"
                                (http-message-kit:http-header-value headers
                                                                    "Content-Type")))
                      (assert
                       (string= "application/octet-stream"
                                (http-message-kit:http-header-value headers
                                                                    "Accept"))))
                  (close-client client))))
          (it-each (("present" 200 t) ("missing" 404 nil))
                   "reports blob ~A status"
                   (name status expected)
                   (let* ((server (make-loopback-http-server :status status))
                          (client
                           (make-client :base-url
                                        (loopback-http-server-url server))))
                     (unwind-protect
                         (progn
                           (assert
                            (eql expected
                                 (blob-exists-p client "sha256:present")))
                           (assert
                            (string-equal "HEAD"
                                          (http-message-kit:http-request-method
                                           (loopback-http-server-request server)))))
                       (close-client client))))
          (it-each
           (("structured API error" 404
                                    "{\"error\":\"model missing\"}"
                                    :api
                                    "model missing")
            ("redirect" 302 "redirect" :http nil)
            ("server error" 500 "server error" :http nil))
           "maps ~A response bodies for status ~A"
           (name status body expected-condition expected-message)
           (let* ((server
                   (make-loopback-http-server :status
                                              status
                                              :body
                                              (cl-codec-kit:string-to-octets
                                               body
                                               :encoding
                                               :utf-8)))
                  (client
                   (make-client :base-url (loopback-http-server-url server)))
                  (condition nil))
             (unwind-protect
                 (handler-case (request-json client :get "/version")
                   (ollama-http-error (caught)
                     (setf condition caught)))
               (close-client client))
             (assert
              (if (eq expected-condition :api)
                  (typep condition 'ollama-api-error)
                  (typep condition 'ollama-http-error)))
             (assert (= status (ollama-http-error-status condition)))
             (assert (equal body (ollama-http-error-body condition)))
             (when expected-message
               (assert
                (equal expected-message (ollama-error-message condition))))))
          (it-each
           (("invalid header name" "Bad Header" "value")
            ("header injection" "X-Test"
                                (format nil
                                        "ok~C~CInjected: yes"
                                        #\Return
                                        #\Linefeed)))
           "rejects ~A in client headers"
           (name header-name header-value)
           (let ((condition nil))
             (handler-case (make-client :headers
                                        (list (cons header-name header-value)))
               (ollama-argument-error (caught)
                 (setf condition caught)))
             (assert condition)))
          (it "normalizes endpoint slashes and preserves the base path"
              (let* ((server (make-loopback-http-server))
                     (base-url
                      (format nil
                              "~A/api/"
                              (string-right-trim "/"
                                                 (loopback-http-server-url
                                                  server))))
                     (client (make-client :base-url base-url)))
                (unwind-protect (request-json client :get "//version")
                  (close-client client))
                (assert
                 (equal "/api/version"
                        (http-message-kit:http-request-path
                         (loopback-http-server-request server)))))
              (it-each
               (("missing host" "http:///api")
                ("unclosed IPv6 bracket" "http://[::1/api")
                ("empty host" "http://:11434/api")
                ("invalid port" "http://localhost:bad/api")
                ("multiple ports" "http://localhost:1:2/api")
                ("empty IPv6 port" "http://[::1]:/api")
                ("out of range port" "http://[::1]:65536/api")
                ("dot-dot segment" "http://localhost:11434/api/../secret"))
               "rejects ~A base URLs"
               (name base-url)
               (let ((condition nil))
                 (handler-case (make-client :base-url
                                            base-url
                                            :allow-insecure-http
                                            t)
                   (ollama-argument-error (caught)
                     (setf condition caught)))
                 (assert (typep condition 'ollama-argument-error)))))
          (it "rejects unsafe endpoints and authorization overrides"
              (let ((client (make-client :api-key "secret"))
                    (condition nil))
                (unwind-protect
                    (handler-case (request-json client
                                                :get
                                                "/version"
                                                :headers
                                                '(("Authorization" .
                                                                   "Basic bad")))
                      (ollama-argument-error (caught)
                        (setf condition caught)))
                  (close-client client))
                (assert (typep condition 'ollama-argument-error)))
              (dolist (path '("/../secret" "\\secret"))
                (let ((condition nil))
                  (handler-case (request-json (make-client) :get path)
                    (ollama-argument-error (caught)
                      (setf condition caught)))
                  (assert (typep condition 'ollama-argument-error)))))
          (it "enforces request and response size limits"
              (let* ((server
                      (make-loopback-http-server :body
                                                 (cl-codec-kit:string-to-octets
                                                  "{\"ok\":true}"
                                                  :encoding
                                                  :utf-8)))
                     (client
                      (make-client :base-url
                                   (loopback-http-server-url server)
                                   :max-request-length
                                   4
                                   :max-input-length
                                   4))
                     (request-condition nil)
                     (response-condition nil))
                (unwind-protect
                    (progn
                      (handler-case (request-json client
                                                  :post
                                                  "/chat"
                                                  :body
                                                  (json-object "x" "123"))
                        (ollama-argument-error (caught)
                          (setf request-condition caught)))
                      (assert (typep request-condition 'ollama-argument-error))
                      (assert (null (loopback-http-server-request server)))
                      (handler-case (request-json client :get "/version")
                        (ollama-protocol-error (caught)
                          (setf response-condition caught)))
                      (assert (typep response-condition 'ollama-protocol-error))
                      (assert
                       (http-message-kit:http-request-p
                        (loopback-http-server-request server))))
                  (close-client client)))))
