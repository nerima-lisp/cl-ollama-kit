(in-package #:ollama-kit/test)

(defun response (body &key (status 200))
  (http-message-kit:make-http-response
   :status status
   :headers (list (cons "content-type" "application/json"))
   :body (if (stringp body)
             (cl-codec-kit:string-to-octets body :encoding :utf-8)
             body)))

(defun response-with-text (text &key (status 200))
  (response (cl-codec-kit:string-to-octets text :encoding :utf-8)
            :status
            status))

(defun client-with-request-function (request-function &rest options)
  (apply #'make-client
         :http-client
         (http-kit/client:make-http-client
          :transport-function
          (lambda (request &key timeout &allow-other-keys)
            (funcall request-function request :timeout timeout)))
         options))

(defconstant +loopback-http-max-header-bytes+ 65536)
  (defconstant +loopback-http-max-body-bytes+ 4194304)
  (defconstant +loopback-http-thread-join-seconds+ 2.0)

  (defvar *loopback-http-servers* nil)

  (defstruct (loopback-http-server
              (:constructor %make-loopback-http-server)
              (:conc-name %loopback-http-server-))
    listener
    port
    thread
    stream
    request
    request-bytes
    (request-count 0)
    status
    headers
    body
    chunks
    chunk-delay
    behavior
    keep-alive-p
    (eof-p nil)
    (server-error nil)
    (thread-joined-p nil)
    (listener-closed-p nil)
    (stream-closed-p nil)
    (stop-requested-p nil)
    (state-lock (sb-thread:make-mutex :name "loopback HTTP fixture state"))
    (eof-semaphore (sb-thread:make-semaphore :count 0)))

  (defun loopback-http-server-url (server)
    (format nil "http://127.0.0.1:~D" (%loopback-http-server-port server)))

  (defun loopback-http-server-request (server)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (%loopback-http-server-request server)))

  (defun loopback-http-server-request-bytes (server)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (%loopback-http-server-request-bytes server)))

  (defun loopback-http-server-eof-p (server)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (%loopback-http-server-eof-p server)))

  (defun loopback-http-server-server-error (server)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (%loopback-http-server-server-error server)))

  (defun loopback-http-server-thread-joined-p (server)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (%loopback-http-server-thread-joined-p server)))

  (defun loopback-http-server-listener-closed-p (server)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (%loopback-http-server-listener-closed-p server)))

  (defun loopback-http-server-await-eof (server timeout-seconds)
    (unless (and (realp timeout-seconds) (not (minusp timeout-seconds)))
      (error "Loopback EOF timeout must be a non-negative number of seconds, got ~S."
             timeout-seconds))
    (or (loopback-http-server-eof-p server)
        (and (sb-thread:wait-on-semaphore
              (%loopback-http-server-eof-semaphore server)
              :timeout timeout-seconds)
             (loopback-http-server-eof-p server))))

  (defun %loopback-set-state (server slot value)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (ecase slot
        (:stream
         (setf (%loopback-http-server-stream server) value))
        (:server-error
         (setf (%loopback-http-server-server-error server) value))
        (:thread-joined-p
         (setf (%loopback-http-server-thread-joined-p server) value))
        (:listener-closed-p
         (setf (%loopback-http-server-listener-closed-p server) value))
        (:stream-closed-p
         (setf (%loopback-http-server-stream-closed-p server) value))
        (:stop-requested-p
         (setf (%loopback-http-server-stop-requested-p server) value)))))

  (defun %loopback-record-eof (server)
    (let ((new-eof-p nil))
      (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
        (unless (%loopback-http-server-eof-p server)
          (setf (%loopback-http-server-eof-p server) t
                new-eof-p t)))
      (when new-eof-p
        (sb-thread:signal-semaphore
         (%loopback-http-server-eof-semaphore server)))
      new-eof-p))

  (defun %loopback-record-request (server request bytes)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (unless (%loopback-http-server-request server)
        (setf (%loopback-http-server-request server) request
              (%loopback-http-server-request-bytes server) bytes))
      (incf (%loopback-http-server-request-count server))))

  (defun %loopback-record-error (server condition)
    (sb-thread:with-mutex ((%loopback-http-server-state-lock server))
      (unless (%loopback-http-server-stop-requested-p server)
        (setf (%loopback-http-server-server-error server) condition))))

  (defun %read-loopback-http-request (stream)
    (let ((parser
            (http-message-kit:make-http1-parser
             :message-type :request
             :max-header-bytes +loopback-http-max-header-bytes+
             :max-body-bytes +loopback-http-max-body-bytes+
             :scheme "http"))
          (single-octet (make-array 1 :element-type '(unsigned-byte 8)))
          (request-bytes
            (make-array 0
                        :element-type '(unsigned-byte 8)
                        :adjustable t
                        :fill-pointer 0)))
      (loop for octet = (read-byte stream nil :eof)
            do (when (eq octet :eof)
                 (if (zerop (length request-bytes))
                     (return-from %read-loopback-http-request
                       (values nil nil t))
                     (error "Peer closed before its HTTP request was complete.")))
               (vector-push-extend octet request-bytes)
               (setf (aref single-octet 0) octet)
               (multiple-value-bind (request remainder complete-p)
                   (http-message-kit:http1-parser-feed parser single-octet)
                 (declare (ignore remainder))
                 (when complete-p
                   (return (values request (copy-seq request-bytes) nil)))))))

  (defun %loopback-ascii-octets (string)
    (map '(vector (unsigned-byte 8))
         (lambda (character)
           (let ((code (char-code character)))
             (unless (< code 128)
               (error "Loopback HTTP framing must be ASCII, got ~S." character))
             code))
         string))

  (defun %loopback-header-present-p (headers name)
    (some (lambda (header)
            (string-equal name (http-message-kit:http-header-name header)))
          headers))

  (defun %loopback-response-headers (server chunked-p body-length)
    (let* ((headers (copy-list (%loopback-http-server-headers server)))
           (status (%loopback-http-server-status server))
           (bodyless-p (or (< status 200) (= status 204) (= status 304))))
      (when (and chunked-p bodyless-p)
        (error "A bodyless fixture response cannot use chunked framing."))
      (when (and (not chunked-p)
                 (not bodyless-p)
                 (not (%loopback-header-present-p headers "content-length")))
        (setf headers
              (append headers
                      (list (http-message-kit:make-http-header
                             "content-length"
                             (write-to-string body-length))))))
      (when (and chunked-p
                 (not (%loopback-header-present-p headers "transfer-encoding")))
        (setf headers
              (append headers
                      (list (http-message-kit:make-http-header
                             "transfer-encoding" "chunked")))))
      (unless (%loopback-header-present-p headers "connection")
        (setf headers
              (append headers
                      (list
                       (http-message-kit:make-http-header
                        "connection"
                        (if (%loopback-http-server-keep-alive-p server)
                            "keep-alive"
                            "close"))))))
      headers))

  (defun %loopback-write-response-headers (stream server chunked-p body-length)
    (let ((headers (%loopback-response-headers server chunked-p body-length)))
      (write-sequence
       (%loopback-ascii-octets
        (with-output-to-string (output)
          (format output "HTTP/1.1 ~D Fixture~C~C"
                  (%loopback-http-server-status server)
                  #\Return #\Newline)
          (dolist (header headers)
            (format output "~A: ~A~C~C"
                    (http-message-kit:http-header-name header)
                    (http-message-kit:http-header-content header)
                    #\Return #\Newline))
          (format output "~C~C" #\Return #\Newline)))
       stream)
      (finish-output stream)))

  (defun %loopback-write-chunk (stream chunk)
    (write-sequence
     (%loopback-ascii-octets
      (format nil "~X~C~C" (length chunk) #\Return #\Newline))
     stream)
    (write-sequence chunk stream)
    (write-sequence
     (%loopback-ascii-octets (format nil "~C~C" #\Return #\Newline))
     stream)
    (finish-output stream))

  (defun %loopback-write-terminal-chunk (stream)
    (write-sequence
     (%loopback-ascii-octets
      (format nil "0~C~C~C~C"
              #\Return #\Newline #\Return #\Newline))
     stream)
    (finish-output stream))

  (defun %loopback-write-configured-response (server stream)
    (let* ((behavior (%loopback-http-server-behavior server))
           (chunks (%loopback-http-server-chunks server))
           (body (%loopback-http-server-body server))
           (chunked-p (or chunks
                          (member behavior '(:headers-only :stalled-body)))))
      (unless (eq behavior :no-response)
        (%loopback-write-response-headers
         stream server chunked-p
         (if chunks 0 (length body)))
        (case behavior
          (:headers-only nil)
          (:stalled-body
           (%loopback-write-chunk stream (or (first chunks) #(120))))
          (:response
           (if chunks
               (progn
                 (loop for chunk in chunks
                       for index from 0
                       do (%loopback-write-chunk stream chunk)
                          (when (and (< index (1- (length chunks)))
                                     (plusp (%loopback-http-server-chunk-delay server)))
                            (sleep (%loopback-http-server-chunk-delay server))))
                 (%loopback-write-terminal-chunk stream))
               (progn
                 (when (plusp (length body))
                   (write-sequence body stream))
                 (finish-output stream))))
          (otherwise
           (error "Unknown loopback HTTP response behavior ~S." behavior))))))

  (defun %loopback-wait-for-peer-eof (server stream)
    (loop for octet = (read-byte stream nil :eof)
          when (eq octet :eof)
            do (%loopback-record-eof server)
               (return t)))

  (defun %loopback-server-worker (server)
    (multiple-value-bind (stream peer-address peer-port)
        (http-kit/network:accept-http-tcp-stream
         (%loopback-http-server-listener server)
         :timeout 5)
      (declare (ignore peer-address peer-port))
      (%loopback-set-state server :stream stream)
      (loop
        (multiple-value-bind (request bytes eof-p)
            (%read-loopback-http-request stream)
          (when eof-p
            (%loopback-record-eof server)
            (return))
          (%loopback-record-request server request bytes)
          (%loopback-write-configured-response server stream)
          (unless (and (eq :response (%loopback-http-server-behavior server))
                       (%loopback-http-server-keep-alive-p server))
            (%loopback-wait-for-peer-eof server stream)
            (return))))))

  (defun make-loopback-http-server
      (&key (status 200) (headers nil) body chunks (chunk-delay 0)
            (behavior :response) (keep-alive-p t))
    (unless (and (integerp status) (<= 200 status 599))
      (error "Loopback HTTP status must be between 200 and 599, got ~S."
             status))
    (unless (and (listp headers)
                 (every #'http-message-kit:http-header-p headers))
      (error "Loopback HTTP headers must be a list of http-message-kit headers."))
    (unless (or (null body)
                (typep body '(vector (unsigned-byte 8))))
      (error "Loopback HTTP body must be an octet vector, got ~S." body))
    (unless (and (listp chunks)
                 (every (lambda (chunk)
                          (and (typep chunk '(vector (unsigned-byte 8)))
                               (plusp (length chunk))))
                        chunks))
      (error "Loopback HTTP chunks must be non-empty octet vectors."))
    (when (and body chunks)
      (error "Provide either a loopback body or chunks, not both."))
    (unless (and (realp chunk-delay) (not (minusp chunk-delay)))
      (error "Loopback HTTP chunk delay must be non-negative seconds, got ~S."
             chunk-delay))
    (unless (member behavior
                    '(:response :headers-only :no-response :stalled-body)
                    :test #'eq)
      (error "Unknown loopback HTTP behavior ~S." behavior))
    (let* ((listener
             (http-kit/network:open-http-tcp-listener
              :host "127.0.0.1" :port 0))
           (server
             (%make-loopback-http-server
              :listener listener
              :port (http-kit/network:http-network-listener-port listener)
              :status status
              :headers (copy-list headers)
              :body (or body #())
              :chunks (copy-list chunks)
              :chunk-delay chunk-delay
              :behavior behavior
              :keep-alive-p keep-alive-p)))
      (push server *loopback-http-servers*)
      (handler-case
          (setf (%loopback-http-server-thread server)
                (sb-thread:make-thread
                 (lambda ()
                   (handler-case
                       (%loopback-server-worker server)
                     (error (condition)
                       (%loopback-record-error server condition))))
                 :name "cl-ollama-kit-loopback-http-server"))
        (error (condition)
          (http-kit/network:close-http-tcp-listener listener)
          (%loopback-set-state server :listener-closed-p t)
          (error condition)))
      server))

  (defun close-loopback-http-server (server)
    (%loopback-set-state server :stop-requested-p t)
    (let ((cleanup-error nil)
          (listener (%loopback-http-server-listener server))
          (stream (and (not (%loopback-http-server-stream-closed-p server))
                       (%loopback-http-server-stream server))))
      (when stream
        (handler-case
            (progn
              (http-kit/network:close-http-tcp-stream stream)
              (%loopback-set-state server :stream-closed-p t))
          (error (condition)
            (setf cleanup-error condition))))
      (unless (loopback-http-server-listener-closed-p server)
        (handler-case
            (progn
              (http-kit/network:close-http-tcp-listener listener)
              (%loopback-set-state server :listener-closed-p t))
          (error (condition)
            (unless cleanup-error
              (setf cleanup-error condition)))))
      (let* ((thread (%loopback-http-server-thread server))
             (joined-p
               (or (null thread)
                   (not (eq :timed-out
                            (sb-thread:join-thread
                             thread
                             :timeout +loopback-http-thread-join-seconds+
                             :default :timed-out)))))) (%loopback-set-state server :thread-joined-p joined-p)
      (when cleanup-error
        (error cleanup-error))
      (values server
              (loopback-http-server-thread-joined-p server)
              (loopback-http-server-listener-closed-p server))))

  (cl-weave:around-each (next)
    (let ((*loopback-http-servers* nil))
      (unwind-protect
           (funcall next)
        (dolist (server *loopback-http-servers*)
          (close-loopback-http-server server)
          (unless (loopback-http-server-thread-joined-p server)
            (error "Loopback HTTP server thread did not join."))
          (unless (loopback-http-server-listener-closed-p server)
            (error "Loopback HTTP listener did not close.")))))))


(defun request-json-object (request)
  (json-kit:parse
   (cl-codec-kit:octets-to-string (http-message-kit:http-request-body request) :encoding :utf-8)
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
