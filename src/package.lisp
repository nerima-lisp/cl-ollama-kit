(defpackage #:ollama-kit
  (:use #:cl)
  (:import-from #:http-message-kit
                #:make-http-request #:http-request-p
                #:make-http-response #:http-response-p
                #:http-response-body #:http-response-headers
                #:http-response-status #:http-response-protocol-version
                #:http-response-reason #:http-response-trailers)
  (:export
   ;; Client and transport boundary.
   #:+default-base-url+
   #:+anthropic-default-base-url+
   #:make-client #:client-p #:client-base-url #:client-http-client
   #:client-headers #:client-timeout #:client-response-timeout
   #:client-idle-timeout #:client-max-input-length
   #:client-max-request-length #:client-api-key-p
   #:client-allow-insecure-http #:close-client
   #:perform-request #:request-json #:request-raw
   #:with-ollama-continuations
   #:call-with-json
   ;; Conditions.
   #:ollama-error #:ollama-error-message
   #:ollama-argument-error #:ollama-argument-error-detail
   #:ollama-transport-error #:ollama-transport-error-cause
   #:ollama-cancelled #:ollama-response-timeout #:ollama-idle-timeout
   #:ollama-protocol-error #:ollama-protocol-error-detail
   #:ollama-http-error #:ollama-http-error-status
   #:ollama-http-error-response #:ollama-http-error-body
   #:ollama-api-error #:ollama-api-error-data

   ;; JSON and message helpers.
   #:+json-unspecified+ #:make-message #:json-object

   ;; Streaming callback errors.
   #:ollama-stream-error #:ollama-stream-error-event
   #:ollama-stream-error-line
   ;; Native API.
   #:generate #:generate-stream
   #:chat #:chat-stream
   #:embed
   #:list-models #:list-running-models #:show-model
   #:create-model #:create-model-stream
   #:copy-model #:delete-model
   #:pull-model #:pull-model-stream
   #:push-model #:push-model-stream
   #:blob-exists-p #:push-blob
   #:web-search #:web-fetch
   #:version

   ;; OpenAI-compatible API.
   #:make-openai-client
   #:openai-model #:openai-models #:openai-chat-completions
   #:openai-chat-completions-stream #:openai-completions
   #:openai-completions-stream #:openai-embeddings
   #:openai-responses #:openai-responses-stream #:openai-images

   ;; Anthropic-compatible API.
   #:make-anthropic-client #:anthropic-messages
   #:anthropic-messages-stream #:call-with-ollama-stream #:call-with-openai-stream #:call-with-anthropic-stream))

