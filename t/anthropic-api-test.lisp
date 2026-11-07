(in-package #:ollama-kit/test)

(defun anthropic-client-with-request-function (request-fn &rest options)
  (apply #'make-anthropic-client
         :network-boundary
         (cl-boundary-kit:make-network-boundary :request-fn request-fn)
         options))

(defun request-header (request name)
  (cdr
   (find name (http-request-headers request) :key #'car :test #'string-equal)))

(describe "Anthropic compatibility API"
          (it "uses the v1 Messages path and X-API-KEY authentication"
              (let ((captured nil))
                (let ((client
                       (anthropic-client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (response-with-text "{}"))
                        :api-key
                        "anthropic-test-key"
                        :headers
                        '(("anthropic-version" . "2023-06-01")))))
                  (let ((value
                         (anthropic-messages client
                                             (json-object "model"
                                                          "model"
                                                          "max_tokens"
                                                          32
                                                          "messages"
                                                          (vector
                                                           (make-message "user"
                                                                         "Hello."))))))
                    (declare (ignore value))))
                (assert (equal :post (http-request-method captured)))
                (assert
                 (equal "http://localhost:11434/v1/messages"
                        (http-request-url captured)))
                (assert
                 (equal "anthropic-test-key"
                        (request-header captured "x-api-key")))
                (assert
                 (equal "2023-06-01"
                        (request-header captured "anthropic-version")))
                (assert (not (request-header captured "authorization")))
                (let ((body (request-json-object captured)))
                  (assert (equal "model" (gethash "model" body)))
                  (assert (= 32 (gethash "max_tokens" body))))))
          (it "preserves a caller-provided X-API-KEY without an API key option"
              (let* ((client
                      (anthropic-client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore request timeout))
                         (response-with-text "{}"))
                       :headers
                       '(("x-api-key" . "provided"))))
                     (headers (client-headers client)))
                (assert
                 (equal "provided"
                        (cdr (assoc "x-api-key" headers :test #'string-equal))))))
          (it "forces streaming and decodes Anthropic SSE events"
  (let ((captured nil)
        (events nil))
    (let ((client
           (anthropic-client-with-request-function
            (lambda (request &key timeout)
              (declare (ignore timeout))
              (setf captured request)
              (make-http-response :status
                                  200
                                  :headers
                                  (list (cons "content-type" "text/event-stream"))
                                  :stream
                                  (make-string-input-stream
                                   (format nil
                                           "event: message_start~%data: {\"type\":\"message_start\"}~%~%data: [DONE]~%~%"))))))
          (body (json-object "model" "model" "stream" nil)))
      (anthropic-messages-stream client
                                 body
                                 (lambda (event)
                                   (push event events)))
      (assert (equal :post (http-request-method captured)))
      (assert
       (equal "http://localhost:11434/v1/messages"
              (http-request-url captured)))
      (let ((request-body (request-json-object captured)))
        (assert (eq t (gethash "stream" request-body))))
      (assert (= 1 (length events)))
      (assert (equal "message_start"
                     (gethash "type" (first events))))))))
