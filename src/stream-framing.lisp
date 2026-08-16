(defun %read-character-line-limited (stream limit)
  (let ((output
         (make-array (min limit 64)
                     :element-type
                     'character
                     :adjustable
                     t
                     :fill-pointer
                     0))
        (length 0)
        (present-p nil))
    (loop for character = (read-char stream nil nil)
          do (cond
               ((null character) (return (values output present-p)))
               ((char= character #\Newline) (return (values output t)))
               (t
                 (setf present-p t)
                 (incf length (%utf8-character-octets character))
                 (when (> length limit)
                   (error 'ollama-protocol-error
                          :message
                          "Ollama stream line exceeds the configured limit."
                          :detail
                          limit))
                 (vector-push-extend character output))))))

(defun %read-octet-line-limited (stream limit)
  (let ((bytes
         (make-array (min limit 64)
                     :element-type
                     '(unsigned-byte 8)
                     :adjustable
                     t
                     :fill-pointer
                     0))
        (present-p nil))
    (loop for byte = (read-byte stream nil nil)
          do (cond
               ((null byte) (return (values (%decode-utf8 bytes) present-p)))
               ((= byte 10) (return (values (%decode-utf8 bytes) t)))
               (t
                 (setf present-p t)
                 (when (>= (length bytes) limit)
                   (error 'ollama-protocol-error
                          :message
                          "Ollama stream line exceeds the configured limit."
                          :detail
                          limit))
                 (vector-push-extend byte bytes))))))

(defun %read-wire-line (stream)
  (if (%binary-stream-p (ollama-stream-stream stream))
      (%read-octet-line-limited (ollama-stream-stream stream)
                                (ollama-stream-max-line-length stream))
      (%read-character-line-limited (ollama-stream-stream stream)
                                    (ollama-stream-max-line-length stream))))

(defun %strip-line-return (line)
  (if (and (plusp (length line))
           (char= (char line (1- (length line))) #\Return))
      (subseq line 0 (1- (length line)))
      line))
