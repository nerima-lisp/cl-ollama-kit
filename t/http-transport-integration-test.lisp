(in-package #:ollama-kit/test)

(define-condition http-transport-callback-error
  (error)
  ())

(defun %http-test-header-value (headers name)
  (loop for header in headers
        when (string-equal name (http-message-kit:http-header-name header))
          return (http-message-kit:http-header-content header)))

(defun %http-test-client (server &rest options)
  (apply #'make-client :base-url (loopback-http-server-url server) options))

(defun %capture-http-test-error (thunk)
  (handler-case (progn
                  (funcall thunk)
                  nil)
    (error (condition)
      condition)))

(defun %await-loopback-request (server seconds)
  (let ((deadline
         (+ (get-internal-real-time)
            (ceiling (* seconds internal-time-units-per-second)))))
    (loop (when (loopback-http-server-request server)
            (return t)) (when (>= (get-internal-real-time) deadline)
                          (return nil)) (sleep 0.005))))

(defun %join-http-test-thread (thread seconds)
  (when thread
    (not
     (eq :timed-out
         (sb-thread:join-thread thread :timeout seconds :default :timed-out)))))

(defun %assert-loopback-server-cleaned (server)
  (close-loopback-http-server server)
  (assert (loopback-http-server-thread-joined-p server))
  (assert (loopback-http-server-listener-closed-p server)))

(describe "HTTP transport integration"
          (it "uses the owned default HTTP client against a loopback server"
              (let* ((server
                      (make-loopback-http-server :body
                                                 (cl-codec-kit:string-to-octets
                                                  "{\"version\":\"fixture\"}"
                                                  :encoding
                                                  :utf-8)))
                     (client (%http-test-client server)))
                (unwind-protect
                    (multiple-value-bind (value response)
                        (request-json client :get "/version")
                      (assert
                       (http-kit/client:http-client-p
                        (client-http-client client)))
                      (assert
                       (http-message-kit:http-request-p
                        (loopback-http-server-request server)))
                      (assert (http-message-kit:http-response-p response))
                      (assert
                       (= 200 (http-message-kit:http-response-status response)))
                      (assert (equal "fixture" (gethash "version" value))))
                  (close-client client)
                  (%assert-loopback-server-cleaned server))))
          (it "round trips HTTP message kit request and response values"
              (let* ((server
                      (make-loopback-http-server :status
                                                 202
                                                 :headers
                                                 (list
                                                  (http-message-kit:make-http-header
                                                   "content-type"
                                                   "application/json")
                                                  (http-message-kit:make-http-header
                                                   "x-loopback-reply"
                                                   "accepted"))
                                                 :chunks
                                                 (list
                                                  (cl-codec-kit:string-to-octets
                                                   "{\"accepted\":"
                                                   :encoding
                                                   :utf-8)
                                                  (cl-codec-kit:string-to-octets
                                                   "true}"
                                                   :encoding
                                                   :utf-8))
                                                 :chunk-delay
                                                 0.01))
                     (client (%http-test-client server))
                     (response nil)
                     (value nil))
                (unwind-protect
                    (multiple-value-setq (value response) (request-json client
                                                                        :post
                                                                        "/round-trip?mode=fixture"
                                                                        :body
                                                                        (json-object
                                                                         "model"
                                                                         "tiny"
                                                                         "prompt"
                                                                         "日本😀")))
                  (close-client client)
                  (%assert-loopback-server-cleaned server))
                (let* ((request (loopback-http-server-request server))
                       (request-uri (http-message-kit:http-request-uri request))
                       (request-body
                        (http-message-kit:http-request-body request))
                       (request-json
                        (json-kit:parse
                         (cl-codec-kit:octets-to-string request-body
                                                        :encoding
                                                        :utf-8)
                         :object-type
                         :hash-table
                         :array-type
                         :vector))
                       (response-headers
                        (http-message-kit:http-response-headers response)))
                  (assert (http-message-kit:http-request-p request))
                  (assert
                   (string= "POST"
                            (http-message-kit:http-request-method request)))
                  (assert
                   (string= "/round-trip?mode=fixture"
                            (http-message-kit:http-request-target request)))
                  (assert
                   (string= "127.0.0.1"
                            (http-message-kit:http-uri-host request-uri)))
                  (assert
                   (string= "application/json; charset=utf-8"
                            (%http-test-header-value
                             (http-message-kit:http-request-headers request)
                             "content-type")))
                  (assert
                   (string= "application/json"
                            (%http-test-header-value
                             (http-message-kit:http-request-headers request)
                             "accept")))
                  (assert (string= "日本😀" (gethash "prompt" request-json)))
                  (assert (eq t (gethash "accepted" value)))
                  (assert (http-message-kit:http-response-p response))
                  (assert
                   (= 202 (http-message-kit:http-response-status response)))
                  (assert
                   (string= "accepted"
                            (%http-test-header-value response-headers
                                                     "x-loopback-reply")))
                  (assert
                   (equalp
                    (cl-codec-kit:string-to-octets "{\"accepted\":true}"
                                                   :encoding
                                                   :utf-8)
                    (http-message-kit:http-response-body response))))))
          (it-each
           (("Ollama JSON error" :api
                                 "{\"error\":\"model missing\"}"
                                 "model missing")
            ("plain HTTP error" :http
                                "upstream unavailable"
                                "upstream unavailable"))
           "maps a ~A response to the existing HTTP condition"
           (name error-kind body expected-message)
           (let* ((server
                   (make-loopback-http-server :status
                                              503
                                              :headers
                                              (list
                                               (http-message-kit:make-http-header
                                                "content-type"
                                                "application/json"))
                                              :body
                                              (cl-codec-kit:string-to-octets
                                               body
                                               :encoding
                                               :utf-8)))
                  (client (%http-test-client server))
                  (condition
                   (%capture-http-test-error
                    (lambda ()
                      (request-json client :get "/error")))))
             (unwind-protect
                 (progn
                   (if (eq error-kind :api)
                       (assert (typep condition 'ollama-api-error))
                       (assert
                        (and (typep condition 'ollama-http-error)
                             (not (typep condition 'ollama-api-error)))))
                   (assert (= 503 (ollama-http-error-status condition)))
                   (assert
                    (http-message-kit:http-response-p
                     (ollama-http-error-response condition)))
                   (assert (equal body (ollama-http-error-body condition)))
                   (when (eq error-kind :api)
                     (assert
                      (equal expected-message (ollama-error-message condition)))
                     (assert (hash-table-p (ollama-api-error-data condition)))))
               (close-client client)
               (%assert-loopback-server-cleaned server))))
          (it "bounds a non-JSON error body before storing the HTTP condition"
              (let* ((body
                      (make-array 4096
                                  :element-type
                                  '(unsigned-byte 8)
                                  :initial-element
                                  65))
                     (server (make-loopback-http-server :status 502 :body body))
                     (client (%http-test-client server :max-input-length 64))
                     (condition
                      (%capture-http-test-error
                       (lambda ()
                         (request-json client :get "/large-error")))))
                (unwind-protect
                    (progn
                      (assert (typep condition 'ollama-http-error))
                      (assert (= 502 (ollama-http-error-status condition)))
                      (assert
                       (<= 1 (length (ollama-http-error-body condition)) 64))
                      (assert
                       (http-message-kit:http-response-p
                        (ollama-http-error-response condition))))
                  (close-client client)
                  (%assert-loopback-server-cleaned server))))
          (it-each
           (("total request deadline" :no-response 0.3 nil nil :total nil)
            ("response header deadline" :no-response nil 0.3 nil :response nil)
            ("idle body deadline" :stalled-body nil nil 0.3 :idle nil)
            ("external cancellation" :no-response 1.5 nil nil :cancel nil)
            ("default options before response headers" :no-response
                                                       nil
                                                       nil
                                                       nil
                                                       :cancel
                                                       t)
            ("default options during a stalled body" :stalled-body
                                                     nil
                                                     nil
                                                     nil
                                                     :cancel
                                                     t))
           "signals the expected transport condition for ~A and releases the peer"
           (name behavior
                 timeout
                 response-timeout
                 idle-timeout
                 expected-kind
                 default-timeouts-p)
           (let* ((chunk
                   (cl-codec-kit:string-to-octets
                    (format nil "{\"response\":\"first\",\"done\":false}~%")
                    :encoding
                    :utf-8))
                  (server
                   (make-loopback-http-server :behavior
                                              behavior
                                              :chunks
                                              (when (eq behavior :stalled-body)
                                                (list chunk))))
                  (client (%http-test-client server))
                  (cancel-token
                   (when (eq expected-kind :cancel)
                     (http-kit/client:make-http-cancellation-token)))
                  (cancel-sent-p nil)
                  (events nil)
                  (cancel-thread
                   (when cancel-token
                     (sb-thread:make-thread
                      (lambda ()
                        (when (%await-loopback-request server 1)
                          (when
                              (and default-timeouts-p
                                   (eq behavior :stalled-body))
                            (loop repeat 200
                                  while (null events)
                                  do (sleep 0.005)))
                          (setf cancel-sent-p (http-kit/client:http-client-cancel-request
                                               cancel-token))))
                      :name
                      "cl-ollama-kit-test-cancel-sender")))
                  (condition
                   (%capture-http-test-error
                    (lambda ()
                      (let ((callback
                             (lambda (event)
                               (push event events))))
                        (if default-timeouts-p
                            (generate-stream client
                                             "tiny"
                                             "prompt"
                                             callback
                                             :cancel-token
                                             cancel-token)
                            (generate-stream client
                                             "tiny"
                                             "prompt"
                                             callback
                                             :timeout
                                             timeout
                                             :response-timeout
                                             response-timeout
                                             :idle-timeout
                                             idle-timeout
                                             :cancel-token
                                             cancel-token))))))
                  (cancel-thread-joined-p
                   (%join-http-test-thread cancel-thread 2)))
             (unwind-protect
                 (progn
                   (assert
                    (http-message-kit:http-request-p
                     (loopback-http-server-request server)))
                   (ecase expected-kind
                     (:total
                       (assert (typep condition 'ollama-transport-error))
                       (assert
                        (typep (ollama-transport-error-cause condition)
                               'http-kit:http-timeout)))
                     (:response
                       (assert (typep condition 'ollama-response-timeout))
                       (assert
                        (typep (ollama-transport-error-cause condition)
                               'http-kit/client:http-client-request-cancelled)))
                     (:idle
                       (assert (typep condition 'ollama-idle-timeout))
                       (assert
                        (typep (ollama-transport-error-cause condition)
                               'http-kit/client:http-client-request-cancelled)))
                     (:cancel
                       (assert cancel-sent-p)
                       (assert cancel-thread-joined-p)
                       (assert (typep condition 'ollama-cancelled))
                       (assert
                        (typep (ollama-transport-error-cause condition)
                               'http-kit/client:http-client-request-cancelled))))
                   (when (eq behavior :stalled-body)
                     (assert (= 1 (length events))))
                   (assert (loopback-http-server-await-eof server 1.5)))
               (when cancel-thread
                 (unless cancel-thread-joined-p
                   (%join-http-test-thread cancel-thread 1)))
               (close-client client)
               (%assert-loopback-server-cleaned server))))
          (it
           "propagates a body callback condition unchanged and releases the connection"
           (let* ((chunk
                   (cl-codec-kit:string-to-octets
                    (format nil "{\"response\":\"callback\",\"done\":false}~%")
                    :encoding
                    :utf-8))
                  (server (make-loopback-http-server :chunks (list chunk)))
                  (client (%http-test-client server))
                  (callback-condition
                   (make-condition 'http-transport-callback-error))
                  (condition
                   (%capture-http-test-error
                    (lambda ()
                      (generate-stream client
                                       "tiny"
                                       "prompt"
                                       (lambda (event)
                                         (declare (ignore event))
                                         (error callback-condition)))))))
             (unwind-protect
                 (progn
                   (assert (eq callback-condition condition))
                   (assert (loopback-http-server-await-eof server 1.5)))
               (close-client client)
               (%assert-loopback-server-cleaned server))))
          (it-each (("owned client" :owned) ("supplied HTTP client" :supplied))
                   "closes idle pooled sockets according to ~A ownership"
                   (name ownership)
                   (let* ((server
                           (make-loopback-http-server :keep-alive-p
                                                      t
                                                      :body
                                                      (cl-codec-kit:string-to-octets
                                                       "{\"ok\":true}"
                                                       :encoding
                                                       :utf-8)))
                          (supplied-http-client
                           (when (eq ownership :supplied)
                             (http-kit/client:make-http-client :default-timeout
                                                               nil)))
                          (client
                           (if supplied-http-client
                               (%http-test-client server
                                                  :http-client
                                                  supplied-http-client)
                               (%http-test-client server))))
                     (unwind-protect
                         (progn
                           (request-json client :get "/idle")
                           (assert
                            (not (loopback-http-server-await-eof server 0.05)))
                           (close-client client)
                           (if supplied-http-client
                               (progn
                                 (assert
                                  (not
                                   (loopback-http-server-await-eof server 0.05)))
                                 (http-kit/client:http-client-clear-connections
                                  supplied-http-client)
                                 (assert
                                  (loopback-http-server-await-eof server 1.5)))
                               (assert
                                (loopback-http-server-await-eof server 1.5))))
                       (when supplied-http-client
                         (http-kit/client:http-client-clear-connections
                          supplied-http-client))
                       (%assert-loopback-server-cleaned server))))
          (it-each
           (("without a supplied HTTP client" nil)
            ("with a caller-supplied HTTP client" t))
           "handles HTTPS base URLs for ~A"
           (name supplied-http-client-p)
           (let* ((http-client
                   (when supplied-http-client-p
                     (http-kit/client:make-http-client :default-timeout nil)))
                  (client nil))
             (unwind-protect
                 (let ((condition
                        (%capture-http-test-error
                         (lambda ()
                           (setf client (if supplied-http-client-p
                                            (make-client :base-url
                                                         "https://ollama.example"
                                                         :http-client
                                                         http-client)
                                            (make-client :base-url
                                                         "https://ollama.example")))))))
                   (if supplied-http-client-p
                       (progn
                         (assert (null condition))
                         (assert (client-p client))
                         (assert (eq http-client (client-http-client client))))
                       (assert (typep condition 'ollama-argument-error))))
               (when client
                 (close-client client))
               (when http-client
                 (http-kit/client:http-client-clear-connections http-client)))))
          (it "cancels the request on a non-local body callback exit"
              (let* ((body
                      (cl-codec-kit:string-to-octets "chunk" :encoding :utf-8))
                     (server
                      (make-loopback-http-server :behavior
                                                 :stalled-body
                                                 :chunks
                                                 (list body)))
                     (client (%http-test-client server))
                     (result nil))
                (unwind-protect
                    (progn
                      (setf result (catch :non-local-body-callback-exit
                                     (ollama-kit::send-http-request client
                                                                    (http-message-kit:make-http-request
                                                                     :method
                                                                     "GET"
                                                                     :uri
                                                                     (loopback-http-server-url
                                                                      server))
                                                                    :timeout
                                                                    1
                                                                    :collect-body-p
                                                                    nil
                                                                    :on-body-chunk
                                                                    (lambda
                                                                        (chunk)
                                                                      (declare (ignore
                                                                                chunk))
                                                                      (throw
                                                                          :non-local-body-callback-exit
                                                                        :escaped)))
                                     :returned))
                      (assert (eq :escaped result))
                      (assert (loopback-http-server-await-eof server 1.5)))
                  (close-client client)
                  (%assert-loopback-server-cleaned server)))))
