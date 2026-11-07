(in-package #:ollama-kit/test)

(progn
  (defun %call-with-openai-loopback-response (payload content-type function)
    (let* ((server
             (make-loopback-http-server
              :headers
              (list (http-message-kit:make-http-header "content-type" content-type))
              :body
              (cl-codec-kit:string-to-octets payload :encoding :utf-8)
              :keep-alive-p nil))
           (client
             (make-openai-client
              :base-url
              (concatenate 'string
                           (loopback-http-server-url server)
                           "/v1"))))
      (unwind-protect
           (funcall function client server)
        (close-client client))))

  (defun %assert-openai-loopback-request (server method path)
    (let ((request (loopback-http-server-request server)))
      (assert (http-message-kit:http-request-p request))
      (assert (string-equal (symbol-name method)
                            (http-message-kit:http-request-method request)))
      (assert
       (string= (concatenate 'string "/v1" path)
                (http-message-kit:http-request-target request)))
      request))

  (defun %openai-request-header-content (request name)
    (loop for header in (http-message-kit:http-request-headers request)
          when (string-equal name (http-message-kit:http-header-name header))
            return (http-message-kit:http-header-content header)))

  (defun %openai-json-object (json)
    (json-kit:parse json :object-type :hash-table :array-type :vector))

  (defun %openai-first-model-id (value)
    (gethash "id" (aref (gethash "data" value) 0)))

  (defun %openai-single-model-id (value)
    (gethash "id" value))

  (defun %openai-assert-chat-body (body)
  (let* ((messages (gethash "messages" body))
         (tools (gethash "tools" body))
         (tool-function (gethash "function" (aref tools 0))))
    (assert (equal "fixture-model" (gethash "model" body)))
    (assert (= 1 (length messages)))
    (assert (equal "user" (gethash "role" (aref messages 0))))
    (assert (equal "Hello" (gethash "content" (aref messages 0))))
    (assert (equal "lookup" (gethash "name" tool-function)))
    (assert (equal "object"
                   (gethash "type" (gethash "parameters" tool-function))))
    (assert (equal "json_object"
                   (gethash "type" (gethash "response_format" body))))
    (multiple-value-bind (stream present-p) (gethash "stream" body)
      (when present-p
        (assert (eq t stream))))))

  (defun %openai-assert-completion-body (body)
  (assert (equal "fixture-model" (gethash "model" body)))
  (assert (equal "Hello" (gethash "prompt" body)))
  (multiple-value-bind (stream present-p) (gethash "stream" body)
    (when present-p
      (assert (eq t stream)))))

  (defun %openai-chat-content (value)
    (let* ((choice (aref (gethash "choices" value) 0))
           (message (gethash "message" choice)))
      (gethash "content" message)))

  (defun %openai-completion-text (value)
    (gethash "text" (aref (gethash "choices" value) 0)))

  (defun %openai-chat-event-content (event)
    (gethash "content"
             (gethash "delta"
                      (aref (gethash "choices" event) 0))))

  (defun %openai-completion-event-text (event)
    (gethash "text" (aref (gethash "choices" event) 0)))

  (describe "OpenAI-compatible API contracts"
    (it-each
     ((openai-models
       "/models"
       nil
       "{\"object\":\"list\",\"data\":[{\"id\":\"fixture-model\",\"object\":\"model\",\"owned_by\":\"ollama\"}]}"
       %openai-first-model-id
       "fixture-model")
      (openai-model
       "/models/fixture-model"
       "fixture-model"
       "{\"id\":\"fixture-model\",\"object\":\"model\",\"owned_by\":\"ollama\"}"
       %openai-single-model-id
       "fixture-model"))
     "reads model ids from ~A"
     (operation path model response-body response-reader expected-id)
     (%call-with-openai-loopback-response
      response-body
      "application/json"
      (lambda (client server)
        (let* ((value
                 (if model
                     (funcall operation client model)
                     (funcall operation client)))
               (request
                 (%assert-openai-loopback-request server :get path)))
          (assert
           (let ((body (http-message-kit:http-request-body request)))
             (and (typep body '(vector (unsigned-byte 8)))
                  (zerop (length body)))))
          (assert (equal expected-id (funcall response-reader value)))))))

    (it-each
     ((openai-chat-completions
       "/chat/completions"
       "{\"model\":\"fixture-model\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"parameters\":{\"type\":\"object\"}}}],\"response_format\":{\"type\":\"json_object\"}}"
       "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"ok\\\":true}\"},\"finish_reason\":\"stop\"}]}"
       %openai-assert-chat-body
       %openai-chat-content
       "{\"ok\":true}")
      (openai-completions
       "/completions"
       "{\"model\":\"fixture-model\",\"prompt\":\"Hello\"}"
       "{\"id\":\"cmpl-1\",\"object\":\"text_completion\",\"choices\":[{\"text\":\"Hi\",\"index\":0,\"finish_reason\":\"stop\"}]}"
       %openai-assert-completion-body
       %openai-completion-text
       "Hi"))
     "sends and decodes the ~A response"
     (operation path request-body response-body request-checker response-reader expected-value)
     (%call-with-openai-loopback-response
      response-body
      "application/json"
      (lambda (client server)
        (let* ((body (%openai-json-object request-body))
               (value (funcall operation client body))
               (request (%assert-openai-loopback-request server :post path)))
          (funcall request-checker (request-json-object request))
          (assert (equal expected-value (funcall response-reader value)))))))

    (it-each
     ((openai-completions-stream
       "/completions"
       "{\"model\":\"fixture-model\",\"prompt\":\"Hello\"}"
       "data: {\"choices\":[{\"text\":\"Hi\"}]}~%~%data: [DONE]~%~%"
       %openai-assert-completion-body
       %openai-completion-event-text
       "Hi"
       nil)
      (openai-chat-completions-stream
       "/chat/completions"
       "{\"model\":\"fixture-model\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"parameters\":{\"type\":\"object\"}}}],\"response_format\":{\"type\":\"json_object\"}}"
       "event: message~%data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}~%~%data: [DONE]~%~%"
       %openai-assert-chat-body
       %openai-chat-event-content
       "Hello"
       (("Accept" . "text/event-stream"))))
     "sends the ~A request body and delivers its callback event"
     (operation path request-body sse-payload request-checker event-reader expected-text request-headers)
     (%call-with-openai-loopback-response
      (format nil sse-payload)
      "text/event-stream"
      (lambda (client server)
        (let* ((body (%openai-json-object request-body))
               (events nil))
          (funcall operation
                   client
                   body
                   (lambda (event) (push event events))
                   :headers request-headers)
          (let* ((request (%assert-openai-loopback-request server :post path))
                 (sent (request-json-object request))
                 (event (first events)))
            (progn
              (funcall request-checker sent)
              (assert (eq t (gethash "stream" sent))))
            (when request-headers
              (assert
               (equal "text/event-stream"
                      (%openai-request-header-content request "Accept"))))
            (assert (= 1 (length events)))
            (assert (equal expected-text (funcall event-reader event))))))))

    (it "sends embeddings and decodes the returned vector"
      (%call-with-openai-loopback-response
       "{\"object\":\"list\",\"data\":[{\"object\":\"embedding\",\"index\":0,\"embedding\":[0.1,0.2]}],\"model\":\"fixture-model\",\"usage\":{\"prompt_tokens\":2,\"total_tokens\":2}}"
       "application/json"
       (lambda (client server)
         (let* ((body
                  (json-object "model"
                               "fixture-model"
                               "input"
                               #("Hello" "world")
                               "encoding_format"
                               "float"))
                (value (openai-embeddings client body))
                (request
                  (%assert-openai-loopback-request server :post "/embeddings"))
                (sent (request-json-object request))
                (data (gethash "data" value))
                (embedding (gethash "embedding" (aref data 0))))
           (assert (equal "fixture-model" (gethash "model" sent)))
           (assert (equal "float" (gethash "encoding_format" sent)))
           (assert (equalp #("Hello" "world") (gethash "input" sent)))
           (assert (equal "fixture-model" (gethash "model" value)))
           (assert (< (abs (- 0.1 (aref embedding 0))) 0.000001))
           (assert (< (abs (- 0.2 (aref embedding 1))) 0.000001)))))

    (it "sends a response request and decodes output text"
      (%call-with-openai-loopback-response
       "{\"id\":\"resp_1\",\"object\":\"response\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}]}"
       "application/json"
       (lambda (client server)
         (let* ((body
                  (json-object "model"
                               "fixture-model"
                               "input"
                               "Hello"
                               "temperature"
                               0))
                (value (openai-responses client body))
                (request (%assert-openai-loopback-request server :post "/responses"))
                (sent (request-json-object request))
                (output (aref (gethash "output" value) 0))
                (content (aref (gethash "content" output) 0)))
           (assert (equal "fixture-model" (gethash "model" sent)))
           (assert (equal "Hello" (gethash "input" sent)))
           (assert (= 0 (gethash "temperature" sent)))
           (assert (equal "resp_1" (gethash "id" value)))
           (assert (equal "response" (gethash "object" value)))
           (assert (equal "completed" (gethash "status" value)))
           (assert (equal "output_text" (gethash "type" content)))
           (assert (equal "Hello" (gethash "text" content)))))))

    (it "delivers ordered response lifecycle events"
      (%call-with-openai-loopback-response
       (format nil
               "event: response.created~%data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"status\":\"in_progress\"}}~%~%event: response.completed~%data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\"}}~%~%data: [DONE]~%~%")
       "text/event-stream"
       (lambda (client server)
         (let ((events nil)
               (body (json-object "model" "fixture-model" "input" "Hello")))
           (openai-responses-stream
            client body (lambda (event) (push event events)))
           (let* ((request
                    (%assert-openai-loopback-request server :post "/responses"))
                  (sent (request-json-object request))
                  (ordered-events (nreverse events))
                  (created (first ordered-events))
                  (completed (second ordered-events)))
             (assert (equal "fixture-model" (gethash "model" sent)))
             (assert (equal "Hello" (gethash "input" sent)))
             (assert (eq t (gethash "stream" sent)))
             (assert (= 2 (length ordered-events)))
             (assert (equal "response.created" (gethash "type" created)))
             (assert
              (equal "resp_1" (gethash "id" (gethash "response" created))))
             (assert (equal "response.completed" (gethash "type" completed)))
             (assert
              (equal "completed"
                     (gethash "status" (gethash "response" completed))))))))))))

(it "supports experimental image generation with the documented fields"
  (%call-with-openai-loopback-response
   "{\"created\":1,\"data\":[{\"b64_json\":\"abc\"}]}"
   "application/json"
   (lambda (client server)
     (let* ((body
              (json-object "model"
                           "x/z-image-turbo"
                           "prompt"
                           "A cute robot learning to paint"
                           "size"
                           "1024x1024"
                           "response_format"
                           "b64_json"
                           "n"
                           1
                           "quality"
                           "standard"
                           "style"
                           "vivid"
                           "user"
                           "test-user"))
            (value (openai-images client body))
            (request
              (%assert-openai-loopback-request
               server :post "/images/generations"))
            (sent (request-json-object request))
            (data (gethash "data" value)))
       (assert (= 1 (gethash "created" value)))
       (assert (equal "x/z-image-turbo" (gethash "model" sent)))
       (assert
        (equal "A cute robot learning to paint" (gethash "prompt" sent)))
       (assert (equal "1024x1024" (gethash "size" sent)))
       (assert (equal "b64_json" (gethash "response_format" sent)))
       (assert (= 1 (gethash "n" sent)))
       (assert (equal "standard" (gethash "quality" sent)))
       (assert (equal "vivid" (gethash "style" sent)))
       (assert (equal "test-user" (gethash "user" sent)))
       (assert (equal "abc" (gethash "b64_json" (aref data 0))))))))
