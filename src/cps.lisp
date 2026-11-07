#.(progn (in-package :ollama-kit) nil)

(defun %call-with-ollama-error (operation success failure)
  "Dispatch OPERATION's values to SUCCESS or an OLLAMA-ERROR to FAILURE."
  (let ((values
         (handler-case (multiple-value-list (funcall operation))
           (ollama-error (condition)
             (return-from %call-with-ollama-error
               (funcall failure condition))))))
    (apply success values)))

(defmacro with-ollama-continuations ((success failure) &body body)
  "Evaluate BODY with validated success and failure continuations.

SUCCESS and FAILURE are evaluated exactly once.  Values returned by BODY are
passed to SUCCESS, while an OLLAMA-ERROR is passed to FAILURE.  Errors raised
by either continuation remain visible to the caller."
  (let ((success-var (gensym "SUCCESS-"))
        (failure-var (gensym "FAILURE-")))
    `(let ((,success-var ,success)
           (,failure-var ,failure))
       (unless (functionp ,success-var)
         (error 'ollama-argument-error :message "SUCCESS must be a function."))
       (unless (functionp ,failure-var)
         (error 'ollama-argument-error :message "FAILURE must be a function."))
       (%call-with-ollama-error
        (lambda ()
          ,@body)
        ,success-var
        ,failure-var))))

(defun call-with-json (client method path success failure &rest arguments)
  "Run REQUEST-JSON in continuation-passing style.

SUCCESS receives the parsed JSON value and HTTP response as two arguments.
FAILURE receives an OLLAMA-ERROR condition.  Programming errors in the
continuations themselves are deliberately not intercepted."
  (with-ollama-continuations (success failure)
                             (apply #'request-json client method path arguments)))

(defmacro define-event-stream-consumer (name wire-format content-type docstring)
  (let ((function-name name)
        (wire-format-value wire-format)
        (content-type-value content-type)
        (function-docstring docstring))
    `(defun ,function-name (client method path event-function &rest options)
       ,function-docstring
       (%call-with-event-stream client
                                method
                                path
                                ,wire-format-value
                                event-function
                                ,content-type-value
                                options))))

(define-event-stream-consumer call-with-openai-stream
                              :sse
                              "text/event-stream"
                              "Consume OpenAI-compatible SSE events synchronously.

EVENT-FUNCTION receives each decoded JSON object. Return :STOP from it to cancel
the active request and complete normally. The HTTP response is closed before
this function returns.")

(define-event-stream-consumer call-with-ollama-stream
                              :ndjson
                              "application/x-ndjson"
                              "Consume native Ollama NDJSON events synchronously.

EVENT-FUNCTION receives each decoded JSON object. Return :STOP from it to cancel
the active request and complete normally. The HTTP response is closed before
this function returns.")

(define-event-stream-consumer call-with-anthropic-stream
                              :sse
                              "text/event-stream"
                              "Consume Anthropic-compatible SSE events synchronously.

EVENT-FUNCTION receives each decoded JSON object. Return :STOP from it to cancel
the active request and complete normally. The HTTP response is closed before
this function returns.")
