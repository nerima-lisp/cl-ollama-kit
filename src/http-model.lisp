#.(progn (in-package :ollama-kit) nil)

(defun response-success-p (response)
  "Return true when RESPONSE has a 2xx HTTP status."
  (and (http-response-p response)
       (integerp (http-response-status response))
       (<= 200 (http-response-status response) 299)))

