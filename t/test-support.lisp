(in-package #:ollama-kit/test)

(defun response (body &key (status 200) (stream nil))
  (make-http-response :status
                      status
                      :headers
                      `(("content-type" . "application/json"))
                      :body
                      (if stream
                          nil
                          body)
                      :stream
                      stream))

(defun response-with-text (text &key (status 200))
  (response (cl-codec-kit:string-to-octets text :encoding :utf-8)
            :status
            status))

(defun queued-client (&rest responses)
  (make-client :network-boundary
               (cl-boundary-kit:make-test-network-boundary :responses responses)))

(defun client-with-request-function (request-fn &rest options)
  (apply #'make-client
         :network-boundary
         (cl-boundary-kit:make-network-boundary :request-fn request-fn)
         options))

(defun openai-client-with-request-function (request-fn &rest options)
  (apply #'make-openai-client
         :network-boundary
         (cl-boundary-kit:make-network-boundary :request-fn request-fn)
         options))

(defun request-json-object (request)
  (json-kit:parse
   (cl-codec-kit:octets-to-string (http-request-body request) :encoding :utf-8)
   :object-type
   :hash-table
   :array-type
   :vector))

(defun %signals-p (type thunk)
  (handler-case (progn
                  (funcall thunk)
                  nil)
    (condition (condition)
      (typep condition type))))

(defun %with-temporary-binary-input (octets function)
  (let ((pathname
         (merge-pathnames
          (format nil "cl-ollama-kit-test-~D.bin" (get-internal-real-time))
          (uiop:temporary-directory))))
    (unwind-protect
        (progn
          (with-open-file
              (output pathname
                      :direction
                      :output
                      :if-exists
                      :supersede
                      :element-type
                      '(unsigned-byte 8))
            (write-sequence octets output))
          (with-open-file
              (input pathname
                     :direction
                     :input
                     :element-type
                     '(unsigned-byte 8))
            (funcall function input)))
      (when (probe-file pathname)
        (delete-file pathname)))))

(defun %read-all-characters (stream)
  (with-output-to-string (output)
    (loop for character = (read-char stream nil nil)
          while character
          do (write-char character output))))
