(in-package #:ollama-kit/test)

(describe "HTTP body and response contracts"
  (it "decodes UTF-8 response bodies within the configured limit"
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
      (let ((response
              (http-message-kit:make-http-response :status 200 :body octets)))
        (assert (equal "日本"
                       (ollama-kit::%response-body-string response 16)))
        (assert (%signals-p 'ollama-protocol-error
                            (lambda ()
                              (ollama-kit::%response-body-string response 3)))))))
  (it "parses JSON and extracts structured HTTP error bodies"
    (assert (eq json-kit:+json-null+
                (ollama-kit::%parse-json-text "" 16)))
    (assert (hash-table-p
             (ollama-kit::%parse-json-text "{\"x\":1}" 16)))
    (assert (hash-table-p
             (ollama-kit::%parse-json-text "{\"x\":1}" 16 t)))
    (assert (%signals-p 'ollama-protocol-error
                        (lambda ()
                          (ollama-kit::%parse-json-text
                           (format nil "{\"~C\":1}" (code-char #xe9))
                           2))))
    (assert (%signals-p 'ollama-protocol-error
                        (lambda ()
                          (ollama-kit::%parse-json-text "{" 16))))
    (let ((data (ollama-kit::%http-error-data "{\"error\":\"bad\"}" 16)))
      (assert (hash-table-p data))
      (assert (equal "bad" (gethash "error" data))))
    (assert (null (ollama-kit::%http-error-data "{" 16))))
  (it-each
   ((200 t)
    (204 t)
    (302 nil)
    (500 nil))
   "recognizes HTTP status ~A as success"
   (status expected)
   (assert
    (eql expected
         (ollama-kit::response-success-p
          (http-message-kit:make-http-response :status status)))))
  (it "validates response types and maps non-success HTTP responses"
    (let ((client (make-client :max-input-length 64)))
      (unwind-protect
           (progn
             (assert (not (ollama-kit::response-success-p nil)))
             (assert (not (ollama-kit::response-success-p "not a response")))
             (assert (%signals-p 'ollama-protocol-error
                                 (lambda ()
                                   (ollama-kit::%ensure-success nil client))))
             (let ((response
                     (http-message-kit:make-http-response
                      :status 200
                      :body (cl-codec-kit:string-to-octets "{}"
                                                           :encoding :utf-8))))
               (assert (eq response
                           (ollama-kit::%ensure-success response client))))
             (let ((response
                     (http-message-kit:make-http-response
                      :status 500
                      :body (cl-codec-kit:string-to-octets "server failure"
                                                           :encoding :utf-8))))
               (assert (%signals-p 'ollama-http-error
                                   (lambda ()
                                     (ollama-kit::%ensure-success response
                                                                  client)))))
             (let ((response
                     (http-message-kit:make-http-response
                      :status 404
                      :body (cl-codec-kit:string-to-octets
                             "{\"error\":\"missing\"}"
                             :encoding :utf-8))))
               (assert (%signals-p 'ollama-api-error
                                   (lambda ()
                                     (ollama-kit::%ensure-success response
                                                                  client))))))
        (close-client client)))))
