(defun %validate-request-body (body-supplied-p body)
  (when (and body-supplied-p
             body
             (not (or (stringp body)
                      (%octet-vector-p body))))
    (error 'ollama-argument-error
           :message "HTTP request body must be a string or octet vector."
           :detail (type-of body)))
  body)

(defun %validate-request-body-length (client body-supplied-p body)
  (when body-supplied-p
    (let ((body-length (%request-body-length body)))
      (when (and body-length
                 (> body-length (client-max-request-length client)))
        (error 'ollama-argument-error
               :message "HTTP request body exceeds the configured limit."
                :detail (client-max-request-length client)))))
  body)

(defun %request-content-type-headers (headers body-supplied-p content-type)
  (cond
    ((and body-supplied-p
          (eq content-type +json-unspecified+))
     (%ensure-header headers
                     "Content-Type"
                     "application/json; charset=utf-8"))
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

(defun %request-headers (client body-supplied-p stream-p headers
                         content-type accept)
  (let* ((request-headers (%normalize-headers headers))
         (authorization-override-p
           (%header-present-p "Authorization" request-headers))
         (all-headers (append request-headers (client-headers client)))
         (all-headers (%request-content-type-headers
                       all-headers body-supplied-p content-type))
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
  (handler-case
      (cl-boundary-kit:network-boundary-request
       (client-network-boundary client)
       request
       :timeout timeout)
    (ollama-error (condition)
      (error condition))
    (error (condition)
      (error 'ollama-transport-error
             :message "The network boundary failed while sending a request."
             :cause condition))))

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

(defun %make-network-request (client method path body-supplied-p body stream-p
                              headers content-type accept)
  (multiple-value-bind (all-headers authorization-override-p)
      (%request-headers client body-supplied-p stream-p headers
                        content-type accept)
    (let ((request
            (make-http-request
             :method method
             :url (%join-url (client-base-url client) path)
             :headers all-headers
             :body (when body-supplied-p body)
             :stream-p stream-p)))
      (when (and (client-api-key-p client) authorization-override-p)
        (error 'ollama-argument-error
               :message "Do not override a configured API-KEY per request."))
      request)))

(defun perform-request (client method path &rest options)
  "Send a raw HTTP request through CLIENT's network boundary.

BODY is a string or octet vector when supplied.  The returned value is an
OLLAMA-KIT:HTTP-RESPONSE.  JSON-aware callers should use REQUEST-JSON.

When CONTENT-TYPE or ACCEPT is explicitly supplied, its value replaces any
header with the same name.  NIL suppresses the default header."
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options
   options '(:body :stream-p :timeout :headers :content-type :accept))
  (multiple-value-bind (body-supplied-p body stream-p timeout headers
                        content-type accept)
      (%request-option-values options)
    (%validate-boolean stream-p "STREAM-P")
    (%validate-request-body body-supplied-p body)
    (%validate-request-body-length client body-supplied-p body)
    (%send-network-request
     client
     (%make-network-request client method path body-supplied-p body stream-p
                            headers content-type accept)
     (%request-timeout client timeout))))

(defun %perform-request-with-optional-body
    (client method path body-supplied-p body &rest options)
  "Call PERFORM-REQUEST while preserving omitted versus explicit NIL BODY."
  (apply #'perform-request
         client method path
         (append (when body-supplied-p (list :body body)) options)))

(defun %parse-json-response (response client)
  (%ensure-success response client)
  (when (http-response-stream response)
    (error 'ollama-protocol-error
           :message "A streaming HTTP response was returned for a JSON request."
           :detail response))
  (values (%parse-json-text (%response-body-string
                             response
                             (client-max-input-length client))
          (client-max-input-length client))
          response))

(defun request-json (client method path &rest options)
  "Send a JSON request and return parsed JSON as the first value.

  The complete HTTP response is returned as the second value.  A non-success
  status signals OLLAMA-HTTP-ERROR or OLLAMA-API-ERROR." 
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options options '(:body :stream-p :timeout :headers))
  (let* ((body-supplied-p (%keyword-option-supplied-p options :body))
         (body (%keyword-option options :body nil))
         (encoded-body (when body-supplied-p
                         (%encode-json body
                                       (client-max-request-length client))))
         (response (%perform-request-with-optional-body
                    client method path body-supplied-p encoded-body
                    :stream-p (%keyword-option options :stream-p nil)
                    :timeout (%keyword-option options :timeout
                                              +timeout-unspecified+)
                    :headers (%keyword-option options :headers nil))))
    (handler-case
        (%parse-json-response response client)
      (error (condition)
             (%close-response-safely response)
             (error condition)))))

(defun %request-json-value (client method path &rest options)
  "Return parsed JSON and close the successful response before returning.

High-level JSON endpoint helpers do not expose the transport response, so
they must settle its ownership here.  REQUEST-JSON remains available when a
caller needs both the decoded value and the response object."
  (multiple-value-bind (value response)
      (apply #'request-json client method path options)
    (unwind-protect
         value
      (%close-response-safely response))))

(defun request-raw (client method path &rest options)
  "Send a request and return its successful HTTP response without consuming it.

The caller owns the returned response and must eventually call
CLOSE-HTTP-RESPONSE.  BODY is passed through as text or octets." 
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options
   options '(:body :stream-p :timeout :headers :content-type :accept))
  (let* ((body-supplied-p (%keyword-option-supplied-p options :body))
         (body (%keyword-option options :body nil))
         (stream-p (%keyword-option options :stream-p nil))
         (timeout (%keyword-option options :timeout
                                   +timeout-unspecified+))
         (headers (%keyword-option options :headers nil))
         (content-type
          (%keyword-option options :content-type +json-unspecified+))
         (accept (%keyword-option options :accept +json-unspecified+))
         (response (%perform-request-with-optional-body
                    client method path body-supplied-p body
                    :stream-p stream-p
                    :timeout timeout
                    :headers headers
                    :content-type content-type
                    :accept accept)))
    (handler-case
        (%ensure-success response client)
      (error (condition)
             (%close-response-safely response)
             (error condition)))
    response))

(defmacro with-http-response ((response-form) &body body)
  "Evaluate RESPONSE-FORM and close its HTTP response after BODY.

The response is closed even when BODY signals.  Cleanup failures are reported
as warnings so that they do not replace the primary result or condition."
  (let ((response (gensym "RESPONSE-")))
    `(let ((,response ,response-form))
       (unwind-protect
            (progn ,@body)
         (%close-response-safely ,response)))))

(defmacro with-json-response ((value-var response-var request-form) &body body)
  "Bind parsed JSON and its response, then close the response after BODY.

REQUEST-FORM must return parsed JSON as its first value and an HTTP response as
its second value, as REQUEST-JSON does."
  (let ((value (gensym "VALUE-"))
        (response (gensym "RESPONSE-")))
    `(multiple-value-bind (,value ,response) ,request-form
       (let ((,value-var ,value)
             (,response-var ,response))
         (unwind-protect
              (progn ,@body)
           (%close-response-safely ,response-var))))))
