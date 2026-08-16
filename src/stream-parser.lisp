(defun %stream-error-message (event)
  (multiple-value-bind (error-data present-p) (%json-field event "error")
    (when present-p
      (cond
        ((stringp error-data) error-data)
        (t
         (multiple-value-bind (message message-p)
             (%json-field error-data "message")
           (when (and message-p (stringp message))
             message)))))))

(defun %decode-stream-event (stream payload line-number)
  (let* ((event
          (%parse-json-text payload (ollama-stream-max-line-length stream)))
         (error-message
          (progn
            (unless (hash-table-p event)
              (error 'ollama-protocol-error
                     :message
                     "Ollama stream events must be JSON objects."
                     :detail
                     event))
            (%stream-error-message event))))
    (when error-message
      (error 'ollama-stream-error
             :message
             error-message
             :detail
             event
             :event
             event
             :line
             line-number))
    event))

(defun %stream-next-ndjson (stream)
  (loop (multiple-value-bind (line present-p) (%read-wire-line stream)
          (unless present-p
            (stream-close stream)
            (return (values nil nil)))
          (incf (ollama-stream-line-number stream))
          (let ((line (%strip-line-return line)))
            (unless
                (zerop (length (string-trim '(#\Space #\Tab #\Return) line)))
              (return
               (values
                (%decode-stream-event stream
                                      line
                                      (ollama-stream-line-number stream))
                t)))))))

(defun %string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun %sse-data-string (data-lines)
  (with-output-to-string (output)
    (loop for line in (nreverse data-lines)
          for first-p = t then nil
          do (unless first-p
               (terpri output)) (write-string line output))))

(defun %sse-data-event (stream data-lines)
  (let ((payload (%sse-data-string data-lines)))
    (if (string= payload "[DONE]")
        (progn
          (stream-close stream)
          (values nil nil))
        (values
         (%decode-stream-event stream
                               payload
                               (ollama-stream-line-number stream))
         t))))

(defun %sse-data-line (line data-lines data-length limit)
  (let ((data (subseq line 5)))
    (when (and (plusp (length data)) (char= (char data 0) #\Space))
      (setf data (subseq data 1)))
    (let ((next-length
           (+ data-length
              (if data-lines
                  1
                  0)
              (%utf8-octet-length data))))
      (when (> next-length limit)
        (error 'ollama-protocol-error
               :message
               "SSE event data exceeds the configured limit."
               :detail
               limit))
      (values (cons data data-lines) next-length))))

(defun %sse-line-kind (line)
  (cond
    ((zerop (length line)) :empty)
    ((char= (char line 0) #\:) :comment)
    ((%string-prefix-p "data:" line) :data)
    (t :other)))

(defun %process-sse-line (line data-lines data-length limit)
  (case (%sse-line-kind line)
    (:empty (values (not (null data-lines)) data-lines data-length))
    (:data
     (multiple-value-bind (next-lines next-length)
         (%sse-data-line line data-lines data-length limit)
       (values nil next-lines next-length)))
    (otherwise (values nil data-lines data-length))))

(defun %validate-sse-event-line-count (event-line-count max-event-lines)
  (when (> event-line-count max-event-lines)
    (error 'ollama-protocol-error
           :message
           "SSE event contains too many lines."
           :detail
           max-event-lines)))

(defun %sse-end-of-input (stream data-lines)
  (stream-close stream)
  (if data-lines
      (%sse-data-event stream data-lines)
      (values nil nil)))

(defun %stream-next-sse (stream)
  (let ((data-lines '())
        (data-length 0)
        (event-line-count 0)
        (max-event-lines
         (min +max-sse-event-lines+ (ollama-stream-max-line-length stream))))
    (loop (multiple-value-bind (line present-p) (%read-wire-line stream)
            (unless present-p
              (return (%sse-end-of-input stream data-lines)))
            (incf (ollama-stream-line-number stream))
            (incf event-line-count)
            (%validate-sse-event-line-count event-line-count max-event-lines)
            (multiple-value-bind (emit-p next-lines next-length)
                (%process-sse-line (%strip-line-return line)
                                   data-lines
                                   data-length
                                   (ollama-stream-max-line-length stream))
              (setf data-lines next-lines
                    data-length next-length)
              (when emit-p
                (return (%sse-data-event stream data-lines))))))))
