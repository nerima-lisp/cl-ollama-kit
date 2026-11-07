(progn
  #.(progn (in-package :ollama-kit) nil)

  (defstruct (stream-parser (:constructor %make-stream-parser-state))
    wire-format
    max-input-bytes
    event-function
    line-framer
    sse-parser
    callback-condition-tag
    stop-tag
    (stopped-p nil))

  (defun %make-stream-parser (wire-format max-input-bytes event-function)
    (unless (member wire-format '(:ndjson :sse))
      (error 'ollama-argument-error
             :message "STREAM wire format must be :NDJSON or :SSE."
             :detail wire-format))
    (unless (typep max-input-bytes '(integer 1 *))
      (error 'ollama-argument-error
             :message "STREAM input limit must be a positive integer."
             :detail max-input-bytes))
    (unless (functionp event-function)
      (error 'ollama-argument-error
             :message "STREAM event callback must be a function."
             :detail event-function))
    (let ((parser (%make-stream-parser-state
                   :wire-format wire-format
                   :max-input-bytes max-input-bytes
                   :event-function event-function
                   :callback-condition-tag (gensym "STREAM-CALLBACK-CONDITION-")
                   :stop-tag (gensym "STREAM-STOP-"))))
      (ecase wire-format
        (:ndjson
         (setf (stream-parser-line-framer parser)
               (%make-stream-line-framer max-input-bytes)))
        (:sse
         (setf (stream-parser-sse-parser parser)
               (sse-kit:make-http-sse-parser
                :max-events nil
                :max-line-bytes max-input-bytes
                :max-data-bytes max-input-bytes
                :max-input-bytes max-input-bytes
                :collect-events-p nil
                :on-event (lambda (event)
                            (%stream-parser-sse-event parser event))))))
      parser))

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

  (defun %decode-stream-event (parser payload line-number)
    (let* ((event (%parse-json-text payload
                                    (stream-parser-max-input-bytes parser)))
           (error-message
             (progn
               (unless (hash-table-p event)
                 (error 'ollama-protocol-error
                        :message "Ollama stream events must be JSON objects."
                        :detail event))
               (%stream-error-message event))))
      (when error-message
        (error 'ollama-stream-error
               :message error-message
               :detail event
               :event event
               :line line-number))
      event))

  (defun %stream-parser-event-callback (parser event)
    (handler-bind
        ((sse-kit:sse-error
           (lambda (condition)
             (throw (stream-parser-callback-condition-tag parser)
                    (list :callback-condition condition)))))
      (funcall (stream-parser-event-function parser) event)))

  (defun %stream-parser-deliver-event (parser payload line-number)
    (let ((event (%decode-stream-event parser payload line-number)))
      (when (eq :stop (%stream-parser-event-callback parser event))
        (setf (stream-parser-stopped-p parser) t)
        (throw (stream-parser-stop-tag parser) :stop)))
    nil)

  (defun %stream-parser-process-ndjson-line (parser line line-number)
    (unless (zerop (length (string-trim '(#\Space #\Tab #\Return) line)))
      (%stream-parser-deliver-event parser line line-number)))

  (defun %stream-parser-sse-event (parser event)
    (let ((payload (sse-kit:http-sse-event-data event)))
      (if (string= payload "[DONE]")
          (progn
            (setf (stream-parser-stopped-p parser) t)
            (throw (stream-parser-stop-tag parser) :stop))
        (%stream-parser-deliver-event parser payload nil))))

  (defun %raise-sse-protocol-error (condition)
    (error 'ollama-protocol-error
           :message "SSE response contains invalid framing or exceeds a limit."
           :detail condition))

  (defun %feed-sse-parser (parser octet-chunk)
    (handler-case
        (sse-kit:feed-http-sse-parser (stream-parser-sse-parser parser)
                                      octet-chunk)
      (sse-kit:sse-error (condition)
        (%raise-sse-protocol-error condition))))

  (defun %finish-sse-parser (parser)
    (handler-case
        (sse-kit:finish-http-sse-parser (stream-parser-sse-parser parser))
      (sse-kit:sse-error (condition)
        (%raise-sse-protocol-error condition))))

  (defun %run-stream-parser-step (parser operation)
    (let* ((callback-tag (stream-parser-callback-condition-tag parser))
           (stop-tag (stream-parser-stop-tag parser))
           (outcome
             (catch callback-tag
               (list :result
                     (catch stop-tag
                       (funcall operation)
                       nil)))))
      (if (eq :callback-condition (first outcome))
          (error (second outcome))
        (second outcome))))

  (defun %feed-stream-parser (parser octet-chunk)
    (unless (stream-parser-p parser)
      (error 'ollama-argument-error
             :message "STREAM-FEED requires a stream parser."
             :detail parser))
    (unless (%octet-vector-p octet-chunk)
      (error 'ollama-protocol-error
             :message "Streaming body chunks must be octet vectors."
             :detail (type-of octet-chunk)))
    (if (stream-parser-stopped-p parser)
        :stop
      (%run-stream-parser-step
       parser
       (lambda ()
         (ecase (stream-parser-wire-format parser)
           (:ndjson
            (%feed-stream-line-framer
             (stream-parser-line-framer parser)
             octet-chunk
             (lambda (line line-number)
               (%stream-parser-process-ndjson-line parser line line-number))))
           (:sse (%feed-sse-parser parser octet-chunk)))))))

  (defun %finish-stream-parser (parser)
    "Finish at EOF; deliver a final NDJSON line and discard unterminated SSE events."
    (unless (stream-parser-p parser)
      (error 'ollama-argument-error
             :message "STREAM-FINISH requires a stream parser."
             :detail parser))
    (if (stream-parser-stopped-p parser)
        :stop
      (%run-stream-parser-step
       parser
       (lambda ()
         (ecase (stream-parser-wire-format parser)
           (:ndjson
            (%finish-stream-line-framer
             (stream-parser-line-framer parser)
             (lambda (line line-number)
               (%stream-parser-process-ndjson-line parser line line-number))))
           (:sse (%finish-sse-parser parser)))))))
)

