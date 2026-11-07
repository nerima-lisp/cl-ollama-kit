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
  (let* ((api-key (%keyword-option options :api-key nil))
         (client-options (copy-list options))
         (base-url
          (%keyword-option options :base-url +anthropic-default-base-url+))
         (headers
          (%anthropic-client-headers (%keyword-option options :headers nil)
                                     api-key)))
    (setf (getf client-options :base-url) base-url)
    (when (or api-key (%keyword-option-supplied-p options :headers))
      (setf (getf client-options :headers) headers))
    (remf client-options :api-key)
    (apply #'make-client client-options)))

(defun %anthropic-stream-body (body)
  (%json-object-with-field body "stream" t))

(define-json-endpoint %request-json-value anthropic-messages
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
                                  (client body event-function
                                          &key
                                          (timeout +timeout-unspecified+)
                                          (response-timeout +timeout-unspecified+)
                                          (idle-timeout +timeout-unspecified+)
                                          headers
                                          cancel-token)
                                  :post
                                  "/messages"
                                  :documentation
                                  "Stream an Anthropic-compatible Messages SSE response through EVENT-FUNCTION.")
