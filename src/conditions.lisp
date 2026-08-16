(define-condition ollama-error
  (error)
  ((message :initarg
            :message
            :reader
            ollama-error-message
            :documentation
            "A human-readable description of the client error."))
  (:documentation "Base condition for errors signalled by OLLAMA-KIT.")
  (:report
   (lambda (condition stream)
     (write-string (ollama-error-message condition) stream))))

(define-condition ollama-argument-error
  (ollama-error)
  ((detail :initarg
           :detail
           :initform
           nil
           :reader
           ollama-argument-error-detail
           :documentation
           "The argument or limit that caused the validation failure."))
  (:documentation "Signals an invalid client or API argument."))

(define-condition ollama-transport-error
  (ollama-error)
  ((cause :initarg
          :cause
          :reader
          ollama-transport-error-cause
          :documentation
          "The original condition signalled by the network boundary."))
  (:documentation "Signals a failure in the injected network transport."))

(define-condition ollama-protocol-error
  (ollama-error)
  ((detail :initarg
           :detail
           :reader
           ollama-protocol-error-detail
           :documentation
           "The response or stream detail that violated the protocol."))
  (:documentation "Signals an invalid response from a network boundary."))

(define-condition ollama-stream-error
  (ollama-protocol-error)
  ((event :initarg
          :event
          :reader
          ollama-stream-error-event
          :documentation
          "The decoded stream event containing the server error.")
   (line :initarg
         :line
         :reader
         ollama-stream-error-line
         :documentation
         "The one-based wire line at which the event was decoded."))
  (:documentation "Signals an error event received in a streaming response."))

(define-condition ollama-http-error
  (ollama-error)
  ((status :initarg
           :status
           :reader
           ollama-http-error-status
           :documentation
           "The HTTP status code returned by the server.")
   (response :initarg
             :response
             :reader
             ollama-http-error-response
             :documentation
             "The complete HTTP response.")
   (body :initarg
         :body
         :reader
         ollama-http-error-body
         :documentation
         "The decoded response body, when available."))
  (:documentation "Signals a non-successful HTTP status."))

(define-condition ollama-api-error
  (ollama-http-error)
  ((data :initarg
         :data
         :reader
         ollama-api-error-data
         :documentation
         "The parsed JSON error object, when available."))
  (:documentation "Signals an HTTP error with an Ollama JSON error payload."))
