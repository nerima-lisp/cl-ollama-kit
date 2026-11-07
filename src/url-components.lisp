#.(progn (in-package :ollama-kit) nil)

(defun %url-control-p (character)
  (or (< (char-code character) 33) (= (char-code character) 127)))

(defun %url-contains-control-p (url)
  (some #'%url-control-p url))

(defun %url-scheme (url)
  (let ((scheme (http-kit:http-uri-scheme (http-kit:parse-http-uri url))))
    (if (string= scheme "http")
        :http
        :https)))

(defun %base-url-loopback-p (base-url)
  (handler-case (let* ((uri (http-kit:parse-http-uri base-url))
                       (host (http-kit:http-uri-host uri)))
                  (member host
                          '("localhost" "127.0.0.1" "::1")
                          :test
                          #'string-equal))
    (http-kit:http-invalid-uri ()
      nil)))

(defun %unsafe-path-segment-p (segment)
  (let ((normalized (string-downcase segment)))
    (or (string= segment ".")
        (string= segment "..")
        ;; A downstream URL implementation may decode these before
        ;; normalizing the path.  Reject encoded dot segments too.
        (search "%2e" normalized))))

(defun %path-contains-dot-segment-p (path)
  (let ((start 0))
    (loop (let* ((separator (position #\/ path :start start))
                 (end (or separator (length path)))
                 (segment (subseq path start end)))
            (when (%unsafe-path-segment-p segment)
              (return t))
            (unless separator
              (return))
            (setf start (1+ separator))))))

(defun %url-has-dot-path-segment-p (uri)
  (%path-contains-dot-segment-p (http-kit:http-uri-path uri)))

(defun %unsafe-request-path-p (relative-path)
  (or (search "://" relative-path)
      (find #\# relative-path)
      (find #\\ relative-path)
      (%path-contains-dot-segment-p
       (subseq relative-path
               0
               (or (position #\? relative-path) (length relative-path))))))
