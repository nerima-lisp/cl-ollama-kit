(progn
  #.(progn (in-package :ollama-kit) nil)

  (defstruct (stream-line-framer
              (:constructor make-stream-line-framer))
    max-input-bytes
    (input-bytes 0)
    (line-number 0)
    line-bytes)

  (defun %make-stream-line-framer (max-input-bytes)
    (%validate-input-length max-input-bytes)
    (make-stream-line-framer
     :max-input-bytes max-input-bytes
     :input-bytes 0
     :line-number 0
     :line-bytes (make-array (min max-input-bytes 64)
                             :element-type '(unsigned-byte 8)
                             :adjustable t
                             :fill-pointer 0)))

  (defun %stream-line-limit-error (framer message)
    (error 'ollama-protocol-error
           :message message
           :detail (stream-line-framer-max-input-bytes framer)))

  (defun %stream-line-framer-line (framer line-function)
    (let* ((bytes (stream-line-framer-line-bytes framer))
           (length (fill-pointer bytes))
           (content-length (if (and (plusp length)
                                    (= #x0d (aref bytes (1- length))))
                               (1- length)
                               length))
           (line (%decode-utf8 (subseq bytes 0 content-length))))
      (setf (fill-pointer bytes) 0)
      (incf (stream-line-framer-line-number framer))
      (funcall line-function line (stream-line-framer-line-number framer))))

  (defun %feed-stream-line-framer (framer octets line-function)
    (unless (%octet-vector-p octets)
      (error 'ollama-protocol-error
             :message "Streaming body chunks must be octet vectors."
             :detail (type-of octets)))
    (let ((next-input (+ (stream-line-framer-input-bytes framer)
                         (length octets))))
      (when (> next-input (stream-line-framer-max-input-bytes framer))
        (%stream-line-limit-error
         framer
         "Ollama stream exceeds the configured input limit."))
      (setf (stream-line-framer-input-bytes framer) next-input))
    (loop for octet across octets
          for bytes = (stream-line-framer-line-bytes framer)
          do (if (= octet 10)
                 (when (eq :stop (%stream-line-framer-line framer line-function))
                   (return-from %feed-stream-line-framer :stop))
               (progn
                 (when (>= (fill-pointer bytes)
                           (stream-line-framer-max-input-bytes framer))
                   (%stream-line-limit-error
                    framer
                    "Ollama stream line exceeds the configured limit."))
                 (vector-push-extend octet bytes))))
    nil)

  (defun %finish-stream-line-framer (framer line-function)
    (if (zerop (fill-pointer (stream-line-framer-line-bytes framer)))
        nil
      (when (eq :stop (%stream-line-framer-line framer line-function))
        :stop))))

