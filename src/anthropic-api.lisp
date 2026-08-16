(defun %anthropic-client-headers (headers api-key)
  (%validate-api-key api-key)
  (let ((normalized (%normalize-headers headers)))
    (if api-key
        (%ensure-header normalized "x-api-key" api-key)
        normalized)))

(defun make-anthropic-client (&rest options)
  "Create a client for Ollama's Anthropic-compatible Messages API.

API-KEY is installed as X-API-KEY.  Additional compatibility headers, such
as ANTHROPIC-VERSION, can be supplied through HEADERS."
  (%validate-keyword-options options +client-option-keys+)
  (let ((api-key (%keyword-option options :api-key nil)))
    (make-client :base-url
                 (%keyword-option options
                                  :base-url
                                  +anthropic-default-base-url+)
                 :network-boundary
                 (%keyword-option options :network-boundary nil)
                 :headers
                 (%anthropic-client-headers
                  (%keyword-option options :headers nil)
                  api-key)
                 :api-key
                 nil
                 :timeout
                 (%keyword-option options :timeout nil)
                 :max-input-length
                 (%keyword-option options :max-input-length 16777216)
                 :max-request-length
                 (%keyword-option options :max-request-length 16777216)
                 :allow-insecure-http
                 (%keyword-option options :allow-insecure-http nil))))

(defun %anthropic-stream-body (body)
  (%json-object-with-field body "stream" t))

(define-anthropic-json-endpoint anthropic-messages
                                (client body
                                        &key
                                        (timeout +timeout-unspecified+)
                                        headers)
                                :post
                                "/messages"
                                :body-form
                                body
                                :documentation
                                "Create an Anthropic-compatible Messages response from a JSON BODY.")

(define-anthropic-stream-endpoint anthropic-messages-stream
                                  (client body
                                          &key
                                          (timeout +timeout-unspecified+)
                                          headers)
                                  :post
                                  "/messages"
                                  :documentation
                                  "Open an Anthropic-compatible Messages SSE response stream.")
