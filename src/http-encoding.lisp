(defun %join-url (base-url path)
  (%validate-request-path path)
  (concatenate 'string
               (string-right-trim "/" base-url)
               "/"
               (string-left-trim "/" path)))

(defun %json-output-limit-error-p (condition)
  (string= (json-kit:json-serialization-error-message condition)
           "serialized output exceeds the configured maximum length"))

(defun %encode-json (object &optional max-request-length)
  (let ((text
         (handler-case (with-output-to-string (stream)
                         (json-kit:write-json object
                                              stream
                                              :max-output-length
                                              max-request-length))
           (json-kit:json-serialization-error (condition)
             (if (%json-output-limit-error-p condition)
                 (error 'ollama-argument-error
                        :message
                        "JSON request body exceeds the configured limit."
                        :detail
                        max-request-length)
                 (error condition))))))
    (let ((octets (cl-codec-kit:string-to-octets text :encoding :utf-8)))
      (when (and max-request-length (> (length octets) max-request-length))
        (error 'ollama-argument-error
               :message
               "JSON request body exceeds the configured limit."
               :detail
               max-request-length))
      octets)))

(defun %octet-vector-p (value)
  (typep value '(vector (unsigned-byte 8))))

(defun %request-body-length (body)
  (typecase body
    (string (length (cl-codec-kit:string-to-octets body :encoding :utf-8)))
    ((vector (unsigned-byte 8)) (length body))
    (otherwise nil)))
