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

(defun %validate-http-url-components
    (url control-message fragment-message scheme-message authority-message
     dot-segment-message &optional after-fragment-check)
  (when (%url-contains-control-p url)
    (error (quote ollama-argument-error) :message control-message))
  (when (find #\# url)
    (error (quote ollama-argument-error) :message fragment-message))
  (when after-fragment-check
    (funcall after-fragment-check))
  (let ((scheme (%url-scheme url)))
    (unless scheme
      (error (quote ollama-argument-error) :message scheme-message))
    (unless (%valid-host-authority-p (%url-authority url))
      (error (quote ollama-argument-error) :message authority-message))
    (when (%url-has-dot-path-segment-p url)
      (error (quote ollama-argument-error) :message dot-segment-message))
    scheme))

(defun %validate-http-request-url (url)
  (%validate-http-url-components
   url
   "HTTP request URLs must not contain controls or whitespace."
   "HTTP request URLs must not contain a fragment."
   "HTTP request URLs must use the HTTP or HTTPS scheme."
   "HTTP request URLs must contain a valid host authority."
   "HTTP request URLs must not contain dot path segments.")
  url)

(defun %validate-base-url (base-url allow-insecure-http)
  (let ((scheme
         (%validate-http-url-components
          base-url
          "BASE-URL must not contain controls or whitespace."
          "BASE-URL must not contain a URL fragment."
          "BASE-URL must use the HTTP or HTTPS scheme."
          "BASE-URL must contain a valid host authority."
          "BASE-URL must not contain dot path segments."
          (lambda ()
            (when (find #\? base-url)
              (error (quote ollama-argument-error)
                     :message
                     "BASE-URL must not contain a query string."))))))
    (when
        (and (eq scheme :http)
             (not allow-insecure-http)
             (not (%base-url-loopback-p base-url)))
      (error (quote ollama-argument-error)
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
