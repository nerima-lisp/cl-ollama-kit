(in-package #:ollama-kit/test)

(describe "Anthropic compatibility API"
  (it "posts the Messages request and decodes a meaningful response"
    (let* ((response-body
             "{\"id\":\"msg_123\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello back\"}],\"model\":\"claude-test\",\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":2,\"output_tokens\":2}}")
           (server
             (make-loopback-http-server
              :headers
              (list (http-message-kit:make-http-header
                     "content-type"
                     "application/json"))
              :body
              (cl-codec-kit:string-to-octets response-body :encoding :utf-8)))
           (client
             (make-anthropic-client
              :base-url
              (concatenate 'string (loopback-http-server-url server) "/v1")
              :api-key "anthropic-test-key"
              :headers '(("anthropic-version" . "2023-06-01"))))
           (input-body
             (json-object "model" "model"
                          "max_tokens" 32
                          "messages"
                          (vector (make-message "user" "Hello.")))))
      (unwind-protect
           (let* ((value (anthropic-messages client input-body))
                  (request (loopback-http-server-request server))
                  (headers (http-message-kit:http-request-headers request))
                  (request-body (request-json-object request))
                  (messages (gethash "messages" request-body))
                  (message (and (vectorp messages)
                                (= 1 (length messages))
                                (aref messages 0)))
                  (content (and message (gethash "content" value))))
             (assert (http-message-kit:http-request-p request))
             (assert (string-equal
                      "POST"
                      (http-message-kit:http-request-method request)))
             (assert (equal "/v1/messages"
                            (http-message-kit:http-request-target request)))
             (assert (equal "anthropic-test-key"
                            (http-message-kit:http-header-value
                             headers "x-api-key")))
             (assert (equal "2023-06-01"
                            (http-message-kit:http-header-value
                             headers "anthropic-version")))
             (assert (null (http-message-kit:http-header-value
                            headers "authorization")))
             (assert (= 3 (hash-table-count request-body)))
             (assert (equal "model" (gethash "model" request-body)))
             (assert (= 32 (gethash "max_tokens" request-body)))
             (assert message)
             (assert (equal "user" (gethash "role" message)))
             (assert (equal "Hello." (gethash "content" message)))
             (assert (equal "msg_123" (gethash "id" value)))
             (assert (equal "message" (gethash "type" value)))
             (assert (equal "assistant" (gethash "role" value)))
             (assert (equal "claude-test" (gethash "model" value)))
             (assert (equal "end_turn" (gethash "stop_reason" value)))
             (assert (vectorp content))
             (assert (= 1 (length content)))
             (assert (equal "text" (gethash "type" (aref content 0))))
             (assert (equal "Hello back"
                            (gethash "text" (aref content 0)))))
        (close-client client))))
  (it "preserves a caller-provided X-API-KEY without an API key option"
    (let ((client
            (make-anthropic-client
             :headers '(("x-api-key" . "provided")))))
      (unwind-protect
           (assert
            (equal "provided"
                   (cdr (assoc "x-api-key"
                               (client-headers client)
                               :test #'string-equal))))
        (close-client client))))
  (it "leaves compatibility headers unset by default"
  (let ((client (make-anthropic-client)))
    (unwind-protect
         (assert (null (client-headers client)))
      (close-client client))))
  (it "forces streaming and delivers decoded Anthropic SSE events"
    (let* ((response-body
             (format nil
                     "event: message_start~%data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_stream\"}}~%~%event: content_block_delta~%data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello back\"}}~%~%data: [DONE]~%~%"))
           (server
             (make-loopback-http-server
              :headers
              (list (http-message-kit:make-http-header
                     "content-type"
                     "text/event-stream"))
              :body
              (cl-codec-kit:string-to-octets response-body :encoding :utf-8)))
           (client
             (make-anthropic-client
              :base-url
              (concatenate 'string (loopback-http-server-url server) "/v1")
              :api-key "anthropic-test-key"
              :headers '(("anthropic-version" . "2023-06-01"))))
           (input-body
             (json-object "model" "model"
                          "max_tokens" 32
                          "messages"
                          (vector (make-message "user" "Hello."))))
           (events nil))
      (unwind-protect
           (progn
             (anthropic-messages-stream
              client input-body
              (lambda (event) (push event events)))
             (setf events (nreverse events))
             (let* ((request (loopback-http-server-request server))
                    (request-body (request-json-object request))
                    (messages (gethash "messages" request-body))
                    (message (and (vectorp messages)
                                  (= 1 (length messages))
                                  (aref messages 0))))
               (assert (http-message-kit:http-request-p request))
               (assert (string-equal
                        "POST"
                        (http-message-kit:http-request-method request)))
               (assert (equal "/v1/messages"
                              (http-message-kit:http-request-target request)))
               (assert (= 4 (hash-table-count request-body)))
               (assert (equal "model" (gethash "model" request-body)))
               (assert (= 32 (gethash "max_tokens" request-body)))
               (assert (eq t (gethash "stream" request-body)))
               (assert message)
               (assert (equal "user" (gethash "role" message)))
               (assert (equal "Hello." (gethash "content" message)))
               (assert (= 2 (length events)))
               (assert (equal "message_start"
                              (gethash "type" (first events))))
               (assert (equal "msg_stream"
                              (gethash "id"
                                       (gethash "message"
                                                (first events)))))
               (assert (equal "content_block_delta"
                              (gethash "type" (second events))))
               (assert (equal "text_delta"
                              (gethash "type"
                                       (gethash "delta"
                                                (second events)))))
               (assert (equal "Hello back"
                              (gethash "text"
                                       (gethash "delta"
                                                (second events)))))))
        (close-client client)))))
