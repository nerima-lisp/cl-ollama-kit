(in-package #:ollama-kit/test)

(describe "Transport and blob edge contracts"
  (it "preserves Ollama errors and wraps generic boundary failures"
    (let ((pass-through
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (error 'ollama-protocol-error
                      :message "boundary protocol failure")))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (perform-request pass-through :get "/version")))))
    (let ((wrapped
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (error "boundary failure")))))
      (assert (%signals-p 'ollama-transport-error
                          (lambda ()
                            (perform-request wrapped :get "/version"))))))

  (it "passes explicit timeouts to the boundary"
    (let (seen-timeout)
      (let ((client
              (client-with-request-function
               (lambda (request &key timeout)
                 (declare (ignore request))
                 (setf seen-timeout timeout)
                 (response-with-text "{}")))))
        (let ((response (perform-request client :get "/version"
                                          :timeout 17)))
          (close-http-response response)))
      (assert (= 17 seen-timeout))))

  (it "uses the client timeout by default and permits explicit NIL"
    (let* ((seen-timeouts '())
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

  (it "rejects invalid transport clients and oversized raw bodies"
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
                          (request-raw client :post "/version"
                                         :body "too long"))))))

  (it "rejects malformed keyword option lists"
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-request :url))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-request :unsupported t))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-request "unsupported" t)))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%validate-keyword-options
                           '(:url "/version" . :body)
                           '(:url)))))

  (it "supports bodyless raw requests and closes malformed JSON responses"
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (make-http-response :status 204 :body nil)))))
      (let ((response (request-raw client :get "/version")))
        (assert (= 204 (http-response-status response)))
        (close-http-response response)))
    (let* ((closed 0)
          (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (make-http-response
                :status 200
                :body "{"
                :close-function (lambda () (incf closed)))))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (request-json client :get "/version"))))
      (assert (= 1 closed))))

  (it "scopes raw and parsed response ownership"
    (let* ((closed 0)
           (response
             (make-http-response
              :status 200
              :body "{}"
              :close-function (lambda () (incf closed)))))
      (with-http-response (response)
        (assert (response-success-p response)))
      (assert (= 1 closed))
      (assert (null (http-response-close-function response))))
    (let* ((closed 0)
           (client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (make-http-response
                 :status 200
                 :body "{}"
                 :close-function (lambda () (incf closed)))))))
      (with-json-response (value response
                           (request-json client :get "/version"))
        (assert (hash-table-p value))
        (assert (response-success-p response)))
      (assert (= 1 closed)))
    (let* ((closed 0)
           (response
             (make-http-response
              :status 200
              :body "{}"
              :close-function (lambda () (incf closed)))))
      (assert (%signals-p 'simple-error
                          (lambda ()
                            (with-http-response (response)
                              (error "primary body failure")))))
      (assert (= 1 closed))))

  (it "closes successful high-level JSON endpoint responses"
    (let* ((closed 0)
          (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (make-http-response
                :status 200
                :body "{\"version\":\"0.1.0\"}"
                :close-function (lambda () (incf closed)))))))
      (let ((value (version client)))
        (assert (hash-table-p value)))
      (assert (= 1 closed))))

  (it "rejects unsafe blob paths and closes non-success responses"
    (dolist (digest (list nil "" "sha256/a" "sha256\\a"
                           "sha256?query" "sha256#fragment"
                           (format nil "sha256~Cnewline" #\Newline)))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%blob-path digest)))))
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (make-http-response :status 200 :body "ok")))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (push-blob client "sha256:ok" '(1 2 3))))))
    (let* ((closed 0)
          (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (make-http-response
                :status 500
                :body "{\"error\":\"blob failure\"}"
                :close-function (lambda ()
                                 (incf closed)
                                  (error "blob cleanup failure")))))))
      (assert (handler-case
                  (handler-bind ((warning #'muffle-warning))
                    (blob-exists-p client "sha256:broken"))
                (ollama-api-error () t)))
      (assert (= 1 closed))))
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               :not-an-http-response))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (blob-exists-p client "sha256:missing"))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (request-json client :get "/version")))))

  (it "closes non-success raw responses before signaling"
    (let* ((closed 0)
           (client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (make-http-response
                 :status 500
                 :body "{\"error\":\"raw failure\"}"
                 :close-function (lambda () (incf closed)))))))
      (assert (%signals-p 'ollama-api-error
                          (lambda ()
                            (request-raw client :get "/version"))))
      (assert (= 1 closed)))))
