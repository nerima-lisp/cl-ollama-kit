#.(progn (in-package :ollama-kit) nil)

(defun %trim-base-url (base-url)
  (unless (and (stringp base-url) (plusp (length base-url)))
    (error 'ollama-argument-error
           :message
           "BASE-URL must be a non-empty string."))
  (let ((trimmed (string-right-trim "/" base-url)))
    (if (plusp (length trimmed))
        trimmed
        (error 'ollama-argument-error
               :message
               "BASE-URL must contain more than URL separators."))))

(defun %validate-http-url-components (url subject)
  (when (%url-contains-control-p url)
    (error 'ollama-argument-error
           :message
           (format nil "~A must not contain controls or whitespace." subject)))
  (when (find #\# url)
    (error 'ollama-argument-error
           :message
           (format nil "~A must not contain a URL fragment." subject)))
  (let ((scheme (%url-scheme url)))
    (unless scheme
      (error 'ollama-argument-error
             :message
             (format nil "~A must use the HTTP or HTTPS scheme." subject)))
    (unless (%valid-host-authority-p (%url-authority url))
      (error 'ollama-argument-error
             :message
             (format nil "~A must contain a valid host authority." subject)))
    (when (%url-has-dot-path-segment-p url)
      (error 'ollama-argument-error
             :message
             (format nil "~A must not contain dot path segments." subject)))
    scheme))

(defun %validate-http-request-url (url)
  (%validate-http-url-components url "HTTP request URLs")
  url)

(defun %validate-base-url (base-url allow-insecure-http)
  (let ((scheme
         (%validate-http-url-components base-url "BASE-URL")))
    (when (find #\? base-url)
      (error 'ollama-argument-error
             :message
             "BASE-URL must not contain a query string."))
    (when (and (eq scheme :http)
               (not allow-insecure-http)
               (not (%base-url-loopback-p base-url)))
      (error 'ollama-argument-error
             :message
             "Non-loopback HTTP requires ALLOW-INSECURE-HTTP."))
    base-url))

(defun %validate-request-path (path)
  (unless (and (stringp path) (plusp (length path)))
    (error 'ollama-argument-error
           :message
           "Request path must be a non-empty string."))
  (when (%url-contains-control-p path)
    (error 'ollama-argument-error
           :message
           "Request paths must not contain controls or whitespace."))
  (let ((relative (string-left-trim "/" path)))
    (when (%unsafe-request-path-p relative)
      (error 'ollama-argument-error
             :message
             "Request paths must be relative and free of unsafe segments."))
    path))
