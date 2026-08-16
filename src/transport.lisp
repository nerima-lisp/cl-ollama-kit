(defun %validate-request-body (body-supplied-p body)
  (when
      (and body-supplied-p
           body
           (not (or (stringp body) (%octet-vector-p body))))
    (error 'ollama-argument-error
           :message
           "HTTP request body must be a string or octet vector."
           :detail
           (type-of body)))
  body)

(defun %validate-request-body-length (client body-supplied-p body)
  (when body-supplied-p
    (let ((body-length (%request-body-length body)))
      (when (and body-length (> body-length (client-max-request-length client)))
        (error 'ollama-argument-error
               :message
               "HTTP request body exceeds the configured limit."
               :detail
               (client-max-request-length client)))))
  body)

(defun %request-content-type-headers (headers body-supplied-p content-type)
  (cond
    ((and body-supplied-p (eq content-type +json-unspecified+))
     (%ensure-header headers "Content-Type" "application/json; charset=utf-8"))
    ((and body-supplied-p content-type)
     (%force-header headers "Content-Type" content-type))
    (t headers)))

(defun %request-accept-headers (headers stream-p accept)
  (cond
    ((eq accept +json-unspecified+)
     (%ensure-header headers
                     "Accept"
                     (if stream-p
                         "application/x-ndjson"
                         "application/json")))
    (accept (%force-header headers "Accept" accept))
    (t headers)))

(defun %request-headers (client body-supplied-p
                                stream-p
                                headers
                                content-type
                                accept)
  (let* ((request-headers (%normalize-headers headers))
         (authorization-override-p
          (%header-present-p "Authorization" request-headers))
         (all-headers (append request-headers (client-headers client)))
         (all-headers
          (%request-content-type-headers all-headers
                                         body-supplied-p
                                         content-type))
         (all-headers (%request-accept-headers all-headers stream-p accept)))
    (values all-headers authorization-override-p)))

(defun %request-timeout (client timeout)
  (if (eq timeout +timeout-unspecified+)
      (client-timeout client)
      (progn
        (%validate-timeout timeout)
        timeout)))

(defun %request-option-values (options)
  (values (%keyword-option-supplied-p options :body)
          (%keyword-option options :body nil)
          (%keyword-option options :stream-p nil)
          (%keyword-option options :timeout +timeout-unspecified+)
          (%keyword-option options :headers nil)
          (%keyword-option options :content-type +json-unspecified+)
          (%keyword-option options :accept +json-unspecified+)))

(defun %send-network-request (client request timeout)
  (handler-case (cl-boundary-kit:network-boundary-request
                 (client-network-boundary client)
                 request
                 :timeout
                 timeout)
    (ollama-error (condition)
      (error condition))
    (error (condition)
      (error 'ollama-transport-error
             :message
             "The network boundary failed while sending a request."
             :cause
             condition))))

(defun %close-response-safely (response)
  (when (http-response-p response)
    ;; Closing is cleanup after the response has already been handled.  A
    ;; close failure must not replace the primary result or condition.
    (handler-case
        (%close-http-response response)
      (error (condition)
        (warn "HTTP response cleanup failed after the primary result was settled: ~A"
              condition))))
  response)

(defun %make-network-request (client method
                                     path
                                     body-supplied-p
                                     body
                                     stream-p
                                     headers
                                     content-type
                                     accept)
  (multiple-value-bind (all-headers authorization-override-p)
      (%request-headers client
                        body-supplied-p
                        stream-p
                        headers
                        content-type
                        accept)
    (let ((request
           (make-http-request :method
                              method
                              :url
                              (%join-url (client-base-url client) path)
                              :headers
                              all-headers
                              :body
                              (when body-supplied-p
                                body)
                              :stream-p
                              stream-p)))
      (when (and (client-api-key-p client) authorization-override-p)
        (error 'ollama-argument-error
               :message
               "Do not override a configured API-KEY per request."))
      request)))

(defun perform-request (client method path &rest options)
  "Send a raw HTTP request through CLIENT's network boundary.

BODY is a string or octet vector when supplied.  The returned value is an
OLLAMA-KIT:HTTP-RESPONSE.  JSON-aware callers should use REQUEST-JSON.

When CONTENT-TYPE or ACCEPT is explicitly supplied, its value replaces any
header with the same name.  NIL suppresses the default header."
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options options
                             '(:body :stream-p
                                     :timeout
                                     :headers
                                     :content-type
                                     :accept))
  (multiple-value-bind (body-supplied-p body
                                        stream-p
                                        timeout
                                        headers
                                        content-type
                                        accept) (%request-option-values options)
    (%validate-boolean stream-p "STREAM-P")
    (%validate-request-body body-supplied-p body)
    (%validate-request-body-length client body-supplied-p body)
    (%send-network-request client
                           (%make-network-request client
                                                  method
                                                  path
                                                  body-supplied-p
                                                  body
                                                  stream-p
                                                  headers
                                                  content-type
                                                  accept)
                           (%request-timeout client timeout))))

(defun %perform-request-with-optional-body (client method
                                                   path
                                                   body-supplied-p
                                                   body
                                                   &rest
                                                   options)
  "Call PERFORM-REQUEST while preserving omitted versus explicit NIL BODY."
  (apply #'perform-request
         client
         method
         path
         (append
          (when body-supplied-p
            (list :body body))
          options)))
