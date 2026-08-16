#.(progn (in-package :ollama-kit) nil)

(defun %close-stream-safely (stream reason)
  "Close STREAM without replacing a primary condition with a cleanup error."
  (handler-case (stream-close stream)
    (error (condition)
      (warn "Ollama stream cleanup failed ~A: ~A" reason condition))))

(defun stream-next (stream)
  "Read and decode the next event from STREAM.

Native Ollama streams use NDJSON; OpenAI-compatible streams use Server-Sent
Events.  Two values are returned: the decoded event and a true presence flag.
At EOF, or after an SSE `[DONE]` marker, NIL, NIL is returned."
  (unless (ollama-stream-p stream)
    (error 'ollama-argument-error
           :message "STREAM-NEXT requires an Ollama stream."))
  (if (stream-closed-p stream)
      (values nil nil)
      (handler-case
        (ecase (ollama-stream-wire-format stream)
            (:ndjson (%stream-next-ndjson stream))
            (:sse (%stream-next-sse stream)))
        (error (condition)
          ;; Cleanup is secondary to the parser or transport condition that is
          ;; already being handled.  Keep that primary condition observable.
          (%close-stream-safely stream
                                "after the primary condition was settled")
          (error condition)))))

(defun stream-events (stream &key limit)
  "Consume STREAM into a list, optionally stopping after LIMIT events."
  (unless (or (null limit) (typep limit '(integer 0 *)))
    (error 'ollama-argument-error
           :message
           "STREAM-EVENTS LIMIT must be NIL or a non-negative integer."))
  (let ((events '())
        (count 0))
    (unwind-protect
        (progn
          (loop while (or (null limit) (< count limit))
                do (multiple-value-bind (event present-p) (stream-next stream)
                     (unless present-p
                       (return))
                     (push event events)
                     (incf count)))
          (nreverse events))
      (%close-stream-safely stream "after consumption"))))

(defun stream-channel (stream &rest options)
  "Bridge STREAM into a `cl-concurrent-kit` channel.

Returns the channel and a completion promise.  The stream is closed when the
producer reaches EOF or exits because of an error."
  (%validate-keyword-options options '(:buffer-size :scope :executor))
  (let ((buffer-size (%keyword-option options :buffer-size 0))
        (scope (%keyword-option options :scope nil))
        (executor (%keyword-option options :executor nil)))
    (cl-concurrent-kit:channel-producer
     (emit :buffer-size buffer-size :scope scope :executor executor)
     (unwind-protect
         (loop (multiple-value-bind (event present-p) (stream-next stream)
                 (unless present-p
                   (return))
                 (funcall emit event)))
       (%close-stream-safely stream "after channel production")))))
