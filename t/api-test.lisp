(in-package #:ollama-kit/test)

(defun request-json-object (request)
  (json-kit:parse
   (cl-codec-kit:octets-to-string (http-request-body request)
                                  :encoding :utf-8)
   :object-type :hash-table
   :array-type :vector))

(describe "native API request contracts"
  (it-each
    ((list-models "/tags" :get)
     (list-running-models "/ps" :get)
     (version "/version" :get))
    "uses ~A for ~A"
    (operation path expected-method)
    (let* ((captured (list nil))
           (client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (response-with-text "{}")))))
      (let ((value (funcall operation client)))
        (declare (ignore value))
        (let ((request (car captured)))
          (assert (http-request-p request))
          (expect (http-request-method request)
                  :to-equal
                  expected-method)
          (expect (http-request-url request)
                  :to-equal
                  (concatenate 'string "http://localhost:11434/api" path))
          (expect (http-request-body request)
                  :to-equal
                  nil)))))

  (it "preserves explicit false, zero, and enum-valued options"
    (let ((captured nil))
      (let ((client
              (client-with-request-function
               (lambda (request &key timeout)
                 (declare (ignore timeout))
                 (setf captured request)
                 (response-with-text "{}")))))
        (generate client "model" "prompt"
                  :format :json
                  :raw nil
                  :think :high
                  :width 768
                  :height 512
                  :steps 4
                  :keep-alive 0
                  :logprobs nil
                  :top-logprobs 0))
      (let ((body (request-json-object captured)))
        (multiple-value-bind (value present-p) (gethash "raw" body)
          (assert present-p)
          (assert (eq json-kit:+json-false+ value)))
        (multiple-value-bind (value present-p) (gethash "think" body)
          (assert present-p)
          (assert (equal "high" value)))
        (multiple-value-bind (value present-p) (gethash "keep_alive" body)
          (assert present-p)
          (assert (= 0 value)))
        (multiple-value-bind (value present-p) (gethash "logprobs" body)
          (assert present-p)
          (assert (eq json-kit:+json-false+ value)))
        (multiple-value-bind (value present-p) (gethash "top_logprobs" body)
          (assert present-p)
          (assert (= 0 value)))
        (assert (= 768 (gethash "width" body)))
        (assert (= 512 (gethash "height" body)))
        (assert (= 4 (gethash "steps" body)))
        (assert (equal "json" (gethash "format" body)))
        (assert (eq json-kit:+json-false+ (gethash "stream" body)))
        (assert (equal :post (http-request-method captured)))
        (assert (equal "http://localhost:11434/api/generate"
                       (http-request-url captured))))))

  (it "preserves the JSON false sentinel for boolean-or-enum options"
    (let ((captured nil))
      (let ((client
              (client-with-request-function
               (lambda (request &key timeout)
                 (declare (ignore timeout))
                 (setf captured request)
                 (response-with-text "{}")))))
        (generate client "model" "prompt"
                  :think json-kit:+json-false+))
      (assert (json-kit:json-false-p
               (gethash "think" (request-json-object captured))))))

  (it "preserves scalar and sequence embedding inputs"
    (let* ((captured (list nil))
           (client
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf (car captured) request)
                (response-with-text "{}")))))
      (let ((value (embed client "model" "single")))
        (declare (ignore value))
        (let ((body (request-json-object (car captured))))
          (assert (equal "single" (gethash "input" body)))))
      (let ((value (embed client "model" #("one" "two")
                          :truncate nil
                          :dimensions 768
                          :keep-alive "5m")))
        (declare (ignore value))
        (let ((body (request-json-object (car captured))))
          (assert (vectorp (gethash "input" body)))
          (assert (equalp #("one" "two") (gethash "input" body)))
          (assert (eq json-kit:+json-false+
                      (gethash "truncate" body)))
          (assert (= 768 (gethash "dimensions" body)))
          (assert (equal "5m" (gethash "keep_alive" body)))))))

  (it "validates native embedding input and option types"
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (error "embedding validation should run before transport")))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda () (embed client "model" 42))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (embed client "model" "text"
                                   :dimensions 1.5))))
      (assert (%signals-p 'ollama-argument-error
                          (lambda ()
                            (embed client "model" "text"
                                   :keep-alive 5))))))

  (it "sends image generation controls for native streaming"
    (let ((captured nil)
          (stream nil))
      (setf stream
            (generate-stream
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (setf captured request)
                (make-http-response
                 :status 200
                 :headers '(("content-type" . "application/x-ndjson"))
                 :stream (make-string-input-stream
                          (format nil "{}~%")))))
             "model" "draw"
             :width 1024
             :height 768
             :steps 12))
      (unwind-protect
           (let ((body (request-json-object captured)))
             (assert (= 1024 (gethash "width" body)))
             (assert (= 768 (gethash "height" body)))
             (assert (= 12 (gethash "steps" body)))
             (assert (eq t (gethash "stream" body))))
        (stream-close stream))))

  (it "sends create renderer and parser options"
    (let ((captured nil))
      (let ((client
              (client-with-request-function
               (lambda (request &key timeout)
                 (declare (ignore timeout))
                 (setf captured request)
                 (response-with-text "{}")))))
        (create-model client "custom"
                      :renderer "ggml"
                      :parser "json"))
      (let ((body (request-json-object captured)))
        (assert (equal "ggml" (gethash "renderer" body)))
        (assert (equal "json" (gethash "parser" body)))
        (assert (eq json-kit:+json-false+ (gethash "stream" body))))))

  (it "distinguishes omitted message fields from supplied JSON null"
    (let ((message (make-message
                    "user" "hello"
                    :name json-kit:+json-null+)))
      (multiple-value-bind (name present-p) (gethash "name" message)
        (assert present-p)
        (assert (eq json-kit:+json-null+ name)))
      (multiple-value-bind (thinking present-p) (gethash "thinking" message)
        (declare (ignore thinking))
        (assert (not present-p))))))

