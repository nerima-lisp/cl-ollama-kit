#.(progn (in-package :ollama-kit) nil)

(defun %validate-api-key (api-key)
  (when (and api-key (not (stringp api-key)))
    (error 'ollama-argument-error :message "API-KEY must be a string."))
  (when
      (and api-key
           (or (zerop (length api-key)) (%unsafe-header-value-p api-key)))
    (error 'ollama-argument-error
           :message
           "API-KEY must be a non-empty header-safe string."))
  api-key)

(defun %validate-client-limit-option (name value options)
  (declare (ignore options))
  (unless (typep value (quote (integer 1 *)))
    (error (quote ollama-argument-error)
           :message
           (format nil "~A must be a positive integer." (symbol-name name))))
  value)

(defun %client-option-default (name)
  (second (assoc name *client-option-table*)))

(defun %validate-client-options (option-values)
  (loop for option in *client-option-table*
        for name = (first option)
        for validator = (third option)
        do (setf (getf option-values name) (funcall (symbol-function validator)
                                                    name
                                                    (getf option-values name)
                                                    option-values)))
  option-values)

(defun %client-headers-with-auth (normalized-headers api-key)
  (when (and api-key (%header-present-p "Authorization" normalized-headers))
    (error 'ollama-argument-error
           :message
           "Do not combine API-KEY with an Authorization header."))
  (if api-key
      (%ensure-header normalized-headers
                      "Authorization"
                      (concatenate 'string "Bearer " api-key))
      normalized-headers))

(defun %validate-client-base-url-option (name value options)
  (declare (ignore name))
  (let ((base-url (%trim-base-url value)))
    (%validate-base-url base-url (getf options :allow-insecure-http))
    base-url))

(defun %validate-client-headers-option (name value options)
  (declare (ignore name))
  (%client-headers-with-auth (%normalize-headers value) (getf options :api-key)))

(defun %validate-client-api-key-option (name value options)
  (declare (ignore name options))
  (%validate-api-key value))

(defun %validate-client-boolean-option (name value options)
  (declare (ignore options))
  (%validate-boolean value (symbol-name name)))

(defun %validate-client-timeout-option (name value options)
  (declare (ignore name options))
  (%validate-timeout value))

(defun %validate-client-http-client-option (name value options)
  (declare (ignore name options))
  (when (and value (not (http-kit/client:http-client-p value)))
    (error (quote ollama-argument-error)
           :message
           "HTTP-CLIENT must be an HTTP-KIT/CLIENT:HTTP-CLIENT."
           :detail
           value))
  value)

(defun %client-option-values (options)
  (loop for option in *client-option-table*
        for name = (first option)
        for default = (%client-option-default name)
        append (list name (%keyword-option options name default))))

(defun make-client (&rest options)
  "Create a client backed by an owned or caller-supplied HTTP client."
  (%validate-keyword-options options *client-option-keys*)
  (let* ((option-values
          (%validate-client-options (%client-option-values options)))
         (base-url (getf option-values :base-url))
         (configured-http-client (getf option-values :http-client))
         (owned-http-client-p (null configured-http-client)))
    (when (and owned-http-client-p (eq (%url-scheme base-url) :https))
      (error (quote ollama-argument-error)
             :message
             "HTTPS requires a TLS-configured HTTP client; pass it with :HTTP-CLIENT."))
    (let* ((http-client
            (or configured-http-client
                (http-kit/client:make-http-client :default-timeout nil)))
           (client-option-initargs
            (loop for option in *client-option-table*
                  for name = (first option)
                  unless (eq name :api-key)
                    append (list name
                                 (if (eq name :http-client)
                                     http-client
                                     (getf option-values name)))))
           (derived-initargs
            (list :owned-http-client-p
                  owned-http-client-p
                  :api-key-p
                  (not (null (getf option-values :api-key))))))
      (apply (function %make-client)
             (append client-option-initargs derived-initargs)))))

(defun close-client (client)
  (unless (client-p client)
    (error 'ollama-argument-error
           :message
           "CLIENT must be an OLLAMA-KIT client."
           :detail
           client))
  (when (client-owned-http-client-p client)
    (http-kit/client:http-client-clear-connections (client-http-client client)))
  client)
