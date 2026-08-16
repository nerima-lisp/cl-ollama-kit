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

(defun %validate-client-limits (max-input-length max-request-length)
  (unless (typep max-input-length '(integer 1 *))
    (error 'ollama-argument-error
           :message
           "MAX-INPUT-LENGTH must be a positive integer."))
  (unless (typep max-request-length '(integer 1 *))
    (error 'ollama-argument-error
           :message
           "MAX-REQUEST-LENGTH must be a positive integer."))
  (values max-input-length max-request-length))

(defun %validate-client-options (network-boundary api-key
                                                  timeout
                                                  max-input-length
                                                  max-request-length
                                                  allow-insecure-http)
  (unless network-boundary
    (error 'ollama-argument-error :message "A NETWORK-BOUNDARY is required."))
  (%validate-timeout timeout)
  (%validate-boolean allow-insecure-http "ALLOW-INSECURE-HTTP")
  (%validate-api-key api-key)
  (%validate-client-limits max-input-length max-request-length)
  network-boundary)

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

(defun %client-option-values (options)
  (values (%keyword-option options :base-url +default-base-url+)
          (%keyword-option options :network-boundary nil)
          (%keyword-option options :headers nil)
          (%keyword-option options :api-key nil)
          (%keyword-option options :timeout nil)
          (%keyword-option options :max-input-length 16777216)
          (%keyword-option options :max-request-length 16777216)
          (%keyword-option options :allow-insecure-http nil)))

(defun make-client (&rest options)
  "Create a client backed by a CL-BOUNDARY-KIT network boundary.

NETWORK-BOUNDARY is composed by the caller so production applications can
choose and configure their concrete HTTP implementation explicitly."
  (%validate-keyword-options options +client-option-keys+)
  (multiple-value-bind (base-url network-boundary
                                 headers
                                 api-key
                                 timeout
                                 max-input-length
                                 max-request-length
                                 allow-insecure-http)
      (%client-option-values options)
    (%validate-client-options network-boundary
                              api-key
                              timeout
                              max-input-length
                              max-request-length
                              allow-insecure-http)
    (let* ((normalized-headers (%normalize-headers headers))
           (normalized-base-url (%trim-base-url base-url)))
      (%validate-base-url normalized-base-url allow-insecure-http)
      (let ((with-auth (%client-headers-with-auth normalized-headers api-key)))
        (%make-client :base-url
                      normalized-base-url
                      :network-boundary
                      network-boundary
                      :headers
                      with-auth
                      :timeout
                      timeout
                      :max-input-length
                      max-input-length
                      :max-request-length
                      max-request-length
                      :api-key-p
                      (not (null api-key))
                      :allow-insecure-http
                      allow-insecure-http)))))
