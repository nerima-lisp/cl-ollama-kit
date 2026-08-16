#.(progn (in-package :ollama-kit) nil)

(defun %json-supplied-p (value)
  (not (eq value +json-unspecified+)))

(defun %json-enum (value)
  (if (symbolp value)
      (string-downcase (symbol-name value))
      value))

(defun %json-key (key)
  (cond
    ((stringp key) key)
    ((symbolp key) (string-downcase (symbol-name key)))
    (t
     (error 'ollama-argument-error
            :message
            "JSON object keys must be strings or symbols."))))

(defun %json-array (value)
  (cond
    ((vectorp value) value)
    ((listp value) (coerce value 'vector))
    (t value)))

(defun %json-object (&rest pairs)
  ;; PAIRS is the fresh list owned by this &REST binding.  Filter it in place
  ;; to avoid allocating a second list for omitted optional fields.
  (json-kit:alist->json-object (delete nil pairs)
                               :duplicate-key-policy :error))

(defun json-object (&rest pairs)
  "Create a JSON object from alternating KEY VALUE arguments.

Keys are strings or symbols.  This helper is intentionally explicit so a
plain Common Lisp alist is never guessed to be a JSON object by accident."
  (unless (evenp (length pairs))
    (error 'ollama-argument-error
           :message
           "JSON-OBJECT requires alternating key and value arguments."))
  (apply #'%json-object
         (loop for (key value) on pairs by #'cddr
               collect (cons (%json-key key) value))))

(defun %json-field-from-members (members key)
  (let ((entry (assoc key members :test #'string=)))
    (if entry
        (values (cdr entry) t)
        (values nil nil))))

(defun %json-alist-p (object)
  (and (listp object) (or (null object) (every #'consp object))))

(defun %json-field (object key)
  (cond
    ((hash-table-p object)
     (multiple-value-bind (value present-p) (gethash key object)
       (values value present-p)))
    ((json-kit:json-object-p object)
     (%json-field-from-members (json-kit:json-object-members object) key))
    ((%json-alist-p object) (%json-field-from-members object key))
    (t (values nil nil))))

(defun make-message (role content
                          &key
                          (name +json-unspecified+)
                          (tool-calls +json-unspecified+)
                          (thinking +json-unspecified+)
                          (images +json-unspecified+))
  "Create a chat message JSON object accepted by the native chat endpoint."
  (%json-object (cons "role" (%json-enum role))
                (cons "content" content)
                (and (%json-supplied-p name) (cons "name" name))
                (and (%json-supplied-p tool-calls)
                     (cons "tool_calls" (%json-array tool-calls)))
                (and (%json-supplied-p thinking) (cons "thinking" thinking))
                (and (%json-supplied-p images)
                     (cons "images" (%json-array images)))))

(defun %json-object-members (object)
  (cond
    ((hash-table-p object) (json-kit:json-object->alist object))
    ((json-kit:json-object-p object) (json-kit:json-object-members object))
    ((and (listp object) (or (null object) (every #'consp object))) object)
    (t
     (error 'ollama-argument-error
            :message
            "Expected a JSON object represented by a hash table or alist."))))

(defun %json-object-with-field (object key value)
  (let ((members (%json-object-members object))
        (kept nil))
    (dolist (member members)
      (unless (string= key (car member))
        (push member kept)))
    (json-kit:alist->json-object (nreverse (cons (cons key value) kept))
                                 :duplicate-key-policy
                                 :error)))
