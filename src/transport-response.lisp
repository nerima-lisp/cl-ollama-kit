(defun %parse-json-response (response client)
  (%ensure-success response client)
  (when (http-response-stream response)
    (error 'ollama-protocol-error
           :message
           "A streaming HTTP response was returned for a JSON request."
           :detail
           response))
  (values
   (%parse-json-text
    (%response-body-string response (client-max-input-length client))
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
    (handler-case (%parse-json-response response client)
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
    (unwind-protect value
      (%close-response-safely response))))

(defun request-raw (client method path &rest options)
  "Send a request and return its successful HTTP response without consuming it.

The caller owns the returned response and must eventually call
CLOSE-HTTP-RESPONSE.  BODY is passed through as text or octets."
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
    (handler-case (%ensure-success response client)
      (error (condition)
        (%close-response-safely response)
        (error condition)))
    response))
