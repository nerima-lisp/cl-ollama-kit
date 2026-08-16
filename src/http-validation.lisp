#.(progn (in-package :ollama-kit) nil)

(defun %http-token-character-p (character)
  (let ((code (char-code character)))
    (or (<= (char-code #\A) code (char-code #\Z))
        (<= (char-code #\a) code (char-code #\z))
        (<= (char-code #\0) code (char-code #\9))
        (find character "!#$%&'*+-.^_`|~"))))

(defun %unsafe-header-value-p (value)
  (some
   (lambda (character)
     (let ((code (char-code character)))
       (or (< code 32) (= code 127))))
   value))

(defun %normalize-method (method)
  (let ((name
         (typecase method
           ((or keyword symbol) (symbol-name method))
           (string method)
           (t
            (error 'ollama-argument-error
                   :message
                   "HTTP methods must be strings or symbols.")))))
    (unless (and (plusp (length name)) (every #'%http-token-character-p name))
      (error 'ollama-argument-error
             :message
             "HTTP methods must be non-empty valid tokens."))
    (let* ((normalized-name (string-upcase name))
           (known-method
            (assoc normalized-name +standard-http-methods+ :test #'string=)))
      (or (cdr known-method) normalized-name))))

(defun %normalize-header-name (name)
  (let ((normalized
         (typecase name
           (string name)
           (symbol (string-downcase (symbol-name name)))
           (t
            (error 'ollama-argument-error
                   :message
                   "HTTP header names must be strings or symbols.")))))
    (unless
        (and (plusp (length normalized))
             (every #'%http-token-character-p normalized))
      (error 'ollama-argument-error
             :message
             "HTTP header names must be valid field-name tokens."))
    normalized))

(defun %normalize-header-entry (entry)
  (unless (consp entry)
    (error 'ollama-argument-error
           :message
           "Each header must be a cons of name and value."))
  (let ((name (%normalize-header-name (car entry)))
        (value (cdr entry)))
    (unless (stringp value)
      (error 'ollama-argument-error
             :message
             "HTTP header values must be strings."))
    (when (%unsafe-header-value-p value)
      (error 'ollama-argument-error
             :message
             "HTTP header values must not contain controls."))
    (cons name value)))

(defun %normalize-headers (headers)
  (unless (listp headers)
    (error 'ollama-argument-error
           :message
           "Headers must be an alist of name . value pairs."))
  (mapcar #'%normalize-header-entry headers))

(defun %header-present-p (name headers)
  (find name headers :key #'car :test #'string-equal))

(defun %ensure-header (headers name value)
  (unless (and (stringp value) (not (%unsafe-header-value-p value)))
    (error 'ollama-argument-error
           :message
           "HTTP header values must be control-free strings."))
  (if (%header-present-p name headers)
      headers
      (cons (cons name value) headers)))

(defun %force-header (headers name value)
  (let ((normalized-name (%normalize-header-name name)))
    (%ensure-header nil normalized-name value)
    (let ((kept nil))
      (dolist (entry headers)
        (let ((normalized-entry (%normalize-header-entry entry)))
          (unless (string-equal normalized-name (car normalized-entry))
            (push normalized-entry kept))))
      (cons (cons normalized-name value) (nreverse kept)))))

(defun %keyword-option-supplied-p (options keyword)
  (loop for tail on options by #'cddr
        thereis (eq (car tail) keyword)))

(defun %keyword-option (options keyword default)
  (if (%keyword-option-supplied-p options keyword)
      (getf options keyword)
      default))

(defun %validate-keyword-options (options allowed)
  (let ((length
         (handler-case (length options)
           (type-error ()
             nil))))
    (unless length
      (error 'ollama-argument-error
             :message
             "Keyword options must be a proper list."))
    (unless (evenp length)
      (error 'ollama-argument-error
             :message
             "Keyword options must be supplied as pairs."))
    (loop for tail on options by #'cddr
          for keyword = (car tail)
          do (unless
                 (and (keywordp keyword) (member keyword allowed :test #'eq))
               (error 'ollama-argument-error
                      :message
                      (format nil "Unknown keyword option ~S." keyword))))
    t))

(defun %validate-boolean (value name)
  (unless (or (null value) (eq value t))
    (error 'ollama-argument-error
           :message
           (format nil "~A must be NIL or T." name)
           :detail
           value))
  value)

(defun %validate-timeout (value)
  (unless
      (or (null value) (and (realp value) (= value value) (not (minusp value))))
    (error 'ollama-argument-error
           :message
           "TIMEOUT must be NIL or a non-negative real number."
           :detail
           value))
  value)
