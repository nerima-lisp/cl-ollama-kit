(defun %call-with-ollama-error (operation success failure)
  "Dispatch OPERATION's values to SUCCESS or an OLLAMA-ERROR to FAILURE."
  (let ((values
          (handler-case
              (multiple-value-list (funcall operation))
            (ollama-error (condition)
              (return-from %call-with-ollama-error
                (funcall failure condition))))))
    (apply success values)))

(defun call-with-json (client method path success failure &rest arguments)
  "Run REQUEST-JSON in continuation-passing style.

SUCCESS receives the parsed JSON value and HTTP response as two arguments.
FAILURE receives an OLLAMA-ERROR condition.  Programming errors in the
continuations themselves are deliberately not intercepted."
  (unless (functionp success)
    (error 'ollama-argument-error
           :message "SUCCESS must be a function."))
  (unless (functionp failure)
    (error 'ollama-argument-error
           :message "FAILURE must be a function."))
  (%call-with-ollama-error
   (lambda () (apply #'request-json client method path arguments))
   success
   failure))

(defun call-with-stream
    (opener client method path success failure &rest arguments)
  "Open a stream in continuation-passing style.

OPENER receives CLIENT, METHOD, PATH, and ARGUMENTS.  SUCCESS owns returned
stream values; FAILURE receives an OLLAMA-ERROR."
  (unless (functionp opener)
    (error 'ollama-argument-error
           :message "CALL-WITH-STREAM requires a stream opener function."))
  (unless (functionp success)
    (error 'ollama-argument-error
           :message "CALL-WITH-STREAM requires a success function."))
  (unless (functionp failure)
    (error 'ollama-argument-error
           :message "CALL-WITH-STREAM requires a failure function."))
  (%call-with-ollama-error
   (lambda () (apply opener client method path arguments))
   success
   failure))
