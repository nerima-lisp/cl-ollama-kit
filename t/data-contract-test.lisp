(in-package #:ollama-kit/test)

(defun %signals-p (type thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (condition (condition)
      (typep condition type))))

(defun %with-temporary-binary-input (octets function)
  (let ((pathname
          (merge-pathnames
           (format nil "cl-ollama-kit-test-~D.bin"
                   (get-internal-real-time))
           (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (with-open-file (output pathname
                                   :direction :output
                                   :if-exists :supersede
                                   :element-type '(unsigned-byte 8))
             (write-sequence octets output))
           (with-open-file (input pathname
                                  :direction :input
                                  :element-type '(unsigned-byte 8))
             (funcall function input)))
      (when (probe-file pathname)
        (delete-file pathname)))))

(defun %read-all-characters (stream)
  (with-output-to-string (output)
    (loop for character = (read-char stream nil nil)
          while character
          do (write-char character output))))

(describe "JSON data contracts"
  (it "normalizes values and supports the accepted object representations"
    (let ((vector #(1 2 3))
          (hash (make-hash-table :test #'equal)))
      (setf (gethash "answer" hash) 42)
      (assert (equal "user" (ollama-kit::%json-enum :user)))
      (assert (equal "value" (ollama-kit::%json-enum "value")))
      (assert (eq json-kit:+json-false+
                  (ollama-kit::%native-bool json-kit:+json-false+)))
      (assert (eq t (ollama-kit::%native-bool t)))
      (let ((client
              (client-with-request-function
               (lambda (request &key timeout)
                 (declare (ignore request timeout))
                 (response-with-text "{}")))))
        (assert (%signals-p
                 'ollama-argument-error
                 (lambda ()
                   (generate client "model" "prompt" :raw 1)))))
      (assert (eq vector (ollama-kit::%json-array vector)))
      (assert (equalp #(1 2 3) (ollama-kit::%json-array '(1 2 3))))
      (assert (eql 7 (ollama-kit::%json-array 7)))
      (assert (equal "name" (ollama-kit::%json-key :name)))
      (assert (equal "name" (ollama-kit::%json-key "name")))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (ollama-kit::%json-key 7))))
      (multiple-value-bind (value present-p)
          (ollama-kit::%json-field hash "answer")
        (assert present-p)
        (assert (= 42 value)))
      (multiple-value-bind (value present-p)
          (ollama-kit::%json-field '(("answer" . 42)) "answer")
        (assert present-p)
        (assert (= 42 value)))
      (multiple-value-bind (value present-p)
          (ollama-kit::%json-field '(not-an-object) "answer")
        (declare (ignore value))
        (assert (not present-p)))
      (multiple-value-bind (value present-p)
          (ollama-kit::%json-field nil "answer")
        (declare (ignore value))
        (assert (not present-p)))
      (multiple-value-bind (value present-p)
          (ollama-kit::%json-field 7 "answer")
        (declare (ignore value))
        (assert (not present-p)))
      (let ((object (json-object "answer" 42)))
        (multiple-value-bind (value present-p)
            (ollama-kit::%json-field object "answer")
          (assert present-p)
          (assert (= 42 value)))
        (multiple-value-bind (value present-p)
            (ollama-kit::%json-field object "missing")
          (declare (ignore value))
          (assert (not present-p)))
        (assert (consp (ollama-kit::%json-object-members object))))
      (let ((ordered (json-kit:make-json-object '(("answer" . 42)))))
        (multiple-value-bind (value present-p)
            (ollama-kit::%json-field ordered "missing")
          (declare (ignore value))
          (assert (not present-p))))
      (assert (consp (ollama-kit::%json-object-members hash)))
      (assert (equal '(("answer" . 42))
                     (ollama-kit::%json-object-members '(("answer" . 42)))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%json-object-members 7))))
      (let ((updated
              (ollama-kit::%json-object-with-field
               '(("answer" . 1) ("other" . 2))
               "answer"
               42)))
        (multiple-value-bind (value present-p)
            (ollama-kit::%json-field updated "answer")
          (assert present-p)
          (assert (= 42 value))))))

  (it "constructs optional message fields without guessing absent values"
    (let ((message
            (make-message
             :user
             "Hello"
             :name "Ada"
             :tool-calls '("tool-call")
             :thinking t
             :images '("base64-image"))))
      (multiple-value-bind (role role-p) (ollama-kit::%json-field message "role")
        (assert role-p)
        (assert (equal "user" role)))
      (multiple-value-bind (images images-p)
          (ollama-kit::%json-field message "images")
        (assert images-p)
        (assert (vectorp images)))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (json-object "odd")))))))

(describe "HTTP validation contracts"
  (it "normalizes methods and headers while rejecting unsafe values"
    (assert (eq :post (ollama-kit::%normalize-method :post)))
    (assert (eq :post (ollama-kit::%normalize-method 'post)))
    (assert (eq :patch (ollama-kit::%normalize-method "patch")))
    (let* ((extension-name (symbol-name (gensym "X-OLLAMA-")))
           (normalized-name (string-upcase extension-name)))
      (assert (equal normalized-name
                     (ollama-kit::%normalize-method extension-name)))
      (assert (null (find-symbol normalized-name :keyword))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-method "bad method"))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-method ""))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-method 7))))
    (assert (equal "x-test" (ollama-kit::%normalize-header-name :x-test)))
    (assert (equal "X-Test" (ollama-kit::%normalize-header-name "X-Test")))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-header-name 7))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-header-name ""))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-header-name "bad name"))))
    (assert (equal '( ("x-test" . "one") ("Y-Test" . "two"))
                   (ollama-kit::%normalize-headers
                    '((:x-test . "one") ("Y-Test" . "two")))))
    (assert (null (ollama-kit::%normalize-headers nil)))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-headers 7))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-headers '(7)))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (ollama-kit::%normalize-headers '(("x"))))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%normalize-headers
                           `(("x" . ,(format nil "bad~Cvalue" #\Newline)))))))
    (let ((headers '(("x-test" . "one"))))
      (assert (eq headers
                  (ollama-kit::%ensure-header headers "x-test" "two")))
      (let ((with-new (ollama-kit::%ensure-header headers "y-test" "two")))
        (assert (equal "two" (cdr (assoc "y-test" with-new :test #'string=)))))
      (let ((forced (ollama-kit::%force-header headers "x-test" "three")))
        (assert (equal '(("x-test" . "three")) forced)))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%ensure-header nil "x-test" 7))))))

  (it "validates base URLs, paths, and configured client limits"
    (let ((boundary
            (cl-boundary-kit:make-network-boundary
             :request-fn (lambda (request &key timeout)
                           (declare (ignore request timeout))
                           (response-with-text "{}")))))
      (assert (equal "http://localhost:11434/api"
                     (ollama-kit::%trim-base-url
                      "http://localhost:11434/api///")))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (ollama-kit::%trim-base-url "///"))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (ollama-kit::%trim-base-url ""))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (ollama-kit::%trim-base-url nil))))
      (assert (ollama-kit::%base-url-loopback-p "http://localhost"))
      (assert (ollama-kit::%base-url-loopback-p "http://127.0.0.1:8080"))
      (assert (ollama-kit::%base-url-loopback-p "http://[::1]:8080"))
      (assert (not (ollama-kit::%base-url-loopback-p "http://user@localhost")))
      (assert (not (ollama-kit::%base-url-loopback-p "https://example.test")))
      (assert (ollama-kit::%decimal-port-p "0"))
      (assert (ollama-kit::%decimal-port-p "65535"))
      (assert (not (ollama-kit::%decimal-port-p "")))
      (assert (not (ollama-kit::%decimal-port-p "65536")))
      (assert (not (ollama-kit::%decimal-port-p "12é")))
      (assert (not (ollama-kit::%decimal-port-p
                   (make-string 100000 :initial-element #\9))))
      (assert (ollama-kit::%valid-host-authority-p "example.test:443"))
      (assert (ollama-kit::%valid-host-authority-p "[2001:db8::1]:443"))
      (assert (ollama-kit::%valid-host-authority-p "[::1]"))
      (assert (ollama-kit::%valid-host-authority-p "[::1]:443"))
      (assert (not (ollama-kit::%valid-host-authority-p "")))
      (assert (not (ollama-kit::%valid-host-authority-p "user@example.test")))
      (assert (not (ollama-kit::%valid-host-authority-p "example.test:bad")))
      (assert (not (ollama-kit::%valid-host-authority-p "[::1]x")))
      (assert (not (ollama-kit::%valid-host-authority-p "[::1]:bad")))
      (dolist (authority '("[::[1]" "example[.test" "example].test"))
        (assert (not (ollama-kit::%valid-host-authority-p authority))))
      (assert (equal "http://localhost:11434/api/x"
                     (ollama-kit::%validate-http-request-url
                      "http://localhost:11434/api/x")))
      (assert (equal "http://localhost:11434"
                     (ollama-kit::%validate-http-request-url
                      "http://localhost:11434")))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%validate-http-request-url "x"))))
      (dolist (url '("ftp://localhost/x"
                     "http:///x"
                     "http://example.test:bad/x"
                     "http://example.test/a/../b"
                     "http://example.test/a%2eb"
                     "http://example.test/#fragment"
                     "http://example.test/a b"))
        (assert (%signals-p 'ollama-argument-error
                            (lambda ()
                              (ollama-kit::%validate-http-request-url url)))))
      (assert (equal "https://example.test/api"
                     (ollama-kit::%validate-base-url
                      "https://example.test/api" nil)))
      (assert (equal "http://example.test/api"
                     (ollama-kit::%validate-base-url
                      "http://example.test/api" t)))
      (assert (equal "https://example.test"
                     (ollama-kit::%validate-base-url
                      "https://example.test" nil)))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%validate-base-url "x" nil))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%validate-base-url
                             (format nil "https://example.test/~C"
                                     (code-char 127))
                             nil))))
      (dolist (base-url '("http://example.test/api?query=1"
                          "http://example.test/api#fragment"
                          "http://example.test/api/./x"
                          "ftp://example.test/api"
                          "http://example.test:bad/api"
                          "http://example.test/api"))
        (assert (%signals-p 'ollama-argument-error
                            (lambda ()
                              (ollama-kit::%validate-base-url base-url nil)))))
      (assert (equal "/v1/models?limit=1"
                     (ollama-kit::%validate-request-path "/v1/models?limit=1")))
      (dolist (path '(nil "" "v1 models" "http://example.test" "/a/../b"
                      "/a\\b" "/a#fragment"))
        (assert (%signals-p 'ollama-argument-error
                            (lambda ()
                              (ollama-kit::%validate-request-path path)))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client))))
      (let ((default-client (make-client :network-boundary boundary)))
        (assert (equal ollama-kit::+default-base-url+
                       (ollama-kit::client-base-url default-client))))
      (let ((zero-timeout-client
              (make-client :network-boundary boundary :timeout 0)))
        (assert (zerop (ollama-kit::client-timeout zero-timeout-client))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :timeout -1))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :timeout "1"))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :allow-insecure-http 1))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :api-key 7))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :api-key ""))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :api-key (format nil "bad~Ckey" #\Newline)))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :max-input-length 0))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :max-request-length 0))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (make-client
                                       :network-boundary boundary
                                       :api-key "secret"
                                       :headers '(("authorization" . "Basic x"))))))
      (let ((client (make-client
                     :network-boundary boundary
                     :base-url "http://example.test/api"
                     :api-key "secret"
                     :allow-insecure-http t)))
        (assert (equal "http://example.test/api"
                       (ollama-kit::client-base-url client)))
        (assert (equal "Bearer secret"
                       (cdr (assoc "Authorization"
                                   (ollama-kit::client-headers client)
                                   :test #'string=))))))))

(describe "HTTP body and response contracts"
  (it "decodes text, octets, streams, and JSON error bodies"
    (let ((octets (cl-codec-kit:string-to-octets "日本" :encoding :utf-8)))
      (assert (equal "" (ollama-kit::%decode-response-body nil 16)))
      (assert (equal "text" (ollama-kit::%decode-response-body "text" 16)))
      (assert (equal "日本" (ollama-kit::%decode-response-body octets 16)))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (ollama-kit::%decode-response-body "x" 0))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%decode-response-body "toolong" 3))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%decode-response-body '(1 2) 16))))
      (assert (eq json-kit:+json-null+
                  (ollama-kit::%parse-json-text "" 16)))
      (assert (hash-table-p (ollama-kit::%parse-json-text "{\"x\":1}" 16)))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%parse-json-text
                             (format nil "{\"~C\":1}" (code-char #xe9))
                             2))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%parse-json-text "{" 16))))
      (let* ((response (make-http-response :status 200 :body "text"))
             (stream (ollama-kit::%response-input-stream response 16)))
        (assert (streamp stream))
        (assert (equal #\t (read-char stream))))
      (let ((response (make-http-response :status 200 :body octets)))
        (assert (equal "日本"
                       (%read-all-characters
                        (ollama-kit::%response-input-stream response 16)))))
      (let ((response (make-http-response :status 200)))
        (assert (equal ""
                       (%read-all-characters
                        (ollama-kit::%response-input-stream response 16)))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%response-input-stream
                             (ollama-kit::%make-http-response
                              :status 200
                              :body '(1 2))
                             16))))
      (let ((data (ollama-kit::%http-error-data "{\"error\":\"bad\"}" 16)))
        (assert (hash-table-p data))
        (assert (equal "bad" (gethash "error" data))))
      (assert (null (ollama-kit::%http-error-data "{" 16)))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%ensure-success nil
                                                         (make-client
                                                          :network-boundary
                                                          (cl-boundary-kit:make-test-network-boundary))))))))

  (it "reads character and binary response streams within their limits"
    (let ((character-stream (make-string-input-stream "日本")))
      (assert (equal "日本"
                     (ollama-kit::%read-response-stream-string
                      character-stream 16))))
    (assert (%signals-p 'ollama-protocol-error
                        (lambda ()
                          (ollama-kit::%read-response-stream-string
                           (make-string-input-stream "abcd") 3))))
    (let ((octets (cl-codec-kit:string-to-octets "日本" :encoding :utf-8)))
      (%with-temporary-binary-input
       octets
       (lambda (stream)
         (assert (equal "日本"
                        (ollama-kit::%read-response-stream-string stream 16)))))
      (%with-temporary-binary-input
       (make-array 4
                   :element-type '(unsigned-byte 8)
                   :initial-contents '(1 2 3 4))
       (lambda (stream)
         (assert (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%read-response-stream-string
                                stream 3))))))))

  (it "validates request and response object construction and cleanup"
    (assert (not (response-success-p nil)))
    (assert (not (response-success-p
                  (ollama-kit::%make-http-response :status 500))))
    (assert (not (response-success-p
                  (ollama-kit::%make-http-response :status "200"))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (make-http-request :url ""))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-request
                           :url "http://localhost/x"
                           :stream-p 1))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-request
                           :url "http://localhost/x"
                           :body '(1 2)))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (make-http-response :status 99))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-response
                           :status 200
                           :body "x"
                           :stream (make-string-input-stream "x")))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-response :status 200 :body '(1 2)))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-response :status 200 :stream 7))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (make-http-response :status 200 :close-function 7))))
    (let ((closed 0)
          (stream (make-string-input-stream "x")))
      (let ((response (make-http-response
                       :status 200
                       :stream stream
                       :close-function (lambda () (incf closed)))))
        (assert (response-success-p response))
        (close-http-response response)
        (close-http-response response)
        (assert (= 1 closed))))
    (let ((response
            (make-http-response
             :status 200
             :close-function (lambda () (error "close failure")))))
      (assert (%signals-p 'ollama-transport-error
                          (lambda () (close-http-response response))))
      (assert (null (ollama-kit::http-response-close-function response)))
      (assert (null (ollama-kit::http-response-stream response))))
    (let ((typed
            (make-condition 'ollama-transport-error
                            :message "already typed"
                            :cause nil)))
      (assert (eq typed (ollama-kit::%close-error typed))))
    (let ((previous
            (make-condition 'ollama-transport-error
                            :message "previous"
                            :cause nil)))
      (assert (eq previous
                  (ollama-kit::%close-resource
                   (lambda () (error "second close failure"))
                   previous))))
    (assert (eql 7 (ollama-kit::%close-http-response 7)))
    (assert (%signals-p 'ollama-argument-error
                        (lambda () (close-http-response nil))))))
