(in-package #:ollama-kit/test)

(describe "OpenAI-compatible API contracts"
  (it "lists models through the OpenAI-compatible endpoint"
    (let ((captured (list nil)))
      (let ((value
              (openai-models
               (openai-client-with-request-function
                (lambda (request &key timeout)
                  (declare (ignore timeout))
                  (setf (car captured) request)
                  (response-with-text
                   "{\"object\":\"list\",\"data\":[{\"id\":\"model\",\"object\":\"model\",\"owned_by\":\"ollama\"}]}"))))))
        (let* ((request (car captured))
               (models (gethash "data" value))
               (model (aref models 0)))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :get (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/models"
                           (http-request-url request)))
          (assert (null (http-request-body request)))
          (assert (equal "list" (gethash "object" value)))
          (assert (equal "model" (gethash "id" model)))
          (assert (equal "ollama" (gethash "owned_by" model)))))))

  (it "retrieves one model through the OpenAI-compatible endpoint"
    (let ((captured (list nil)))
      (let ((value
              (openai-model
               (openai-client-with-request-function
                (lambda (request &key timeout)
                  (declare (ignore timeout))
                  (setf (car captured) request)
                  (response-with-text
                   "{\"id\":\"model\",\"object\":\"model\",\"owned_by\":\"ollama\"}")))
               "model")))
        (let ((request (car captured)))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :get (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/models/model"
                           (http-request-url request)))
          (assert (null (http-request-body request)))
          (assert (equal "model" (gethash "id" value)))
          (assert (equal "model" (gethash "object" value)))))))

  (it "sends chat JSON bodies including generic tool and response format fields"
    (let ((captured (list nil))
          (body
            (json-object
             "model" "model"
             "messages" (vector (json-object "role" "user" "content" "Hello"))
             "tools" (vector
                      (json-object
                       "type" "function"
                       "function"
                       (json-object
                        "name" "lookup"
                        "parameters" (json-object "type" "object"))))
             "response_format" (json-object "type" "json_object"))))
      (let ((value
              (openai-chat-completions
               (openai-client-with-request-function
                (lambda (request &key timeout)
                  (declare (ignore timeout))
                  (setf (car captured) request)
                  (response-with-text
                   "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"ok\\\":true}\"},\"finish_reason\":\"stop\"}]}")))
               body)))
        (let* ((request (car captured))
               (sent (request-json-object request))
               (messages (gethash "messages" sent))
               (tools (gethash "tools" sent))
               (tool (aref tools 0))
               (function (gethash "function" tool))
               (choices (gethash "choices" value))
               (choice (aref choices 0))
               (message (gethash "message" choice)))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :post (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/chat/completions"
                           (http-request-url request)))
          (assert (equal "chatcmpl-1" (gethash "id" value)))
          (assert (equal "chat.completion" (gethash "object" value)))
          (assert (equal "{\"ok\":true}" (gethash "content" message)))
          (assert (equal "model" (gethash "model" sent)))
          (assert (equal "Hello"
                         (gethash "content" (aref messages 0))))
          (assert (equal "lookup" (gethash "name" function)))
          (assert (equal "json_object"
                         (gethash "type" (gethash "response_format" sent))))))))

  (it "supports text completions as JSON and SSE"
    (let ((captured (list nil))
          (stream nil)
          (body (json-object "model" "model" "prompt" "Hello")))
      (let ((value
              (openai-completions
               (openai-client-with-request-function
                (lambda (request &key timeout)
                  (declare (ignore timeout))
                  (setf (car captured) request)
                  (response-with-text
                   "{\"id\":\"cmpl-1\",\"object\":\"text_completion\",\"choices\":[{\"text\":\"Hi\",\"index\":0,\"finish_reason\":\"stop\"}]}")))
               body)))
        (let* ((request (car captured))
               (choices (gethash "choices" value))
               (choice (aref choices 0)))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :post (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/completions"
                           (http-request-url request)))
          (assert (equal "cmpl-1" (gethash "id" value)))
          (assert (equal "text_completion" (gethash "object" value)))
          (assert (equal "Hi" (gethash "text" choice)))
          (assert (equal "Hello"
                         (gethash "prompt" (request-json-object request))))))
      (setf stream
            (openai-completions-stream
             (openai-client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (make-http-response
                 :status 200
                 :headers '(("content-type" . "text/event-stream"))
                 :stream
                 (make-string-input-stream
                  (format nil
                          "data: {\"choices\":[{\"text\":\"Hi\"}]}~%~%data: [DONE]~%~%")))))
             body))
      (unwind-protect
           (progn
             (multiple-value-bind (event present-p) (stream-next stream)
               (assert present-p)
               (let* ((choices (gethash "choices" event))
                      (choice (aref choices 0)))
                 (assert (equal "Hi" (gethash "text" choice)))))
             (multiple-value-bind (event present-p) (stream-next stream)
               (declare (ignore event))
               (assert (not present-p)))
             (let ((request (car captured)))
               (assert (http-request-p request))
               (assert (eq :post (http-request-method request)))
               (assert (string= "http://localhost:11434/v1/completions"
                                (http-request-url request)))
               (assert (eq t (gethash "stream" (request-json-object request))))))
          (when stream
            (stream-close stream)))))

  (it "parses chat completion SSE and forces stream mode in the request"
    (let ((captured (list nil))
          (stream nil))
      (setf stream
            (openai-chat-completions-stream
             (openai-client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (make-http-response
                 :status 200
                 :headers '(("content-type" . "text/event-stream"))
                 :stream
                 (make-string-input-stream
                  (format nil
                          "event: message~%data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}~%~%data: [DONE]~%~%")))))
             (json-object "model" "model" "messages" #())
             :headers '(("Accept" . "application/x-ndjson"))))
      (unwind-protect
           (progn
             (multiple-value-bind (event present-p) (stream-next stream)
               (assert present-p)
               (let* ((choices (gethash "choices" event))
                      (choice (aref choices 0))
                      (delta (gethash "delta" choice)))
                 (assert (equal "Hi" (gethash "content" delta)))))
             (multiple-value-bind (event present-p) (stream-next stream)
               (declare (ignore event))
               (assert (not present-p)))
             (let ((request (car captured)))
               (assert (http-request-p request))
               (assert (eq :post (http-request-method request)))
               (assert (string= "http://localhost:11434/v1/chat/completions"
                                (http-request-url request)))
               (assert (equal "text/event-stream"
                              (cdr (assoc "Accept"
                                          (http-request-headers request)
                                          :test #'string-equal))))
               (assert (eq t (gethash "stream"
                                      (request-json-object request))))))
        (when stream
          (stream-close stream)))))

  (it "sends embeddings requests and parses the returned vector"
    (let ((captured (list nil))
          (body (json-object "model" "model"
                             "input" (vector "Hello" "world")
                             "encoding_format" "float")))
      (let ((value
              (openai-embeddings
               (openai-client-with-request-function
                (lambda (request &key timeout)
                  (declare (ignore timeout))
                  (setf (car captured) request)
                  (response-with-text
                   "{\"object\":\"list\",\"data\":[{\"object\":\"embedding\",\"index\":0,\"embedding\":[0.1,0.2]}],\"model\":\"model\",\"usage\":{\"prompt_tokens\":2,\"total_tokens\":2}}")))
               body)))
        (let* ((request (car captured))
               (sent (request-json-object request))
               (input (gethash "input" sent))
               (data (gethash "data" value))
               (embedding (gethash "embedding" (aref data 0))))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :post (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/embeddings"
                           (http-request-url request)))
          (assert (equal "list" (gethash "object" value)))
          (assert (equal "model" (gethash "model" value)))
          (assert (equal "model" (gethash "model" sent)))
          (assert (equal "float" (gethash "encoding_format" sent)))
          (assert (equal "Hello" (aref input 0)))
          (assert (equal "world" (aref input 1)))
          (assert (< (abs (- 0.1 (aref embedding 0))) 0.000001))
          (assert (< (abs (- 0.2 (aref embedding 1))) 0.000001))))))

  (it "supports responses as JSON"
    (let ((captured (list nil))
          (body (json-object "model" "model"
                             "input" "Hello"
                             "temperature" 0)))
      (let ((value
              (openai-responses
               (openai-client-with-request-function
                (lambda (request &key timeout)
                  (declare (ignore timeout))
                  (setf (car captured) request)
                  (response-with-text
                   "{\"id\":\"resp_1\",\"object\":\"response\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}]}")))
               body)))
        (let* ((request (car captured))
               (sent (request-json-object request))
               (output (aref (gethash "output" value) 0))
               (content (aref (gethash "content" output) 0)))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :post (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/responses"
                           (http-request-url request)))
          (assert (equal "resp_1" (gethash "id" value)))
          (assert (equal "response" (gethash "object" value)))
          (assert (equal "completed" (gethash "status" value)))
          (assert (equal "model" (gethash "model" sent)))
          (assert (equal "Hello" (gethash "input" sent)))
          (assert (equal "output_text" (gethash "type" content)))
          (assert (equal "Hello" (gethash "text" content)))))))

  (it "supports responses as SSE and observes completion"
    (let ((captured (list nil))
          (stream nil)
          (body (json-object "model" "model" "input" "Hello")))
      (setf stream
            (openai-responses-stream
             (openai-client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (make-http-response
                 :status 200
                 :headers '(("content-type" . "text/event-stream"))
                 :stream
                 (make-string-input-stream
                  (format nil
                          "event: response.created~%data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"status\":\"in_progress\"}}~%~%event: response.completed~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}~%~%data: [DONE]~%~%")))))
             body))
      (unwind-protect
           (progn
             (multiple-value-bind (event present-p) (stream-next stream)
               (assert present-p)
               (assert (equal "response.created" (gethash "type" event)))
               (assert (equal "resp_1"
                              (gethash "id" (gethash "response" event)))))
             (multiple-value-bind (event present-p) (stream-next stream)
               (assert present-p)
               (assert (equal "response.completed" (gethash "type" event)))
               (assert (equal "completed"
                              (gethash "status" (gethash "response" event)))))
             (multiple-value-bind (event present-p) (stream-next stream)
               (declare (ignore event))
               (assert (not present-p)))
             (let ((request (car captured)))
               (assert (http-request-p request))
               (assert (eq :post (http-request-method request)))
               (assert (string= "http://localhost:11434/v1/responses"
                                (http-request-url request)))
               (let ((sent (request-json-object request)))
                 (assert (equal "model" (gethash "model" sent)))
                 (assert (equal "Hello" (gethash "input" sent)))
                 (assert (eq t (gethash "stream" sent))))))
        (when stream
           (stream-close stream))))))

  (it "supports experimental image generation with the documented fields"
    (let* ((captured (list nil))
           (body (json-object
                  "model" "x/z-image-turbo"
                  "prompt" "A cute robot learning to paint"
                  "size" "1024x1024"
                  "response_format" "b64_json"
                  "n" 1
                  "quality" "standard"
                  "style" "vivid"
                  "user" "test-user"))
           (client
             (openai-client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (response-with-text
                 "{\"created\":1,\"data\":[{\"b64_json\":\"abc\"}]}")))))
      (let ((value (openai-images client body)))
        (let* ((request (car captured))
               (sent (request-json-object request))
               (data (gethash "data" value)))
          (assert (hash-table-p value))
          (assert (http-request-p request))
          (assert (eq :post (http-request-method request)))
          (assert (string= "http://localhost:11434/v1/images/generations"
                           (http-request-url request)))
          (assert (= 1 (gethash "created" value)))
          (assert (equal "x/z-image-turbo" (gethash "model" sent)))
          (assert (equal "A cute robot learning to paint"
                         (gethash "prompt" sent)))
          (assert (equal "1024x1024" (gethash "size" sent)))
          (assert (equal "b64_json" (gethash "response_format" sent)))
          (assert (= 1 (gethash "n" sent)))
          (assert (equal "standard" (gethash "quality" sent)))
          (assert (equal "vivid" (gethash "style" sent)))
          (assert (equal "test-user" (gethash "user" sent)))
          (assert (equal "abc" (gethash "b64_json" (aref data 0))))))))
