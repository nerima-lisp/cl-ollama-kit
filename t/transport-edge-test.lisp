(in-package #:ollama-kit/test)

(describe "Transport and blob edge contracts"
          (it "preserves Ollama errors and wraps HTTP client failures"
              (let* ((expected
                      (make-condition 'ollama-protocol-error
                                      :message
                                      "HTTP callback failure"
                                      :detail
                                      nil))
                     (client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore request timeout))
                         (error expected))))
                     (caught nil))
                (handler-case (perform-request client :get "/version")
                  (ollama-protocol-error (condition)
                    (setf caught condition)))
                (assert (eq expected caught)))
              (let* ((client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore request timeout))
                         (error "HTTP callback failure"))))
                     (caught nil))
                (handler-case (perform-request client :get "/version")
                  (ollama-transport-error (condition)
                    (setf caught condition)))
                (assert caught)
                (assert
                 (typep (ollama-transport-error-cause caught) 'simple-error))))
          (it
           "passes client defaults and explicit timeout values to the HTTP client"
           (let* ((seen-timeouts '())
                  (client
                   (client-with-request-function
                    (lambda (request &key timeout)
                      (declare (ignore request))
                      (push timeout seen-timeouts)
                      (response-with-text "{}"))
                    :timeout
                    23)))
             (version client)
             (version client :timeout nil)
             (assert (equal '(nil 23) seen-timeouts))))
          (it "rejects invalid clients, request options, and oversized bodies"
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (perform-request nil :get "/version"))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (request-json nil :get "/version"))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (request-raw nil :get "/version"))))
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{}"))
                      :max-request-length
                      3)))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (request-raw client
                                            :post
                                            "/version"
                                            :body
                                            "too long"))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (perform-request client
                                                :get
                                                "/version"
                                                :unsupported
                                                t))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%validate-keyword-options
                                '(:url "/version" . :body)
                                '(:url)))))))
          (it "supports bodyless raw responses and rejects malformed JSON"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "" :status 204)))))
                (let ((response (request-raw client :get "/version")))
                  (assert (http-message-kit:http-response-p response))
                  (assert
                   (= 204 (http-message-kit:http-response-status response)))))
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{")))))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (request-json client :get "/version"))))))
          (it "returns parsed JSON with its complete HTTP response"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{\"version\":\"0.1.0\"}")))))
                (multiple-value-bind (value response)
                    (request-json client :get "/version")
                  (assert (hash-table-p value))
                  (assert (http-message-kit:http-response-p response))
                  (assert
                   (= 200 (http-message-kit:http-response-status response)))
                  (assert
                   (equalp
                    (cl-codec-kit:string-to-octets "{\"version\":\"0.1.0\"}"
                                                   :encoding
                                                   :utf-8)
                    (http-message-kit:http-response-body response))))))
          (it-each
           (("nil" nil) ("empty" "")
            ("slash" "sha256/a")
            ("backslash" "sha256\\a")
            ("query" "sha256?query")
            ("fragment" "sha256#fragment")
            ("newline" (format nil "sha256~Cnewline" #\Newline)))
           "rejects unsafe blob path ~A"
           (name digest)
           (assert
            (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%blob-path digest)))))
          (it "rejects non-octet blob bodies before transport"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "ok")))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (push-blob client "sha256:ok" '(1 2 3)))))))
          (it
           "covers raw request validation, byte encoding, headers, and response limits"
           (let* ((observed-request nil)
                  (transport-called-p nil)
                  (client
                   (client-with-request-function
                    (lambda (request &key timeout)
                      (declare (ignore timeout))
                      (setf observed-request request
                            transport-called-p t)
                      (response-with-text "{}")))))
             (let ((condition nil))
               (handler-case (request-raw client
                                          :post
                                          "/invalid"
                                          :body
                                          (list 1 2 3))
                 (ollama-argument-error (caught)
                   (setf condition caught)))
               (assert condition)
               (assert
                (string= "HTTP request body must be a string or octet vector."
                         (ollama-error-message condition)))
               (assert
                (eq (ollama-argument-error-detail condition)
                    (find-symbol "CONS" :cl)))
               (assert (not transport-called-p)))
             (request-raw client :get "/no-accept" :accept nil)
             (assert
              (null
               (http-message-kit:http-header-value
                (http-message-kit:http-request-headers observed-request)
                "Accept")))
             (request-raw client :post "/utf8" :body "A λ")
             (assert
              (equalp #(65 32 206 187)
                      (http-message-kit:http-request-body observed-request)))
             (let* ((override-transport-called-p nil)
                    (override-client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (setf override-transport-called-p t)
                        (response-with-text "{}"))
                      :api-key
                      "fixture-api-key"))
                    (condition nil))
               (handler-case (request-raw override-client
                                          :get
                                          "/override"
                                          :headers
                                          (list
                                           (cons "Authorization"
                                                 "Basic fixture")))
                 (ollama-argument-error (caught)
                   (setf condition caught)))
               (assert condition)
               (assert
                (string= "Do not override a configured API-KEY per request."
                         (ollama-error-message condition)))
               (assert (null (ollama-argument-error-detail condition)))
               (assert (not override-transport-called-p)))
             (let* ((oversized-body
                     (cl-codec-kit:string-to-octets "12345" :encoding :utf-8))
                    (overflow-client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response oversized-body))
                      :max-input-length
                      4))
                    (condition nil))
               (handler-case (request-raw overflow-client :get "/too-large")
                 (ollama-protocol-error (caught)
                   (setf condition caught)))
               (assert condition)
               (assert
                (string= "HTTP response body exceeds the configured limit."
                         (ollama-error-message condition)))
               (assert (= 4 (ollama-protocol-error-detail condition))))))
          (it "maps blob and raw non-success responses to Ollama API errors"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{\"error\":\"blob failure\"}"
                                            :status
                                            500)))))
                (let ((caught nil))
                  (handler-case (blob-exists-p client "sha256:broken")
                    (ollama-api-error (condition)
                      (setf caught condition)))
                  (assert caught)
                  (assert (= 500 (ollama-http-error-status caught)))
                  (assert
                   (equal "blob failure"
                          (gethash "error" (ollama-api-error-data caught))))
                  (assert
                   (equal "{\"error\":\"blob failure\"}"
                          (ollama-http-error-body caught))))
                (assert
                 (%signals-p 'ollama-api-error
                             (lambda ()
                               (request-raw client :get "/version"))))))
          (it "maps bodyless HEAD 500 responses to Ollama HTTP errors"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore timeout))
                        (assert
                         (string-equal "HEAD"
                                       (http-message-kit:http-request-method
                                        request)))
                        (response nil :status 500)))))
                (let ((caught nil))
                  (handler-case (blob-exists-p client "sha256:bodyless")
                    (ollama-http-error (condition)
                      (setf caught condition)))
                  (assert caught)
                  (assert (= 500 (ollama-http-error-status caught)))
                  (assert (equal "" (ollama-http-error-body caught)))
                  (assert (not (typep caught 'ollama-api-error)))))))

(it-each
 (("string" :string "A λ" #(65 32 206 187))
  ("octet vector" :octets (0 255 128) #(0 255 128)))
 "sends ~A blob request bytes"
 (name body-kind representation expected-bytes)
 (let* ((body
         (case body-kind
           (:string representation)
           (:octets
            (make-array (length representation)
                        :element-type
                        '(unsigned-byte 8)
                        :initial-contents
                        representation))))
        (sent-request nil)
        (client
         (client-with-request-function
          (lambda (request &key timeout)
            (declare (ignore timeout))
            (setf sent-request request)
            (response-with-text "stored" :status 201)))))
   (let ((response (push-blob client "sha256:upload" body)))
     (assert (http-message-kit:http-response-p response))
     (assert (= 201 (http-message-kit:http-response-status response)))
     (assert (http-message-kit:http-request-p sent-request))
     (assert
      (string-equal "POST" (http-message-kit:http-request-method sent-request)))
     (assert
      (string= "/api/blobs/sha256:upload"
               (http-message-kit:http-request-target sent-request)))
     (assert
      (equalp expected-bytes (http-message-kit:http-request-body sent-request)))
     (let ((headers (http-message-kit:http-request-headers sent-request)))
       (assert
        (string= "application/octet-stream"
                 (http-message-kit:http-header-value headers "Content-Type")))
       (assert (null (http-message-kit:http-header-value headers "Accept")))))))

(it "covers timeout outcomes and absent monitor callbacks"
    (let* ((cancel-token (http-kit/client:make-http-cancellation-token))
           (cancel-lock
            (cl-concurrent-kit:make-lock :name
                                         "cl-ollama-kit test timeout cancellation"))
           (cancel-condition
            (cl-concurrent-kit:make-condition-variable :name
                                                       "cl-ollama-kit test timeout cancellation"))
           (expiry-observed-p nil)
           (condition nil))
      (http-kit/client::%client-cancellation-token-register-handler cancel-token
                                                                    (lambda ()
                                                                      (cl-concurrent-kit:with-lock-held
                                                                       (cancel-lock)
                                                                       (setf expiry-observed-p t)
                                                                       (cl-concurrent-kit:condition-notify
                                                                        cancel-condition))))
      (handler-case (ollama-kit::%call-with-http-timeout-monitor cancel-token
                                                                 0
                                                                 nil
                                                                 nil
                                                                 nil
                                                                 (lambda
                                                                     (response-header-callback
                                                                      body-chunk-callback)
                                                                   (declare (ignore
                                                                             response-header-callback
                                                                             body-chunk-callback))
                                                                   (cl-concurrent-kit:with-lock-held
                                                                    (cancel-lock)
                                                                    (loop until expiry-observed-p
                                                                          do (cl-concurrent-kit:condition-wait
                                                                              cancel-condition
                                                                              cancel-lock)))
                                                                   :response))
        (ollama-response-timeout (caught)
          (setf condition caught)))
      (assert condition)
      (assert expiry-observed-p)
      (assert
       (string=
        "HTTP response headers were not received before the response timeout."
        (ollama-error-message condition))))
    (let ((send-called-p nil))
      (let ((response
             (ollama-kit::%call-with-http-timeout-monitor nil
                                                          nil
                                                          nil
                                                          nil
                                                          nil
                                                          (lambda
                                                              (response-header-callback
                                                               body-chunk-callback)
                                                            (assert
                                                             (null
                                                              response-header-callback))
                                                            (assert
                                                             (null
                                                              body-chunk-callback))
                                                            (setf send-called-p t)
                                                            :response))))
        (assert send-called-p)
        (assert (eq :response response)))))

(it "re-signals a transport cancellation not caused by response overflow"
    (let* ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (error (quote http-kit/client:http-client-request-cancelled)))))
           (caught nil))
      (handler-case (perform-request client :get "/cancelled")
        (ollama-cancelled (condition)
          (setf caught condition)))
      (assert caught)
      (assert
       (typep (ollama-transport-error-cause caught)
              (quote http-kit/client:http-client-request-cancelled)))))

(it "returns the diagnostic prefix after overflow cancellation"
    (let* ((body (cl-codec-kit:string-to-octets "abcdef" :encoding :utf-8))
           (client
            (make-client :http-client
                         (http-kit/client:make-http-client :transport-function
                                                           (lambda
                                                               (request &key
                                                                        on-response-headers
                                                                        on-body-chunk
                                                                        &allow-other-keys)
                                                             (declare (ignore
                                                                       request))
                                                             (funcall
                                                              on-response-headers
                                                              502
                                                              nil)
                                                             (funcall
                                                              on-body-chunk
                                                              body)
                                                             (error
                                                              (quote
                                                               http-kit/client:http-client-request-cancelled))))
                         :max-input-length
                         4))
           (response (perform-request client :get "/large-error")))
      (assert (= 502 (http-message-kit:http-response-status response)))
      (assert
       (equalp #(97 98 99 100) (http-message-kit:http-response-body response)))))

(it
 "stops reading an oversized non-success response and keeps its diagnostic prefix"
 (let* ((body
         (make-array (* 1024 1024)
                     :element-type
                     (quote (unsigned-byte 8))
                     :initial-element
                     65))
        (server
         (make-loopback-http-server :status 502 :body body :keep-alive-p nil))
        (client
         (make-client :base-url
                      (loopback-http-server-url server)
                      :max-input-length
                      64))
        (server-thread (%loopback-http-server-thread server))
        (condition nil))
   (unwind-protect
       (progn
         (handler-case (request-json client :get "/large-error")
           (ollama-http-error (caught)
             (setf condition caught)))
         (assert condition)
         (assert (= 502 (ollama-http-error-status condition)))
         (assert (= 64 (length (ollama-http-error-body condition))))
         (assert
          (= 502
             (http-message-kit:http-response-status
              (ollama-http-error-response condition))))
         (assert
          (= 64
             (length
              (http-message-kit:http-response-body
               (ollama-http-error-response condition)))))
         (close-client client)
         (sb-thread:join-thread server-thread)
         (let ((server-error (loopback-http-server-server-error server))
               (server-eof-p (loopback-http-server-eof-p server)))
           (assert (and server-error (not server-eof-p))
                   (server-error server-eof-p))))
     (close-client client)
     (close-loopback-http-server server))))
