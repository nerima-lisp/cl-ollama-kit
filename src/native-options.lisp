(defun %optional-json-pair (key value &optional (transform #'identity))
  (when (%json-supplied-p value)
    (cons key (funcall transform value))))

(defmacro %native-body (&rest pairs)
  "Build a native JSON object directly from PAIRS."
  `(%json-object ,@pairs))

(defun %stream-option-pair (stream-p)
  (cons "stream" (if stream-p t json-kit:+json-false+)))

(defun %native-bool (value)
  (cond
    ((or (null value)
         (json-kit:json-false-p value))
     json-kit:+json-false+)
    ((eq value t) t)
    (t
     (error 'ollama-argument-error
            :message "Native boolean options must be NIL or T."
            :detail value))))

(defun %native-enum (value)
  (%json-enum value))

(defun %native-think (value)
  (if (or (stringp value) (symbolp value))
      (%native-enum value)
      (%native-bool value)))
