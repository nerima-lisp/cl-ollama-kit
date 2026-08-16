(defun make-openai-client (&rest options)
  "Create a client for Ollama's OpenAI-compatible `/v1` API."
  (%validate-keyword-options options +client-option-keys+)
  (make-client :base-url
               (%keyword-option options :base-url +openai-default-base-url+)
               :network-boundary
               (%keyword-option options :network-boundary nil)
               :headers
               (%keyword-option options :headers nil)
               :api-key
               (%keyword-option options :api-key nil)
               :timeout
               (%keyword-option options :timeout nil)
               :max-input-length
               (%keyword-option options :max-input-length 16777216)
               :max-request-length
               (%keyword-option options :max-request-length 16777216)
               :allow-insecure-http
               (%keyword-option options :allow-insecure-http nil)))

(defun %openai-stream-body (body)
  (%json-object-with-field body "stream" t))

(define-openai-json-endpoint openai-models
                             (client &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :get
                             "/models"
                             :documentation
                             "List models through `/v1/models`.")

(defun %openai-model-has-control-p (model)
  (some
   (lambda (character)
     (or (< (char-code character) 33) (= (char-code character) 127)))
   model))

(defun %openai-model-has-path-separator-p (model)
  (or (find #\/ model)
      (find #\\ model)
      (string= model ".")
      (string= model "..")))

(defun %validate-openai-model-name (model)
  (unless (and (stringp model) (plusp (length model)))
    (error 'ollama-argument-error
           :message
           "OpenAI model names must be non-empty strings."))
  (when (%openai-model-has-control-p model)
    (error 'ollama-argument-error
           :message
           "OpenAI model names must not contain controls or whitespace."))
  (when (or (find #\? model) (find #\# model) (find #\% model))
    (error 'ollama-argument-error
           :message
           "OpenAI model names must not contain URL delimiters."))
  (when (%openai-model-has-path-separator-p model)
    (error 'ollama-argument-error
           :message
           "OpenAI model names must be a single URL path segment."))
  model)

(defun openai-model (client model &key (timeout +timeout-unspecified+) headers)
  "Return one model description through `/v1/models/{model}`."
  (%validate-openai-model-name model)
  (%request-json-value client
                       :get
                       (format nil "/models/~A" model)
                       :timeout
                       timeout
                       :headers
                       headers))

(define-openai-json-endpoint openai-chat-completions
                             (client body
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/chat/completions"
                             :body-form
                             body
                             :documentation
                             "Create a chat completion using a JSON object BODY.")

(define-openai-stream-endpoint openai-chat-completions-stream
                               (client body
                                       &key
                                       (timeout +timeout-unspecified+)
                                       headers)
                               :post
                               "/chat/completions"
                               :documentation
                               "Stream a chat completion using an OpenAI-compatible request BODY.")

(define-openai-json-endpoint openai-completions
                             (client body
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/completions"
                             :body-form
                             body
                             :documentation
                             "Create a text completion using an OpenAI-compatible request BODY.")

(define-openai-stream-endpoint openai-completions-stream
                               (client body
                                       &key
                                       (timeout +timeout-unspecified+)
                                       headers)
                               :post
                               "/completions"
                               :documentation
                               "Stream a text completion using an OpenAI-compatible request BODY.")

(define-openai-json-endpoint openai-embeddings
                             (client body
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/embeddings"
                             :body-form
                             body
                             :documentation
                             "Create embeddings using an OpenAI-compatible request BODY.")

(define-openai-json-endpoint openai-responses
                             (client body
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/responses"
                             :body-form
                             body
                             :documentation
                             "Create a response through Ollama's experimental `/v1/responses` API.")

(define-openai-stream-endpoint openai-responses-stream
                               (client body
                                       &key
                                       (timeout +timeout-unspecified+)
                                       headers)
                               :post
                               "/responses"
                               :documentation
                               "Stream a response through Ollama's experimental `/v1/responses` API.")

(define-openai-json-endpoint openai-images
                             (client body
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/images/generations"
                             :body-form
                             body
                             :documentation
                             "Generate images through Ollama's experimental `/v1/images/generations` API.")
