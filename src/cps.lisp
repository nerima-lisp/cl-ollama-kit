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

(defun call-with-stream (opener client
                                method
                                path
                                success
                                failure
                                &rest
                                arguments)
  "Open a stream in continuation-passing style.

OPENER receives CLIENT, METHOD, PATH, and ARGUMENTS.  SUCCESS owns returned
stream values; FAILURE receives an OLLAMA-ERROR."
  (unless (functionp opener)
    (error 'ollama-argument-error
           :message
           "CALL-WITH-STREAM requires a stream opener function."))
  (with-ollama-continuations (success failure)
                             (apply opener client method path arguments)))
