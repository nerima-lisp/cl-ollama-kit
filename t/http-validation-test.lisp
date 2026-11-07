(in-package #:ollama-kit/test)

(defun %parsed-http-url-valid-p (url)
  (handler-case (ollama-kit::%validate-http-url-components url "HTTP URLs")
    (ollama-kit:ollama-argument-error ()
      nil)))

(defun %parsed-http-authority-valid-p (authority)
  (%parsed-http-url-valid-p (format nil "http://~A/api" authority)))

(defun %parsed-http-port-valid-p (port)
  (%parsed-http-authority-valid-p (format nil "example.test:~A" port)))

(defun %parsed-http-request-url (url)
  (ollama-kit::%validate-http-url-components url "HTTP request URLs")
  url)

(describe "HTTP validation contracts"
          (it-each
           (("request query" :request "http://example.test/api?limit=1" :accept)
            ("request mixed-case HTTP scheme" :request
                                              "HtTp://example.test/api"
                                              :accept)
            ("request mixed-case HTTPS scheme" :request
                                               "hTtPs://example.test/api"
                                               :accept)
            ("base mixed-case HTTPS scheme" :base
                                            "hTtPs://example.test/api"
                                            :accept)
            ("request tab" :request #\Tab :reject)
            ("request newline" :request #\Newline :reject)
            ("base tab" :base #\Tab :reject)
            ("base newline" :base #\Newline :reject)
            ("base dot-dot path segment" :base
                                         "https://example.test/api/../v1"
                                         :reject)
            ("base encoded dot segment" :base
                                        "https://example.test/api/%2E/v1"
                                        :reject))
           "handles ~A URL validation"
           (name endpoint input outcome)
           (let* ((url
                   (if (characterp input)
                       (format nil
                               "~A://example.test/api~Cpath"
                               (if (eq endpoint :base)
                                   "https"
                                   "http")
                               input)
                       input))
                  (validator
                   (if (eq endpoint :base)
                       (lambda ()
                         (ollama-kit::%validate-base-url url nil))
                       (lambda ()
                         (%parsed-http-request-url url)))))
             (if (eq outcome :accept)
                 (assert (equal url (funcall validator)))
                 (assert (%signals-p (quote ollama-argument-error) validator)))))
          (it "normalizes methods and headers while rejecting unsafe values"
              (assert (eq :post (ollama-kit::%normalize-method :post)))
              (assert (eq :post (ollama-kit::%normalize-method 'post)))
              (assert (eq :patch (ollama-kit::%normalize-method "patch")))
              (let* ((extension-name (symbol-name (gensym "X-OLLAMA-")))
                     (normalized-name (string-upcase extension-name)))
                (assert
                 (equal normalized-name
                        (ollama-kit::%normalize-method extension-name)))
                (assert (null (find-symbol normalized-name :keyword))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-method "bad method"))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-method ""))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-method 7))))
              (assert
               (equal "x-test" (ollama-kit::%normalize-header-name :x-test)))
              (assert
               (equal "X-Test" (ollama-kit::%normalize-header-name "X-Test")))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-header-name 7))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-header-name ""))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-header-name "bad name"))))
              (assert
               (equal '(("x-test" . "one") ("Y-Test" . "two"))
                      (ollama-kit::%normalize-headers
                       '((:x-test . "one") ("Y-Test" . "two")))))
              (assert (null (ollama-kit::%normalize-headers nil)))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-headers 7))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-headers '(7)))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-headers '(("x"))))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (ollama-kit::%normalize-headers
                              `(("x" . ,(format nil "bad~Cvalue" #\Newline)))))))
              (let ((headers '(("x-test" . "one"))))
                (assert
                 (eq headers
                     (ollama-kit::%ensure-header headers "x-test" "two")))
                (let ((with-new
                       (ollama-kit::%ensure-header headers "y-test" "two")))
                  (assert
                   (equal "two" (cdr (assoc "y-test" with-new :test #'string=)))))
                (let ((forced
                       (ollama-kit::%force-header headers "x-test" "three")))
                  (assert (equal '(("x-test" . "three")) forced)))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%ensure-header nil "x-test" 7))))))
          (it "validates base URLs, paths, and configured client limits"
              (let ((http-client
                     (http-kit/client:make-http-client :default-timeout nil)))
                (assert
                 (equal "http://localhost:11434/api"
                        (ollama-kit::%trim-base-url
                         "http://localhost:11434/api///")))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%trim-base-url "///"))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%trim-base-url ""))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%trim-base-url nil))))
                (assert (ollama-kit::%base-url-loopback-p "http://localhost"))
                (assert
                 (ollama-kit::%base-url-loopback-p "http://127.0.0.1:8080"))
                (assert (ollama-kit::%base-url-loopback-p "http://[::1]:8080"))
                (assert
                 (not
                  (ollama-kit::%base-url-loopback-p "http://user@localhost")))
                (assert
                 (not (ollama-kit::%base-url-loopback-p "https://example.test")))
                (assert (%parsed-http-port-valid-p "0"))
                (assert (%parsed-http-port-valid-p "65535"))
                (assert (not (%parsed-http-port-valid-p "")))
                (assert (not (%parsed-http-port-valid-p "65536")))
                (assert (not (%parsed-http-port-valid-p "12é")))
                (assert
                 (not
                  (%parsed-http-port-valid-p
                   (make-string 100000 :initial-element #\9))))
                (assert (%parsed-http-authority-valid-p "example.test:443"))
                (assert (%parsed-http-authority-valid-p "[2001:db8::1]:443"))
                (assert (%parsed-http-authority-valid-p "[::1]"))
                (assert (%parsed-http-authority-valid-p "[::1]:443"))
                (assert (not (%parsed-http-authority-valid-p "")))
                (assert
                 (not (%parsed-http-authority-valid-p "user@example.test")))
                (assert
                 (not (%parsed-http-authority-valid-p "example.test:bad")))
                (assert (not (%parsed-http-authority-valid-p "[::1]x")))
                (assert (not (%parsed-http-authority-valid-p "[::1]:bad")))
                (dolist (authority '("[::[1]" "example[.test" "example].test"))
                  (assert (not (%parsed-http-authority-valid-p authority))))
                (assert
                 (equal "http://localhost:11434/api/x"
                        (%parsed-http-request-url
                         "http://localhost:11434/api/x")))
                (assert
                 (equal "http://localhost:11434"
                        (%parsed-http-request-url "http://localhost:11434")))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (%parsed-http-request-url "x"))))
                (dolist
                    (url
                     '("ftp://localhost/x" "http:///x"
                                           "http://example.test:bad/x"
                                           "http://example.test/a/../b"
                                           "http://example.test/a%2eb"
                                           "http://example.test/#fragment"
                                           "http://example.test/a b"))
                  (assert
                   (%signals-p 'ollama-argument-error
                               (lambda ()
                                 (%parsed-http-request-url url)))))
                (assert
                 (equal "https://example.test/api"
                        (ollama-kit::%validate-base-url
                         "https://example.test/api"
                         nil)))
                (assert
                 (equal "http://example.test/api"
                        (ollama-kit::%validate-base-url
                         "http://example.test/api"
                         t)))
                (assert
                 (equal "https://example.test"
                        (ollama-kit::%validate-base-url "https://example.test"
                                                        nil)))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%validate-base-url "x" nil))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%validate-base-url
                                (format nil
                                        "https://example.test/~C"
                                        (code-char 127))
                                nil))))
                (dolist
                    (base-url
                     '("http://example.test/api?query=1"
                       "http://example.test/api#fragment"
                       "http://example.test/api/./x"
                       "ftp://example.test/api"
                       "http://example.test:bad/api"
                       "http://example.test/api"))
                  (assert
                   (%signals-p 'ollama-argument-error
                               (lambda ()
                                 (ollama-kit::%validate-base-url base-url nil)))))
                (assert
                 (equal "/v1/models?limit=1"
                        (ollama-kit::%validate-request-path
                         "/v1/models?limit=1")))
                (dolist
                    (path
                     '(nil ""
                           "v1 models"
                           "http://example.test"
                           "/a/../b"
                           "/a\\b"
                           "/a#fragment"))
                  (assert
                   (%signals-p 'ollama-argument-error
                               (lambda ()
                                 (ollama-kit::%validate-request-path path)))))
                (let ((default-client (make-client)))
                  (unwind-protect
                      (progn
                        (assert (ollama-kit:client-p default-client))
                        (assert
                         (null (ollama-kit:client-timeout default-client)))
                        (assert
                         (= 300
                            (ollama-kit:client-response-timeout default-client)))
                        (assert
                         (= 120 (ollama-kit:client-idle-timeout default-client)))
                        (assert
                         (= 16777216
                            (ollama-kit:client-max-input-length default-client)))
                        (assert
                         (= 16777216
                            (ollama-kit:client-max-request-length
                             default-client)))
                        (assert
                         (null
                          (ollama-kit:client-allow-insecure-http default-client)))
                        (assert
                         (not (ollama-kit:client-api-key-p default-client))))
                    (close-client default-client)))
                (let ((default-client (make-client :http-client http-client)))
                  (assert
                   (equal ollama-kit::+default-base-url+
                          (ollama-kit::client-base-url default-client))))
                (let ((zero-timeout-client
                       (make-client :http-client http-client :timeout 0)))
                  (assert
                   (zerop (ollama-kit::client-timeout zero-timeout-client))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :timeout
                                            -1))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :timeout
                                            "1"))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :allow-insecure-http
                                            1))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client http-client :api-key 7))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :api-key
                                            ""))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :api-key
                                            (format nil "bad~Ckey" #\Newline)))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :max-input-length
                                            0))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :max-request-length
                                            0))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :http-client
                                            http-client
                                            :api-key
                                            "secret"
                                            :headers
                                            '(("authorization" . "Basic x"))))))
                (let ((client
                       (make-client :http-client
                                    http-client
                                    :base-url
                                    "http://example.test/api"
                                    :api-key
                                    "secret"
                                    :allow-insecure-http
                                    t)))
                  (assert
                   (equal "http://example.test/api"
                          (ollama-kit::client-base-url client)))
                  (assert
                   (equal "Bearer secret"
                          (cdr
                           (assoc "Authorization"
                                  (ollama-kit::client-headers client)
                                  :test
                                  #'string=))))))))

(it "validates web-fetch URLs before transport and forwards query URLs"
    (let* ((transport-count 0)
           (seen-request nil)
           (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (incf transport-count)
               (setf seen-request request)
               (response-with-text "{}")))))
      (unwind-protect
          (progn
            (dolist
                (url
                 (list "http://[::[1]/page" "https://user@example.test/page"))
              (assert
               (%signals-p (quote ollama-argument-error)
                           (lambda ()
                             (web-fetch client url))))
              (assert (zerop transport-count)))
            (web-fetch client "https://example.test/doc?x=1")
            (assert (= 1 transport-count))
            (assert
             (equal "https://example.test/doc?x=1"
                    (gethash "url" (request-json-object seen-request)))))
        (close-client client))))

(it "percent-encodes Unicode model names into one OpenAI path segment"
    (let* ((seen-request nil)
           (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf seen-request request)
               (response-with-text "{}"))
             :base-url
             ollama-kit::+openai-default-base-url+)))
      (unwind-protect
          (progn
            (openai-model client "éあ😀")
            (assert
             (equal "/v1/models/%C3%A9%E3%81%82%F0%9F%98%80"
                    (http-message-kit:http-request-target seen-request))))
        (close-client client))))

(it "forwards client transport and timeout options for OpenAI and Anthropic"
    (let* ((http-client (http-kit/client:make-http-client :default-timeout nil))
           (openai
            (make-openai-client :http-client
                                http-client
                                :response-timeout
                                17
                                :idle-timeout
                                9))
           (anthropic
            (make-anthropic-client :http-client
                                   http-client
                                   :response-timeout
                                   13
                                   :idle-timeout
                                   5
                                   :api-key
                                   "anthropic-test-key")))
      (unwind-protect
          (progn
            (assert (eq http-client (ollama-kit:client-http-client openai)))
            (assert (= 17 (ollama-kit:client-response-timeout openai)))
            (assert (= 9 (ollama-kit:client-idle-timeout openai)))
            (assert (eq http-client (ollama-kit:client-http-client anthropic)))
            (assert (= 13 (ollama-kit:client-response-timeout anthropic)))
            (assert (= 5 (ollama-kit:client-idle-timeout anthropic)))
            (assert
             (equal "anthropic-test-key"
                    (cdr
                     (assoc "x-api-key"
                            (ollama-kit:client-headers anthropic)
                            :test
                            (function string-equal))))))
        (close-client openai)
        (close-client anthropic))))

(it "accepts mixed-case localhost for an HTTP base URL"
    (assert (ollama-kit::%base-url-loopback-p "http://LOCALHOST"))
    (assert
     (equal "HtTp://LoCaLhOsT:11434/api"
            (ollama-kit::%validate-base-url "HtTp://LoCaLhOsT:11434/api" nil))))
