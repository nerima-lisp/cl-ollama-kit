#.(progn (in-package :ollama-kit) nil)

(defun %unsafe-blob-digest-p (digest)
  (or (%url-contains-control-p digest)
      (find-if
       (lambda (character)
         (find character "/\\?#"))
       digest)))

(defun %validate-blob-digest (digest)
  (unless (and (stringp digest) (plusp (length digest)))
    (error 'ollama-argument-error
           :message
           "BLOB digest must be a non-empty string."))
  (when (%unsafe-blob-digest-p digest)
    (error 'ollama-argument-error
           :message
           "BLOB digest contains unsafe path characters."))
  digest)

(defun %blob-path (digest)
  (%validate-blob-digest digest)
  (let ((path (concatenate 'string "/blobs/" digest)))
    (%validate-request-path path)
    path))

(defun blob-exists-p (client digest
                             &key
                             (timeout +timeout-unspecified+)
                             headers)
  "Return true when DIGEST is present in Ollama's blob store. A 404 returns NIL."
  (let ((response (perform-request client
                                   :head
                                   (%blob-path digest)
                                   :timeout
                                   timeout
                                   :headers
                                   headers)))
    (unless (http-response-p response)
      (error 'ollama-protocol-error
             :message
             "HTTP client did not return an HTTP response."
             :detail
             response))
    (let ((status (http-response-status response)))
      (cond
        ((and (integerp status) (<= 200 status 299)) t)
        ((and (integerp status) (= status 404)) nil)
        (t (%raise-http-error response client))))))

(defun push-blob (client digest
                         body
                         &key
                         (timeout +timeout-unspecified+)
                         headers)
  "Upload raw BODY to Ollama's blob store under DIGEST and return its response."
  (unless (or (stringp body) (%octet-vector-p body))
    (error 'ollama-argument-error
           :message
           "BLOB body must be a string or octet vector."
           :detail
           (type-of body)))
  (request-raw client
               :post
               (%blob-path digest)
               :body
               body
               :content-type
               "application/octet-stream"
               :accept
               nil
               :timeout
               timeout
               :headers
               headers))
