(defun %url-control-p (character)
  (or (< (char-code character) 33) (= (char-code character) 127)))

(defun %url-contains-control-p (url)
  (some #'%url-control-p url))

(defun %url-scheme (url)
  (cond
    ((and (>= (length url) 7) (string-equal "http://" url :end2 7)) :http)
    ((and (>= (length url) 8) (string-equal "https://" url :end2 8)) :https)
    (t nil)))

(defun %url-component-end (url start delimiters)
  (or
   (position-if
    (lambda (character)
      (find character delimiters))
    url
    :start
    start)
   (length url)))

(defun %url-authority (url)
  (let* ((authority-start (+ (search "://" url) 3))
         (authority-end (%url-component-end url authority-start "/?#")))
    (subseq url authority-start authority-end)))

(defun %url-path (url)
  (let* ((authority-start (+ (search "://" url) 3))
         (authority-end (%url-component-end url authority-start "/?#")))
    (when
        (and (< authority-end (length url))
             (char= (char url authority-end) #\/))
      (subseq url authority-end (%url-component-end url authority-end "?#")))))

(defun %authority-host (authority)
  (if (char= (char authority 0) #\[)
      (let ((closing (position #\] authority)))
        (and closing (subseq authority 1 closing)))
      (subseq authority 0 (or (position #\: authority) (length authority)))))

(defun %base-url-loopback-p (base-url)
  (let ((authority (%url-authority base-url)))
    (when (or (zerop (length authority)) (find #\@ authority))
      (return-from %base-url-loopback-p))
    (let ((host (%authority-host authority)))
      (and host
           (member (string-downcase host)
                   '("localhost" "127.0.0.1" "::1")
                   :test
                   #'string=)))))

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

(defun %ascii-digit-p (character)
  (let ((code (char-code character)))
    (<= (char-code #\0) code (char-code #\9))))

(defun %decimal-port-p (port)
  (and (plusp (length port))
       (<= (length port) 5)
       (every #'%ascii-digit-p port)
       (<= (parse-integer port) 65535)))

(defun %valid-authority-port-p (suffix)
  (or (zerop (length suffix))
      (and (char= (char suffix 0) #\:) (%decimal-port-p (subseq suffix 1)))))

(defun %valid-bracketed-host-p (authority closing)
  (and (> closing 1)
       (not (find #\[ authority :start 1 :end closing))
       (every
        (lambda (character)
          (or (alphanumericp character) (find character ":.%_-")))
        (subseq authority 1 closing))))

(defun %valid-bracketed-authority-p (authority)
  (let ((closing (position #\] authority)))
    (and closing
         (%valid-bracketed-host-p authority closing)
         (%valid-authority-port-p (subseq authority (1+ closing))))))

(defun %valid-plain-host-p (host)
  (and (plusp (length host))
       (every
        (lambda (character)
          (or (alphanumericp character) (find character ".-_~!$&'()*+,;=")))
        host)))

(defun %valid-plain-authority-p (authority)
  (let ((colon (position #\: authority)))
    (and (not (find #\[ authority))
         (not (find #\] authority))
         (%valid-plain-host-p
          (subseq authority 0 (or colon (length authority))))
         (or (null colon) (%valid-authority-port-p (subseq authority colon))))))

(defun %valid-host-authority-p (authority)
  (and (plusp (length authority))
       (null (find #\@ authority))
       (if (char= (char authority 0) #\[)
           (%valid-bracketed-authority-p authority)
           (%valid-plain-authority-p authority))))

(defun %url-has-dot-path-segment-p (url)
  (let ((path (%url-path url)))
    (and path (%path-contains-dot-segment-p path))))

(defun %unsafe-request-path-p (relative-path)
  (or (search "://" relative-path)
      (find #\# relative-path)
      (find #\\ relative-path)
      (%path-contains-dot-segment-p
       (subseq relative-path
               0
               (or (position #\? relative-path) (length relative-path))))))
