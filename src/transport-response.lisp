(defun %parse-json-response (response client)
  (%ensure-success response client)
  (values
   (%parse-json-text
    (%response-body-string response (client-max-input-length client))
    (client-max-input-length client))
   response))

(defun request-json (client method path &rest options)
  "Send a JSON request and return parsed JSON as the first value.

The complete HTTP message response is returned as the second value. A
non-success status signals OLLAMA-HTTP-ERROR or OLLAMA-API-ERROR."
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options options '(:body :stream-p :timeout :headers))
  (let* ((body-supplied-p (%keyword-option-supplied-p options :body))
         (body (%keyword-option options :body nil))
         (encoded-body
          (when body-supplied-p
            (%encode-json body (client-max-request-length client))))
         (response
          (%perform-request-with-optional-body client
                                               method
                                               path
                                               body-supplied-p
                                               encoded-body
                                               :stream-p
                                               (%keyword-option options
                                                                :stream-p
                                                                nil)
                                               :timeout
                                               (%keyword-option options
                                                                :timeout
                                                                +timeout-unspecified+)
                                               :headers
                                               (%keyword-option options
                                                                :headers
                                                                nil))))
    (%parse-json-response response client)))

(defun %request-json-value (client method path &rest options)
  (nth-value 0 (apply #'request-json client method path options)))

(defun request-raw (client method path &rest options)
  "Send a request and return its successful HTTP message response.

BODY is passed through as text or octets."
  (unless (client-p client)
    (error 'ollama-argument-error :message "CLIENT must be an Ollama client."))
  (%validate-keyword-options options
                             '(:body :stream-p
                                     :timeout
                                     :headers
                                     :content-type
                                     :accept))
  (let* ((body-supplied-p (%keyword-option-supplied-p options :body))
         (body (%keyword-option options :body nil))
         (stream-p (%keyword-option options :stream-p nil))
         (timeout (%keyword-option options :timeout +timeout-unspecified+))
         (headers (%keyword-option options :headers nil))
         (content-type
          (%keyword-option options :content-type +json-unspecified+))
         (accept (%keyword-option options :accept +json-unspecified+))
         (response
          (%perform-request-with-optional-body client
                                               method
                                               path
                                               body-supplied-p
                                               body
                                               :stream-p
                                               stream-p
                                               :timeout
                                               timeout
                                               :headers
                                               headers
                                               :content-type
                                               content-type
                                               :accept
                                               accept)))
    (%ensure-success response client)
    response))
