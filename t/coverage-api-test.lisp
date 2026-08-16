(in-package #:ollama-kit/test)

(describe "native endpoint families"
          (it "covers JSON and streaming endpoint declarations"
              (let* ((captured (list nil))
                     (json-client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore timeout))
                         (setf (car captured) request)
                         (response-with-text "{}"))))
                     (stream-client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore timeout))
                         (setf (car captured) request)
                         (coverage-stream-response)))))
                (coverage-json-call
                 (lambda ()
                   (chat json-client
                         "model"
                         (list (make-message "user" "hello")))))
                (assert (coverage-path-p (car captured) "/api/chat"))
                (coverage-json-call
                 (lambda ()
                   (embed json-client "model" '("one" "two"))))
                (assert (coverage-path-p (car captured) "/api/embed"))
                (coverage-json-call
                 (lambda ()
                   (show-model json-client "model")))
                (assert (coverage-path-p (car captured) "/api/show"))
                (coverage-json-call
                 (lambda ()
                   (copy-model json-client "source" "destination")))
                (assert (coverage-path-p (car captured) "/api/copy"))
                (coverage-json-call
                 (lambda ()
                   (delete-model json-client "model")))
                (assert (coverage-path-p (car captured) "/api/delete"))
                (coverage-json-call
                 (lambda ()
                   (pull-model json-client "model")))
                (assert (coverage-path-p (car captured) "/api/pull"))
                (coverage-json-call
                 (lambda ()
                   (push-model json-client "model")))
                (assert (coverage-path-p (car captured) "/api/push"))
                (coverage-stream-call
                 (lambda ()
                   (chat-stream stream-client "model" #())))
                (assert (coverage-path-p (car captured) "/api/chat"))
                (coverage-json-call
                 (lambda ()
                   (embed json-client
                          "model"
                          '("one" "two")
                          :dimensions
                          768
                          :keep-alive
                          "5m")))
                (assert (coverage-path-p (car captured) "/api/embed"))
                (coverage-stream-call
                 (lambda ()
                   (create-model-stream stream-client "model")))
                (assert (coverage-path-p (car captured) "/api/create"))
                (coverage-stream-call
                 (lambda ()
                   (pull-model-stream stream-client "model")))
                (assert (coverage-path-p (car captured) "/api/pull"))
                (coverage-stream-call
                 (lambda ()
                   (push-model-stream stream-client "model")))
                (assert (coverage-path-p (car captured) "/api/push")))))

(describe "web endpoint families"
          (it "covers search and fetch operations"
              (let* ((captured (list nil))
                     (client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore timeout))
                         (setf (car captured) request)
                         (response-with-text "{}")))))
                (coverage-json-call
                 (lambda ()
                   (web-search client "query")))
                (assert (coverage-path-p (car captured) "/api/web_search"))
                (coverage-json-call
                 (lambda ()
                   (web-search client "query" :max-results 5)))
                (assert (coverage-path-p (car captured) "/api/web_search"))
                (coverage-json-call
                 (lambda ()
                   (web-fetch client "https://example.com")))
                (assert (coverage-path-p (car captured) "/api/web_fetch")))))

(describe "OpenAI-compatible endpoint families"
          (it
           "covers model, completion, embedding, response, and image operations"
           (let* ((captured (list nil))
                  (client
                   (openai-client-with-request-function
                    (lambda (request &key timeout)
                      (declare (ignore timeout))
                      (setf (car captured) request)
                      (response-with-text "{}"))))
                  (body (json-object "model" "model")))
             (coverage-json-call
              (lambda ()
                (openai-models client)))
             (assert (coverage-path-p (car captured) "/v1/models"))
             (coverage-json-call
              (lambda ()
                (openai-model client "model")))
             (assert (coverage-path-p (car captured) "/v1/models/model"))
             (coverage-json-call
              (lambda ()
                (openai-chat-completions client body)))
             (assert (coverage-path-p (car captured) "/v1/chat/completions"))
             (coverage-json-call
              (lambda ()
                (openai-completions client body)))
             (assert (coverage-path-p (car captured) "/v1/completions"))
             (coverage-json-call
              (lambda ()
                (openai-embeddings client body)))
             (assert (coverage-path-p (car captured) "/v1/embeddings"))
             (coverage-json-call
              (lambda ()
                (openai-responses client body)))
             (assert (coverage-path-p (car captured) "/v1/responses"))
             (coverage-json-call
              (lambda ()
                (openai-images client body)))
             (assert (coverage-path-p (car captured) "/v1/images/generations")))))

(it "forces stream mode for every OpenAI streaming operation"
    (let* ((captured (list nil))
           (client
            (openai-client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf (car captured) request)
               (make-http-response :status
                                   200
                                   :headers
                                   '(("content-type" . "text/event-stream"))
                                   :stream
                                   (make-string-input-stream
                                    (format nil "data: {}~%~%data: [DONE]~%~%"))))))
           (body (json-object "model" "model")))
      (coverage-stream-call
       (lambda ()
         (openai-chat-completions-stream client body)))
      (assert (coverage-path-p (car captured) "/v1/chat/completions"))
      (assert (eq t (gethash "stream" (request-json-object (car captured)))))
      (coverage-stream-call
       (lambda ()
         (openai-completions-stream client body)))
      (assert (coverage-path-p (car captured) "/v1/completions"))
      (coverage-stream-call
       (lambda ()
         (openai-responses-stream client body)))
      (assert (coverage-path-p (car captured) "/v1/responses"))))
