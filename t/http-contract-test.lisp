(in-package #:ollama-kit/test)

(describe "HTTP body and response contracts"
          (it "decodes text, octets, streams, and JSON error bodies"
              (let ((octets
                     (cl-codec-kit:string-to-octets "日本" :encoding :utf-8)))
                (assert (equal "" (ollama-kit::%decode-response-body nil 16)))
                (assert
                 (equal "text" (ollama-kit::%decode-response-body "text" 16)))
                (assert
                 (equal "日本" (ollama-kit::%decode-response-body octets 16)))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (ollama-kit::%decode-response-body "x" 0))))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%decode-response-body "toolong" 3))))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%decode-response-body '(1 2) 16))))
                (assert
                 (eq json-kit:+json-null+ (ollama-kit::%parse-json-text "" 16)))
                (assert
                 (hash-table-p (ollama-kit::%parse-json-text "{\"x\":1}" 16)))
                (assert
                 (hash-table-p (ollama-kit::%parse-json-text "{\"x\":1}" 16 t)))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%parse-json-text
                                (format nil "{\"~C\":1}" (code-char #xe9))
                                2))))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%parse-json-text "{" 16))))
                (let* ((response (make-http-response :status 200 :body "text"))
                       (stream (ollama-kit::%response-input-stream response 16)))
                  (assert (streamp stream))
                  (assert (equal #\t (read-char stream))))
                (let ((response (make-http-response :status 200 :body octets)))
                  (assert
                   (equal "日本"
                          (%read-all-characters
                           (ollama-kit::%response-input-stream response 16)))))
                (let ((response (make-http-response :status 200)))
                  (assert
                   (equal ""
                          (%read-all-characters
                           (ollama-kit::%response-input-stream response 16)))))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%response-input-stream
                                (ollama-kit::%make-http-response :status
                                                                 200
                                                                 :body
                                                                 '(1 2))
                                16))))
                (let ((data
                       (ollama-kit::%http-error-data "{\"error\":\"bad\"}" 16)))
                  (assert (hash-table-p data))
                  (assert (equal "bad" (gethash "error" data))))
                (assert (null (ollama-kit::%http-error-data "{" 16)))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (ollama-kit::%ensure-success nil
                                                            (make-client
                                                             :network-boundary
                                                             (cl-boundary-kit:make-test-network-boundary))))))))
          (it "reads character and binary response streams within their limits"
              (let ((character-stream (make-string-input-stream "日本")))
                (assert
                 (equal "日本"
                        (ollama-kit::%read-response-stream-string
                         character-stream
                         16))))
              (assert
               (%signals-p 'ollama-protocol-error
                           (lambda ()
                             (ollama-kit::%read-response-stream-string
                              (make-string-input-stream "abcd")
                              3))))
              (let ((octets
                     (cl-codec-kit:string-to-octets "日本" :encoding :utf-8)))
                (%with-temporary-binary-input octets
                                              (lambda (stream)
                                                (assert
                                                 (equal "日本"
                                                        (ollama-kit::%read-response-stream-string
                                                         stream
                                                         16)))))
                (%with-temporary-binary-input
                 (make-array 4
                             :element-type
                             '(unsigned-byte 8)
                             :initial-contents
                             '(1 2 3 4))
                 (lambda (stream)
                   (assert
                    (%signals-p 'ollama-protocol-error
                                (lambda ()
                                  (ollama-kit::%read-response-stream-string
                                   stream
                                   3))))))))
          (it "validates request and response object construction and cleanup"
              (assert (not (response-success-p nil)))
              (assert
               (not
                (response-success-p
                 (ollama-kit::%make-http-response :status 500))))
              (assert
               (not
                (response-success-p
                 (ollama-kit::%make-http-response :status "200"))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-request :url ""))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-request :url
                                                "http://localhost/x"
                                                :stream-p
                                                1))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-request :url
                                                "http://localhost/x"
                                                :body
                                                '(1 2)))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-response :status 99))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-response :status
                                                 200
                                                 :body
                                                 "x"
                                                 :stream
                                                 (make-string-input-stream "x")))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-response :status 200 :body '(1 2)))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-response :status 200 :stream 7))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (make-http-response :status 200 :close-function 7))))
              (let ((closed 0)
                    (stream (make-string-input-stream "x")))
                (let ((response
                       (make-http-response :status
                                           200
                                           :stream
                                           stream
                                           :close-function
                                           (lambda ()
                                             (incf closed)))))
                  (assert (response-success-p response))
                  (close-http-response response)
                  (close-http-response response)
                  (assert (= 1 closed))))
              (let ((response
                     (make-http-response :status
                                         200
                                         :close-function
                                         (lambda ()
                                           (error "close failure")))))
                (assert
                 (%signals-p 'ollama-transport-error
                             (lambda ()
                               (close-http-response response))))
                (assert
                 (null (ollama-kit::http-response-close-function response)))
                (assert (null (ollama-kit::http-response-stream response))))
              (let ((typed
                     (make-condition 'ollama-transport-error
                                     :message
                                     "already typed"
                                     :cause
                                     nil)))
                (assert (eq typed (ollama-kit::%close-error typed))))
              (let ((previous
                     (make-condition 'ollama-transport-error
                                     :message
                                     "previous"
                                     :cause
                                     nil)))
                (assert
                 (eq previous
                     (ollama-kit::%close-resource
                      (lambda ()
                        (error "second close failure"))
                      previous))))
              (assert (eql 7 (ollama-kit::%close-http-response 7)))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (close-http-response nil))))))