(describe "continuation-passing JSON API"
  (it "dispatches successful values and API errors to continuations"
    (let ((success-value nil)
          (success-response nil)
          (failure-condition nil))
      (call-with-json
       (queued-client (response-with-text "{\"ok\":true}"))
       :get "/version"
       (lambda (value response)
         (setf success-value (gethash "ok" value)
               success-response response))
       (lambda (condition)
         (setf failure-condition condition)))
      (unwind-protect
           (with-soft-assertions
             (expect success-value :to-be t)
             (expect failure-condition :to-be nil))
        (close-http-response success-response)))
    (let ((failure-condition nil))
      (call-with-json
       (queued-client
        (response-with-text "{\"error\":\"missing\"}" :status 404))
       :get "/version"
       (lambda (&rest values)
         (declare (ignore values))
         (error "The success continuation must not run."))
       (lambda (condition)
         (setf failure-condition condition)))
      (expect failure-condition :to-satisfy
               (lambda (condition)
                 (and (typep condition 'ollama-api-error)
                      (equal "missing" (ollama-error-message condition))))))))

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

(describe "Ollama web API contracts"
  (it "posts search and fetch requests with the documented payloads"
    (let* ((captured (list nil))
          (client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore timeout))
               (setf (car captured) request)
               (response-with-text "{}")))))
      (let ((value (web-search client "Common Lisp" :max-results 3)))
        (assert (http-request-p (car captured)))
        (let ((body (request-json-object (car captured))))
          (assert (hash-table-p value))
          (assert (eq :post (http-request-method (car captured))))
          (assert (search "/api/web_search"
                         (http-request-url (car captured))))
          (assert (equal "Common Lisp" (gethash "query" body)))
          (assert (= 3 (gethash "max_results" body)))))
      (let ((value (web-fetch client "https://example.com/docs")))
        (assert (http-request-p (car captured)))
        (let ((body (request-json-object (car captured))))
          (assert (hash-table-p value))
          (assert (eq :post (http-request-method (car captured))))
          (assert (search "/api/web_fetch"
                         (http-request-url (car captured))))
          (assert (equal "https://example.com/docs"
                         (gethash "url" body)))))))

  (it "rejects invalid web search and fetch arguments"
    (let ((client
            (client-with-request-function
             (lambda (request &key timeout)
               (declare (ignore request timeout))
               (response-with-text "{}")))))
      (dolist (thunk
                (list
                 (lambda () (web-search client nil))
                 (lambda () (web-search client "query" :max-results 0))
                 (lambda () (web-search client "query" :max-results 11))
                 (lambda () (web-search client "query" :max-results "3"))
                 (lambda () (web-fetch client nil))))
        (handler-case
            (progn (funcall thunk) (assert nil))
          (ollama-argument-error () t))))))

(describe "stream lifecycle and error contracts"
  (it "runs an HTTP close callback at most once"
    (let ((close-count 0)
          (stream nil))
      (setf stream
            (open-ollama-stream
             (client-with-request-function
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (make-http-response
                 :status 200
                 :headers '(("content-type" . "application/x-ndjson"))
                 :stream (make-string-input-stream "")
                 :close-function (lambda () (incf close-count)))))
             :post "/chat"))
      (stream-close stream)
      (stream-close stream)
      (assert (stream-closed-p stream))
      (assert (= 1 close-count))))

  (it "raises a structured condition for a streamed API error"
    (let ((stream
            (open-ollama-stream
             (queued-client
              (response-with-text
               (format nil "{\"error\":\"model failed\"}~%")))
             :post "/chat"))
          (condition nil))
      (handler-case (stream-next stream)
        (ollama-stream-error (caught)
          (setf condition caught)))
      (assert condition)
      (assert (equal "model failed" (ollama-error-message condition)))
      (assert (= 1 (ollama-stream-error-line condition)))
      (assert (hash-table-p (ollama-stream-error-event condition)))
      (assert (stream-closed-p stream))))

  (it "preserves streamed HTTP error bodies and releases the response"
    (let ((close-count 0)
          (condition nil))
      (handler-case
          (open-ollama-stream
           (client-with-request-function
            (lambda (request &key timeout)
              (declare (ignore request timeout))
              (make-http-response
               :status 404
               :headers '(("content-type" . "application/x-ndjson"))
               :stream (make-string-input-stream
                        (format nil "{\"error\":\"model missing\"}~%"))
               :close-function (lambda () (incf close-count)))))
           :post "/chat")
        (ollama-api-error (caught)
          (setf condition caught)))
      (assert condition)
      (assert (search "model missing" (ollama-http-error-body condition)))
      (assert (hash-table-p (ollama-api-error-data condition)))
      (assert (= 1 close-count))))

  (it "releases an unexpected streaming response from a JSON request"
    (let ((close-count 0)
          (condition nil))
      (handler-case
          (request-json
           (client-with-request-function
            (lambda (request &key timeout)
              (declare (ignore request timeout))
              (make-http-response
               :status 200
               :stream (make-string-input-stream "{}")
               :close-function (lambda () (incf close-count)))))
           :get "/version")
        (ollama-protocol-error (caught)
          (setf condition caught)))
      (assert condition)
      (assert (= 1 close-count)))))
