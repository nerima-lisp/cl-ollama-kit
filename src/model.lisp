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

(defun %validate-client-options (http-client api-key
                                                timeout
                                                response-timeout
                                                idle-timeout
                                                max-input-length
                                                max-request-length
                                                allow-insecure-http)
  (when (and http-client
             (not (http-kit/client:http-client-p http-client)))
    (error 'ollama-argument-error
           :message "HTTP-CLIENT must be an HTTP-KIT/CLIENT:HTTP-CLIENT."
           :detail http-client))
  (%validate-timeout timeout)
  (%validate-timeout response-timeout)
  (%validate-timeout idle-timeout)
  (%validate-boolean allow-insecure-http "ALLOW-INSECURE-HTTP")
  (%validate-api-key api-key)
  (%validate-client-limits max-input-length max-request-length)
  http-client)


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
          (%keyword-option options :http-client nil)
          (%keyword-option options :headers nil)
          (%keyword-option options :api-key nil)
          (%keyword-option options :timeout nil)
          (%keyword-option options :response-timeout 300)
          (%keyword-option options :idle-timeout 120)
          (%keyword-option options :max-input-length 16777216)
          (%keyword-option options :max-request-length 16777216)
          (%keyword-option options :allow-insecure-http nil)))


(defun make-client (&rest options)
  "Create a client backed by an owned or caller-supplied HTTP client."
  (%validate-keyword-options options +client-option-keys+)
  (multiple-value-bind (base-url http-client
                                 headers
                                 api-key
                                 timeout
                                 response-timeout
                                 idle-timeout
                                 max-input-length
                                 max-request-length
                                 allow-insecure-http)
      (%client-option-values options)
    (%validate-client-options http-client
                              api-key
                              timeout
                              response-timeout
                              idle-timeout
                              max-input-length
                              max-request-length
                              allow-insecure-http)
    (let* ((normalized-headers (%normalize-headers headers))
           (normalized-base-url (%trim-base-url base-url)))
      (progn
        (%validate-base-url normalized-base-url allow-insecure-http)
        (when (and (null http-client)
                   (eq (%url-scheme normalized-base-url) :https))
          (error 'ollama-argument-error
                 :message
                 "HTTPS requires a TLS-configured HTTP client; pass it with :HTTP-CLIENT.")))
      (let* ((with-auth (%client-headers-with-auth normalized-headers api-key))
             (owned-http-client-p (null http-client))
             (http-client (or http-client
                              (http-kit/client:make-http-client
                               :default-timeout nil))))
        (%make-client :base-url
                      normalized-base-url
                      :http-client
                      http-client
                      :owned-http-client-p
                      owned-http-client-p
                      :headers
                      with-auth
                      :timeout
                      timeout
                      :response-timeout
                      response-timeout
                      :idle-timeout
                      idle-timeout
                      :max-input-length
                      max-input-length
                      :max-request-length
                      max-request-length
                      :api-key-p
                      (not (null api-key))
                      :allow-insecure-http
                      allow-insecure-http)))))
(defun close-client (client)
  (unless (client-p client)
    (error 'ollama-argument-error
           :message "CLIENT must be an OLLAMA-KIT client."
           :detail client))
  (when (client-owned-http-client-p client)
    (http-kit/client:http-client-clear-connections
     (client-http-client client)))
  client)


