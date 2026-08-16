#.(progn (in-package :ollama-kit) nil)

(defun %validate-http-request-url-argument (url)
  (unless (and (stringp url) (plusp (length url)))
    (error 'ollama-argument-error
           :message
           "HTTP request URL must be a non-empty string."))
  (%validate-http-request-url url)
  url)

(defun %validate-http-body (body)
  (when
      (and body
           (not (or (stringp body) (typep body '(vector (unsigned-byte 8))))))
    (error 'ollama-argument-error
           :message
           "HTTP request body must be a string or octet vector."
           :detail
           (type-of body)))
  body)

(defun %validate-http-status (status)
  (unless (typep status '(integer 100 599))
    (error 'ollama-argument-error
           :message
           "HTTP response status must be an integer from 100 through 599."))
  status)

(defun %validate-http-response-body (body stream)
  (when (and body stream)
    (error 'ollama-argument-error
           :message
           "An HTTP response cannot contain both a body and a stream."))
  (when
      (and body
           (not (or (stringp body) (typep body '(vector (unsigned-byte 8))))))
    (error 'ollama-argument-error
           :message
           "HTTP response body must be a string or octet vector."
           :detail
           (type-of body)))
  body)

(defun %validate-http-response-stream (stream)
  (when (and stream (not (streamp stream)))
    (error 'ollama-argument-error
           :message
           "HTTP response streams must be stream objects."))
  stream)

(defun %validate-close-function (close-function)
  (when (and close-function (not (functionp close-function)))
    (error 'ollama-argument-error
           :message
           "HTTP response close callbacks must be functions."))
  close-function)

(defun %validate-http-response-options (status body stream close-function)
  (%validate-http-status status)
  (%validate-http-response-body body stream)
  (%validate-http-response-stream stream)
  (%validate-close-function close-function)
  (values status body stream close-function))

(defun make-http-request (&rest options)
  "Construct an HTTP request for a custom CL-BOUNDARY-KIT transport."
  (%validate-keyword-options options '(:method :url :headers :body :stream-p))
  (let ((method (%keyword-option options :method :get))
        (url (%keyword-option options :url nil))
        (headers (%keyword-option options :headers nil))
        (body (%keyword-option options :body nil))
        (stream-p (%keyword-option options :stream-p nil)))
    (%validate-http-request-url-argument url)
    (%validate-boolean stream-p "STREAM-P")
    (%validate-http-body body)
    (%make-http-request :method
                        (%normalize-method method)
                        :url
                        url
                        :headers
                        (%normalize-headers headers)
                        :body
                        body
                        :stream-p
                        (not (null stream-p)))))

(defun make-http-response (&key status headers body stream close-function)
  "Construct an HTTP response for a test or custom network boundary."
  (%validate-http-response-options status body stream close-function)
  (%make-http-response :status
                       status
                       :headers
                       (%normalize-headers headers)
                       :body
                       body
                       :stream
                       stream
                       :close-function
                       close-function))

(defun response-success-p (response)
  "Return true when RESPONSE has a 2xx HTTP status."
  (and (http-response-p response)
       (integerp (http-response-status response))
       (<= 200 (http-response-status response) 299)))

(defun %close-error (condition)
  (if (typep condition 'ollama-transport-error)
      condition
      (make-condition 'ollama-transport-error
                      :message
                      "Failed to close an HTTP response resource."
                      :cause
                      condition)))

(defun %close-resource (operation previous-error)
  (handler-case (progn
                  (funcall operation)
                  previous-error)
    (error (condition)
      (or previous-error (%close-error condition)))))

(defun %close-owned-resources (stream close-function)
  (let ((failure nil))
    (when (streamp stream)
      (setf failure (%close-resource
                     (lambda ()
                       (close stream))
                     failure)))
    (when close-function
      (setf failure (%close-resource close-function failure)))
    (when failure
      (error failure))))

(defun %close-http-response (response)
  "Release RESPONSE's stream and close callback at most once."
  (when (http-response-p response)
    (let ((stream (http-response-stream response))
          (close-function (http-response-close-function response)))
      (setf (http-response-stream response) nil
            (http-response-close-function response) nil)
      (%close-owned-resources stream close-function)))
  response)

(defun close-http-response (response)
  "Release RESPONSE's body stream and close callback at most once."
  (unless (http-response-p response)
    (error 'ollama-argument-error :message "Expected an HTTP response."))
  (%close-http-response response))
