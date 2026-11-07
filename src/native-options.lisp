#.(progn (in-package :ollama-kit) nil)

(defun %optional-json-pair (key value &optional (transform #'identity))
  (when (%json-supplied-p value)
    (cons key (funcall transform value))))

(defun %stream-option-pair (stream-p)
  (cons "stream"
        (if stream-p
            t
            json-kit:+json-false+)))

(defun %native-bool (value)
  (cond
    ((or (null value) (json-kit:json-false-p value)) json-kit:+json-false+)
    ((eq value t) t)
    (t
     (error 'ollama-argument-error
            :message
            "Native boolean options must be NIL or T."
            :detail
            value))))

(defun %native-think (value)
  (cond
    ((or (null value) (eq value t) (json-kit:json-false-p value))
     (%native-bool value))
    ((or (stringp value) (symbolp value)) (%json-enum value))
    (t (%native-bool value))))
