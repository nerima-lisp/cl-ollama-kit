#.(progn (in-package :ollama-kit) nil)

(defun %unsafe-blob-digest-p (digest)
  (or (some (lambda (character)
              (or (< (char-code character) 33)
                  (= (char-code character) 127)))
            digest)
      (find-if (lambda (character)
                 (find character "/\\?#"))
               digest)))

(defun %validate-blob-digest (digest)
  (unless (and (stringp digest) (plusp (length digest)))
    (error 'ollama-argument-error
           :message "BLOB digest must be a non-empty string."))
  (when (%unsafe-blob-digest-p digest)
    (error 'ollama-argument-error
           :message "BLOB digest contains unsafe path characters."))
  digest)

(defun %blob-path (digest)
  (%validate-blob-digest digest)
  (let ((path (concatenate 'string "/blobs/" digest)))
    (%validate-request-path path)
    path))

(defun blob-exists-p (client digest
                      &key (timeout +timeout-unspecified+) headers)
  "Return true when DIGEST is present in Ollama's blob store.

The HEAD response is always closed before this function returns." 
  (let ((response nil))
    (unwind-protect
         (progn
           (setf response
                 (perform-request client :head (%blob-path digest)
                                  :timeout timeout
                                  :headers headers))
           (unless (http-response-p response)
             (error 'ollama-protocol-error
                    :message "Network boundary did not return an HTTP response."
                    :detail response))
           (cond
             ((response-success-p response) t)
             ((= (http-response-status response) 404) nil)
             (t (%raise-http-error response client))))
      (when (http-response-p response)
        (%close-response-safely response)))))

(defun push-blob (client digest body
                  &key (timeout +timeout-unspecified+) headers)
  "Upload raw BODY to Ollama's blob store under DIGEST.

The successful HTTP response is returned to the caller, which owns it and
must eventually call CLOSE-HTTP-RESPONSE." 
  (unless (or (stringp body) (%octet-vector-p body))
    (error 'ollama-argument-error
           :message "BLOB body must be a string or octet vector."
           :detail (type-of body)))
  (request-raw client :post (%blob-path digest)
               :body body
               :content-type "application/octet-stream"
               :accept nil
               :timeout timeout
               :headers headers))
