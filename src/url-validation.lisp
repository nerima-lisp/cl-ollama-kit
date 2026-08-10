(defun %trim-base-url (base-url)
  (unless (and (stringp base-url) (plusp (length base-url)))
    (error 'ollama-argument-error
           :message "BASE-URL must be a non-empty string."))
  (let ((trimmed (string-right-trim "/" base-url)))
    (if (plusp (length trimmed))
        trimmed
        (error 'ollama-argument-error
               :message "BASE-URL must contain more than URL separators."))))

(defun %validate-http-request-url (url)
  (when (%url-contains-control-p url)
    (error 'ollama-argument-error
           :message "HTTP request URLs must not contain controls or whitespace."))
  (when (find #\# url)
    (error 'ollama-argument-error
           :message "HTTP request URLs must not contain a fragment."))
  (unless (%url-scheme url)
    (error 'ollama-argument-error
           :message "HTTP request URLs must use the HTTP or HTTPS scheme."))
  (unless (%valid-host-authority-p (%url-authority url))
    (error 'ollama-argument-error
           :message "HTTP request URLs must contain a valid host authority."))
  (when (%url-has-dot-path-segment-p url)
    (error 'ollama-argument-error
           :message "HTTP request URLs must not contain dot path segments."))
  url)

(defun %validate-base-url (base-url allow-insecure-http)
  (when (%url-contains-control-p base-url)
    (error 'ollama-argument-error
           :message "BASE-URL must not contain controls or whitespace."))
  (when (find #\# base-url)
    (error 'ollama-argument-error
           :message "BASE-URL must not contain a URL fragment."))
  (when (find #\? base-url)
    (error 'ollama-argument-error
           :message "BASE-URL must not contain a query string."))
  (let ((scheme (%url-scheme base-url)))
    (unless scheme
      (error 'ollama-argument-error
             :message "BASE-URL must use the HTTP or HTTPS scheme."))
    (unless (%valid-host-authority-p (%url-authority base-url))
      (error 'ollama-argument-error
             :message "BASE-URL must contain a valid host authority."))
    (when (%url-has-dot-path-segment-p base-url)
      (error 'ollama-argument-error
             :message "BASE-URL must not contain dot path segments."))
    (when (and (eq scheme :http)
               (not allow-insecure-http)
               (not (%base-url-loopback-p base-url)))
      (error 'ollama-argument-error
             :message "Non-loopback HTTP requires ALLOW-INSECURE-HTTP.")))
  base-url)

(defun %validate-request-path (path)
  (unless (and (stringp path) (plusp (length path)))
    (error 'ollama-argument-error :message "Request path must be a non-empty string."))
  (when (%url-contains-control-p path)
    (error 'ollama-argument-error
           :message "Request paths must not contain controls or whitespace."))
  (let ((relative (string-left-trim "/" path)))
    (when (%unsafe-request-path-p relative)
      (error 'ollama-argument-error
             :message "Request paths must be relative and free of unsafe segments."))
    path))
