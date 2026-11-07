#.(progn (in-package :ollama-kit) nil)

(defun %decode-utf8 (octets)
  (handler-case (multiple-value-bind (text remainder)
                    (cl-codec-kit:decode-prefix octets :encoding :utf-8)
                  (if (zerop (length remainder))
                      text
                      (error 'ollama-protocol-error
                             :message
                             "HTTP response body ends with an incomplete UTF-8 sequence."
                             :detail
                             remainder)))
    (ollama-protocol-error (condition)
      (error condition))
    (cl-codec-kit:cl-codec-kit-error (condition)
      (error 'ollama-protocol-error
             :message
             "HTTP response body is not valid UTF-8."
             :detail
             condition))))

(defun %validate-input-length (max-input-length)
  (when (and max-input-length (not (typep max-input-length '(integer 1 *))))
    (error 'ollama-argument-error
           :message
           "MAX-INPUT-LENGTH must be a positive integer."))
  max-input-length)

(defun %response-body-octet-length (body)
  (typecase body
    (string (%utf8-octet-length body))
    ((vector (unsigned-byte 8)) (length body))
    (otherwise nil)))

(defun %validate-response-body-length (body max-input-length)
  (let ((body-length (and max-input-length (%response-body-octet-length body))))
    (when (and body-length (> body-length max-input-length))
      (error 'ollama-protocol-error
             :message
             "HTTP response body exceeds the configured limit."
             :detail
             max-input-length)))
  body)

(defun %response-body-text (body)
  (cond
    ((null body) "")
    ((stringp body) body)
    ((%octet-vector-p body) (%decode-utf8 body))
    (t
     (error 'ollama-protocol-error
            :message
            "HTTP response body is neither text nor octets."
            :detail
            body))))

(defun %decode-response-body (body &optional max-input-length)
  (%validate-input-length max-input-length)
  (%validate-response-body-length body max-input-length)
  (%response-body-text body))

(defun %response-body-string (response max-input-length)
  (%decode-response-body (http-response-body response) max-input-length))

(defun %parse-json-text (text max-input-length &optional length-validated-p)
  (when
      (and (not length-validated-p)
           max-input-length
           (> (%utf8-octet-length text) max-input-length))
    (error 'ollama-protocol-error
           :message
           "HTTP response body exceeds the configured limit."
           :detail
           max-input-length))
  (if (zerop (length text))
      json-kit:+json-null+
      (handler-case (json-kit:parse text
                                    :object-type
                                    :hash-table
                                    :array-type
                                    :vector
                                    :null-value
                                    json-kit:+json-null+
                                    :false-value
                                    json-kit:+json-false+
                                    :max-input-length
                                    max-input-length
                                    :duplicate-key-policy
                                    :error)
        (json-kit:json-kit-error (condition)
          (error 'ollama-protocol-error
                 :message
                 "HTTP response body is not valid JSON."
                 :detail
                 condition)))))

(defun %http-error-data (body max-input-length)
  (handler-case (%parse-json-text body max-input-length)
    (ollama-protocol-error ()
      nil)))

(defun %http-error-message (data)
  (multiple-value-bind (error-data present-p) (%json-field data "error")
    (cond
      ((and present-p (stringp error-data)) error-data)
      (present-p
       (multiple-value-bind (nested-message nested-p)
           (%json-field error-data "message")
         (when (and nested-p (stringp nested-message))
           nested-message))))))

(defun %signal-http-error (response status body data)
  (let ((message (%http-error-message data)))
    (if message
        (error 'ollama-api-error
               :message
               message
               :status
               status
               :response
               response
               :body
               body
               :data
               data)
        (error 'ollama-http-error
               :message
               (format nil "Ollama request failed with HTTP status ~A" status)
               :status
               status
               :response
               response
               :body
               body))))

(defun %raise-http-error (response client)
  (let* ((status (http-response-status response))
         (body
          (handler-case (%response-body-string response
                                               (client-max-input-length client))
            (ollama-protocol-error ()
              "")))
         (data (%http-error-data body (client-max-input-length client))))
    (%signal-http-error response status body data)))

(defun %ensure-success (response client)
  (unless (http-response-p response)
    (error 'ollama-protocol-error
           :message
           "HTTP client did not return an HTTP response."
           :detail
           response))
  (unless (response-success-p response)
    (%raise-http-error response client))
  response)
