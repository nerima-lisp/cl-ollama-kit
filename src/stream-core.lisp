#.(progn (in-package :ollama-kit) nil)

(defun %close-response (response)
  (%close-response-safely response))

(defun %open-event-stream (client method
                                  path
                                  &key
                                  body
                                  body-supplied-p
                                  timeout
                                  headers
                                  wire-format
                                  accept)
  (let* ((encoded-body
          (when body-supplied-p
            (%encode-json body (client-max-request-length client))))
         (response
          (%perform-request-with-optional-body client
                                               method
                                               path
                                               body-supplied-p
                                               encoded-body
                                               :stream-p
                                               t
                                               :timeout
                                               timeout
                                               :headers
                                               headers
                                               :accept
                                               accept)))
    (handler-case (%ensure-success response client)
      (ollama-error (condition)
        (%close-response response)
        (error condition)))
    (handler-case (%make-ollama-stream :stream
                                       (%response-input-stream response
                                                               (client-max-input-length
                                                                client))
                                       :response
                                       response
                                       :close-function
                                       (http-response-close-function response)
                                       :wire-format
                                       wire-format
                                       :max-line-length
                                       (client-max-input-length client))
      (error (condition)
        (%close-response response)
        (error condition)))))

(defun open-ollama-stream (client method path &rest options)
  "Open a native Ollama NDJSON response stream.

BODY is encoded as JSON when supplied.  The returned stream owns the response
stream and must eventually be closed with STREAM-CLOSE."
  (%validate-keyword-options options '(:body :timeout :headers))
  (%open-event-stream client
                      method
                      path
                      :body
                      (%keyword-option options :body nil)
                      :body-supplied-p
                      (%keyword-option-supplied-p options :body)
                      :timeout
                      (%keyword-option options :timeout +timeout-unspecified+)
                      :headers
                      (%keyword-option options :headers nil)
                      :wire-format
                      :ndjson
                      :accept
                      "application/x-ndjson"))

(defun open-openai-stream (client method path &rest options)
  "Open an OpenAI-compatible Server-Sent Events response stream."
  (%validate-keyword-options options '(:body :timeout :headers))
  (%open-event-stream client
                      method
                      path
                      :body
                      (%keyword-option options :body nil)
                      :body-supplied-p
                      (%keyword-option-supplied-p options :body)
                      :timeout
                      (%keyword-option options :timeout +timeout-unspecified+)
                      :headers
                      (%keyword-option options :headers nil)
                      :wire-format
                      :sse
                      :accept
                      "text/event-stream"))

(defun open-anthropic-stream (client method path &rest options)
  "Open an Anthropic-compatible Server-Sent Events response stream."
  (apply #'open-openai-stream client method path options))

(defun stream-closed-p (stream)
  (ollama-stream-closed-p stream))

(defun stream-close (stream)
  "Close STREAM.  Closing is idempotent and releases the HTTP response stream."
  (unless (ollama-stream-p stream)
    (error 'ollama-argument-error
           :message
           "STREAM-CLOSE requires an Ollama stream."))
  (unless (stream-closed-p stream)
    (setf (ollama-stream-closed-p stream) t)
    (let ((response (ollama-stream-response stream))
          (underlying (ollama-stream-stream stream))
          (close-function (ollama-stream-close-function stream)))
      (setf (ollama-stream-stream stream) nil
            (ollama-stream-response stream) nil
            (ollama-stream-close-function stream) nil)
      (if (http-response-p response)
          (%close-http-response response)
          (%close-owned-resources underlying close-function))))
  t)
