(in-package #:ollama-kit/test)

(describe "Transport and blob edge contracts"
  (it "preserves Ollama errors and wraps HTTP client failures"
    (let* ((expected
             (make-condition 'ollama-protocol-error
                             :message "HTTP callback failure"
                             :detail nil))
           (client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (error expected))))
           (caught nil))
      (handler-case
          (perform-request client :get "/version")
        (ollama-protocol-error (condition)
          (setf caught condition)))
      (assert (eq expected caught)))
    (let* ((client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (error "HTTP callback failure"))))
           (caught nil))
      (handler-case
          (perform-request client :get "/version")
        (ollama-transport-error (condition)
          (setf caught condition)))
      (assert caught)
      (assert (typep (ollama-transport-error-cause caught) 'simple-error))))
  (it "passes client defaults and explicit timeout values to the HTTP client"
    (let ((seen-timeouts '())
          (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request))
               (push timeout seen-timeouts)
               (response-with-text "{}"))
             :timeout 23)))
      (version client)
      (version client :timeout nil)
      (assert (equal '(nil 23) seen-timeouts))))
  (it "rejects invalid clients, request options, and oversized bodies"
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (perform-request nil :get "/version"))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (request-json nil :get "/version"))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (request-raw nil :get "/version"))))
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (response-with-text "{}"))
             :max-request-length 3)))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (request-raw client
                                         :post
                                         "/version"
                                         :body
                                         "too long"))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (perform-request client
                                             :get
                                             "/version"
                                             :unsupported
                                             t))))
      (assert (%signals-p 'ollama-argument-error
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
        (assert (= 204 (http-message-kit:http-response-status response)))))
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (response-with-text "{")))))
      (assert (%signals-p 'ollama-protocol-error
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
        (assert (= 200 (http-message-kit:http-response-status response)))
        (assert (equalp
                 (cl-codec-kit:string-to-octets
                  "{\"version\":\"0.1.0\"}" :encoding :utf-8)
                 (http-message-kit:http-response-body response))))))
  (it-each
   (("nil" nil)
    ("empty" "")
    ("slash" "sha256/a")
    ("backslash" "sha256\\a")
    ("query" "sha256?query")
    ("fragment" "sha256#fragment")
    ("newline" (format nil "sha256~Cnewline" #\Newline)))
   "rejects unsafe blob path ~A"
   (name digest)
   (assert (%signals-p 'ollama-argument-error
                       (lambda ()
                         (ollama-kit::%blob-path digest)))))
  (it "rejects non-octet blob bodies before transport"
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (response-with-text "ok")))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (push-blob client "sha256:ok" '(1 2 3)))))))
  (it "maps blob and raw non-success responses to Ollama API errors"
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (response-with-text "{\"error\":\"blob failure\"}"
                                   :status 500)))))
      (let ((caught nil))
        (handler-case
            (blob-exists-p client "sha256:broken")
          (ollama-api-error (condition)
            (setf caught condition)))
        (assert caught)
        (assert (= 500 (ollama-http-error-status caught)))
        (assert (equal "blob failure"
                       (gethash "error" (ollama-api-error-data caught))))
        (assert (equal "{\"error\":\"blob failure\"}"
                       (ollama-http-error-body caught))))
      (assert (%signals-p 'ollama-api-error
                          (lambda ()
                            (request-raw client :get "/version")))))))
