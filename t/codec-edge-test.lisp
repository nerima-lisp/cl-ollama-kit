(in-package #:ollama-kit/test)

(describe "Codec and data edge contracts"
  (it "bounds JSON serialization before UTF-8 encoding"
    (let ((encoded (ollama-kit::%encode-json "あ" 5)))
      (assert (= 5 (length encoded)))
      (assert (equal "\"あ\""
                     (cl-codec-kit:octets-to-string encoded :encoding :utf-8))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%encode-json "あ" 4))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%encode-json (make-string 32
                                                                   :initial-element #\x)
                                                    8))))
    (let ((cycle (list nil)))
      (setf (car cycle) cycle)
      (assert (%signals-p 'json-kit:json-serialization-error
                          (lambda ()
                            (ollama-kit::%encode-json cycle 128))))))

  (it "handles ordered JSON objects and strict generated headers"
    (let ((object
            (json-kit:alist->json-object
             '(("answer" . 42))
             :duplicate-key-policy :preserve)))
      (multiple-value-bind (value present-p)
          (ollama-kit::%json-field object "answer")
        (assert present-p)
        (assert (= 42 value)))
      (assert (equal '(("answer" . 42))
                     (ollama-kit::%json-object-members object))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%ensure-header
                           nil
                           "X-Test"
                           (format nil "unsafe~Cvalue" #\Newline))))))

  (it "covers raw body sizing and response stream representations"
    (let ((octets
            (make-array 2
                        :element-type '(unsigned-byte 8)
                        :initial-contents '(65 66))))
      (assert (= 3 (ollama-kit::%request-body-length "abc")))
      (assert (= 9 (ollama-kit::%request-body-length "あいう")))
      (assert (= 2 (ollama-kit::%request-body-length octets)))
      (assert (null (ollama-kit::%request-body-length nil)))
      (assert (null (ollama-kit::%request-body-length '(1 2)))))
    (let* ((input (make-string-input-stream "stream"))
           (response (make-http-response :status 200 :stream input)))
      (assert (eq input (ollama-kit::%response-input-stream response 32)))
      (assert (equal "stream"
                     (ollama-kit::%response-body-string response 32))))
    (assert (%signals-p 'ollama-argument-error
                        (lambda ()
                          (ollama-kit::%decode-response-body
                           "x"
                           0)))))
    (let ((incomplete
            (make-array 1
                        :element-type '(unsigned-byte 8)
                        :initial-element #xC3))
          (invalid
            (make-array 1
                        :element-type '(unsigned-byte 8)
                        :initial-element #xFF)))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%decode-response-body incomplete))))
      (assert (%signals-p 'ollama-protocol-error
                          (lambda ()
                            (ollama-kit::%decode-response-body invalid)))))

  (it "extracts nested API error messages and closes failed responses"
    (let* ((closed 0)
          (client
            (queued-client
             (make-http-response
              :status 500
              :body "{\"error\":{\"message\":\"nested failure\"}}"
              :close-function (lambda () (incf closed))))))
      (let ((caught nil))
        (handler-case
            (request-json client :get "/version")
          (ollama-api-error (condition)
            (setf caught t)
            (assert (equal "nested failure"
                           (ollama-error-message condition)))))
        (assert caught))
      (assert (= 1 closed))))

  (it "preserves request errors when response cleanup fails"
    (let* ((response
             (make-http-response
              :status 200
              :body "{"
              :close-function (lambda () (error "close failure"))))
           (client (queued-client response))
           (caught nil)
           (cleanup-warning nil))
      (handler-bind
          ((warning (lambda (condition)
                      (declare (ignore condition))
                      (setf cleanup-warning t)
                      (muffle-warning))))
        (handler-case
            (request-json client :get "/version")
          (ollama-protocol-error (condition)
            (setf caught condition))))
      (assert (typep caught 'ollama-protocol-error))
      (assert cleanup-warning)
      (assert (null (ollama-kit::http-response-close-function response)))
      (assert (null (ollama-kit::http-response-stream response)))))

  (it "falls back to HTTP errors for malformed nested messages"
    (let* ((closed 0)
           (client
             (queued-client
              (make-http-response
               :status 500
               :body "{\"error\":{\"message\":42}}"
               :close-function (lambda () (incf closed))))))
      (assert (%signals-p 'ollama-http-error
                          (lambda ()
                            (request-json client :get "/version"))))
      (assert (= 1 closed)))))
