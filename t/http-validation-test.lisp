(in-package #:ollama-kit/test)

(describe "HTTP validation contracts"
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
              (let ((boundary
                     (cl-boundary-kit:make-network-boundary :request-fn
                                                            (lambda
                                                                (request &key
                                                                         timeout)
                                                              (declare (ignore
                                                                        request
                                                                        timeout))
                                                              (response-with-text
                                                               "{}")))))
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
                (assert (ollama-kit::%decimal-port-p "0"))
                (assert (ollama-kit::%decimal-port-p "65535"))
                (assert (not (ollama-kit::%decimal-port-p "")))
                (assert (not (ollama-kit::%decimal-port-p "65536")))
                (assert (not (ollama-kit::%decimal-port-p "12é")))
                (assert
                 (not
                  (ollama-kit::%decimal-port-p
                   (make-string 100000 :initial-element #\9))))
                (assert
                 (ollama-kit::%valid-host-authority-p "example.test:443"))
                (assert
                 (ollama-kit::%valid-host-authority-p "[2001:db8::1]:443"))
                (assert (ollama-kit::%valid-host-authority-p "[::1]"))
                (assert (ollama-kit::%valid-host-authority-p "[::1]:443"))
                (assert (not (ollama-kit::%valid-host-authority-p "")))
                (assert
                 (not (ollama-kit::%valid-host-authority-p "user@example.test")))
                (assert
                 (not (ollama-kit::%valid-host-authority-p "example.test:bad")))
                (assert (not (ollama-kit::%valid-host-authority-p "[::1]x")))
                (assert (not (ollama-kit::%valid-host-authority-p "[::1]:bad")))
                (dolist (authority '("[::[1]" "example[.test" "example].test"))
                  (assert (not (ollama-kit::%valid-host-authority-p authority))))
                (assert
                 (equal "http://localhost:11434/api/x"
                        (ollama-kit::%validate-http-request-url
                         "http://localhost:11434/api/x")))
                (assert
                 (equal "http://localhost:11434"
                        (ollama-kit::%validate-http-request-url
                         "http://localhost:11434")))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%validate-http-request-url "x"))))
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
                                 (ollama-kit::%validate-http-request-url url)))))
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
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client))))
                (let ((default-client (make-client :network-boundary boundary)))
                  (assert
                   (equal ollama-kit::+default-base-url+
                          (ollama-kit::client-base-url default-client))))
                (let ((zero-timeout-client
                       (make-client :network-boundary boundary :timeout 0)))
                  (assert
                   (zerop (ollama-kit::client-timeout zero-timeout-client))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :timeout
                                            -1))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :timeout
                                            "1"))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :allow-insecure-http
                                            1))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :api-key
                                            7))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :api-key
                                            ""))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :api-key
                                            (format nil "bad~Ckey" #\Newline)))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :max-input-length
                                            0))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :max-request-length
                                            0))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (make-client :network-boundary
                                            boundary
                                            :api-key
                                            "secret"
                                            :headers
                                            '(("authorization" . "Basic x"))))))
                (let ((client
                       (make-client :network-boundary
                                    boundary
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
