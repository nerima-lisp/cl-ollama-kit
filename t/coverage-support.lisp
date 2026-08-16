(in-package #:ollama-kit/test)

(defun coverage-tree-contains-symbol-p (tree symbol)
  (cond
    ((eq tree symbol) t)
    ((consp tree)
     (or (coverage-tree-contains-symbol-p (car tree) symbol)
         (coverage-tree-contains-symbol-p (cdr tree) symbol)))
    (t nil)))

(defun coverage-stream-response (&optional (payload (format nil "{}~%"))
                                           (content-type "application/x-ndjson"))
  (make-http-response :status
                      200
                      :headers
                      `(("content-type" . ,content-type))
                      :stream
                      (make-string-input-stream payload)))

(defun coverage-json-call (operation)
  (let ((value (funcall operation)))
    (assert (hash-table-p value))))

(defun coverage-stream-call (operation)
  (let ((stream (funcall operation)))
    (unwind-protect
        (multiple-value-bind (event present-p) (stream-next stream)
          (assert (hash-table-p event))
          (assert present-p))
      (stream-close stream))))

(defun coverage-path-p (request path)
  (assert (http-request-p request))
  (assert (stringp path))
  (let* ((url (http-request-url request))
         (authority-start (+ (or (search "://" url) -3) 3))
         (path-start
          (or (position #\/ url :start authority-start) (length url)))
         (path-end
          (or (position #\? url :start path-start)
              (position #\# url :start path-start)
              (length url))))
    (string= path (subseq url path-start path-end))))
