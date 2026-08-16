(in-package #:ollama-kit/test)

(describe "Stream framing edge contracts"
          (it "handles character and binary line EOF and limits"
              (multiple-value-bind (line present-p)
                  (ollama-kit::%read-character-line-limited
                   (make-string-input-stream "final")
                   16)
                (assert present-p)
                (assert (equal "final" line)))
              (multiple-value-bind (line present-p)
                  (ollama-kit::%read-character-line-limited
                   (make-string-input-stream "")
                   16)
                (assert (not present-p))
                (assert (equal "" line)))
              (assert
               (%signals-p 'ollama-protocol-error
                           (lambda ()
                             (ollama-kit::%read-character-line-limited
                              (make-string-input-stream "abcd")
                              3))))
              (%with-temporary-binary-input
               (cl-codec-kit:string-to-octets "final" :encoding :utf-8)
               (lambda (stream)
                 (multiple-value-bind (line present-p)
                     (ollama-kit::%read-octet-line-limited stream 16)
                   (assert present-p)
                   (assert (equal "final" line)))))
              (%with-temporary-binary-input
               (cl-codec-kit:string-to-octets (format nil "final~%")
                                              :encoding
                                              :utf-8)
               (lambda (stream)
                 (multiple-value-bind (line present-p)
                     (ollama-kit::%read-octet-line-limited stream 16)
                   (assert present-p)
                   (assert (equal "final" line)))))
              (%with-temporary-binary-input
               (make-array 0 :element-type '(unsigned-byte 8))
               (lambda (stream)
                 (multiple-value-bind (line present-p)
                     (ollama-kit::%read-octet-line-limited stream 16)
                   (assert (not present-p))
                   (assert (equal "" line)))))
              (%with-temporary-binary-input
               (cl-codec-kit:string-to-octets "abcd" :encoding :utf-8)
               (lambda (stream)
                 (assert
                  (%signals-p 'ollama-protocol-error
                              (lambda ()
                                (ollama-kit::%read-octet-line-limited stream 3)))))))
          (it "decodes nested stream errors and ignores non-data SSE lines"
              (let ((event
                     (json-kit:alist->json-object
                      (list
                       (cons "error"
                             (json-kit:alist->json-object
                              '(("message" . "nested stream failure"))
                              :duplicate-key-policy
                              :preserve)))
                      :duplicate-key-policy
                      :preserve)))
                (let ((message (ollama-kit::%stream-error-message event)))
                  (assert (equal "nested stream failure" message))))
              (dolist
                  (error-data
                   (list
                    (json-kit:alist->json-object '(("message" . 7))
                                                 :duplicate-key-policy
                                                 :preserve)
                    (json-kit:alist->json-object nil
                                                 :duplicate-key-policy
                                                 :preserve)))
                (let ((event
                       (json-kit:alist->json-object
                        (list (cons "error" error-data))
                        :duplicate-key-policy
                        :preserve)))
                  (assert (null (ollama-kit::%stream-error-message event)))))
              (assert (not (ollama-kit::%string-prefix-p "data:" "x")))
              (assert (not (ollama-kit::%string-prefix-p "data:" "datum")))
              (let ((stream
                     (open-openai-stream
                      (queued-client
                       (response-with-text
                        (format nil
                                ": comment~%ignored: value~%~%data: {\"ok\":true}~%~%")))
                      :post
                      "/chat")))
                (multiple-value-bind (event present-p) (stream-next stream)
                  (assert present-p)
                  (assert (gethash "ok" event)))
                (multiple-value-bind (event present-p) (stream-next stream)
                  (declare (ignore event))
                  (assert (not present-p)))
                (assert (stream-closed-p stream)))
              (let ((stream
                     (open-openai-stream
                      (queued-client (response-with-text "data: {\"ok\":true}"))
                      :post
                      "/chat")))
                (multiple-value-bind (event present-p) (stream-next stream)
                  (assert present-p)
                  (assert (gethash "ok" event)))
                (assert (stream-closed-p stream)))
              (let ((stream
                     (open-openai-stream
                      (queued-client
                       (response-with-text
                        (format nil "data:{\"ok\":true}~%~%")))
                      :post
                      "/chat")))
                (unwind-protect
                    (multiple-value-bind (event present-p) (stream-next stream)
                      (assert present-p)
                      (assert (gethash "ok" event)))
                  (stream-close stream)))
              (let ((stream
                     (open-openai-stream
                      (queued-client
                       (response-with-text (format nil "data:~%~%")))
                      :post
                      "/chat")))
                (unwind-protect
                    (assert
                     (%signals-p 'ollama-protocol-error
                                 (lambda ()
                                   (stream-next stream))))
                  (stream-close stream))))
          (it "joins multiple SSE data lines into one JSON event"
              (let ((stream
                     (open-openai-stream
                      (queued-client
                       (response-with-text
                        (format nil "data: {\"ok\":~%data: true}~%~%")))
                      :post
                      "/chat")))
                (unwind-protect
                    (multiple-value-bind (event present-p) (stream-next stream)
                      (assert present-p)
                      (assert (eq t (gethash "ok" event))))
                  (stream-close stream))))
          (it "handles SSE completion markers, empty input, and line limits"
              (let ((done
                     (open-openai-stream
                      (queued-client
                       (response-with-text (format nil "data: [DONE]~%~%")))
                      :post
                      "/chat")))
                (multiple-value-bind (event present-p) (stream-next done)
                  (declare (ignore event))
                  (assert (not present-p)))
                (assert (stream-closed-p done)))
              (let ((empty
                     (open-openai-stream (queued-client (response-with-text ""))
                                         :post
                                         "/chat")))
                (multiple-value-bind (event present-p) (stream-next empty)
                  (declare (ignore event))
                  (assert (not present-p)))
                (assert (stream-closed-p empty)))
              (let ((ollama-kit::+max-sse-event-lines+ 1)
                    (stream
                     (open-openai-stream
                      (queued-client
                       (response-with-text (format nil ": one~%: two~%")))
                      :post
                      "/chat")))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (stream-next stream))))
                (assert (stream-closed-p stream))))
          (it "validates stream collection bounds and close idempotence"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text (format nil "{\"ok\":true}~%")))
                      :post
                      "/generate")))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (stream-events stream :limit -1))))
                (assert (null (stream-events stream :limit 0)))
                (assert (stream-closed-p stream))
                (multiple-value-bind (event present-p) (stream-next stream)
                  (declare (ignore event))
                  (assert (not present-p))))
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (response-with-text (format nil "{\"ok\":true}~%")))
                      :post
                      "/generate")))
                (assert (equal t (gethash "ok" (car (stream-events stream)))))
                (assert (stream-closed-p stream)))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (stream-next nil))))
              (assert
               (%signals-p 'ollama-argument-error
                           (lambda ()
                             (stream-close nil))))
              (let* ((closed 0)
                     (client
                      (queued-client
                       (make-http-response :status
                                           200
                                           :body
                                           (cl-codec-kit:string-to-octets
                                            (format nil "{\"ok\":true}~%")
                                            :encoding
                                            :utf-8)
                                           :close-function
                                           (lambda ()
                                             (incf closed))))))
                (let ((stream (open-ollama-stream client :post "/generate")))
                  (stream-close stream)
                  (stream-close stream)
                  (assert (= 1 closed)))))
          (it "closes malformed stream bodies during setup"
              (let* ((closed 0)
                     (client
                      (queued-client
                       (ollama-kit::%make-http-response :status
                                                        200
                                                        :body
                                                        '(1 2)
                                                        :close-function
                                                        (lambda ()
                                                          (incf closed))))))
                (assert
                 (%signals-p 'ollama-protocol-error
                             (lambda ()
                               (open-ollama-stream client :post "/generate"))))
                (assert (= 1 closed))))
          (it "preserves a stream parse error when cleanup also fails"
              (let ((stream
                     (open-ollama-stream
                      (queued-client
                       (make-http-response :status
                                           200
                                           :body
                                           (cl-codec-kit:string-to-octets "{"
                                                                          :encoding
                                                                          :utf-8)
                                           :close-function
                                           (lambda ()
                                             (error "stream close failure"))))
                      :post
                      "/generate"))
                    (warning-seen nil))
                (handler-bind ((warning
                                (lambda (condition)
                                  (when
                                      (search "stream cleanup failed"
                                              (string-downcase
                                               (princ-to-string condition)))
                                    (setf warning-seen t)
                                    (muffle-warning condition)))))
                  (let ((caught nil))
                    (handler-case (stream-next stream)
                      (ollama-protocol-error (condition)
                        (setf caught condition)))
                    (assert (typep caught 'ollama-protocol-error))))
                (assert warning-seen)
                (assert (stream-closed-p stream))))
          (it "reads binary wire streams through public Ollama streaming"
              (%with-temporary-binary-input
               (cl-codec-kit:string-to-octets (format nil "{\"binary\":true}~%")
                                              :encoding
                                              :utf-8)
               (lambda (wire)
                 (let ((stream
                        (open-ollama-stream
                         (queued-client
                          (make-http-response :status 200 :stream wire))
                         :post
                         "/generate")))
                   (unwind-protect
                       (multiple-value-bind (event present-p)
                           (stream-next stream)
                         (assert present-p)
                         (assert (eq t (gethash "binary" event))))
                     (stream-close stream))))))
          (it "closes the underlying wire stream"
              (let* ((wire (make-string-input-stream ""))
                     (stream
                      (open-ollama-stream
                       (queued-client
                        (make-http-response :status 200 :stream wire))
                       :post
                       "/generate")))
                (stream-close stream)
                (assert (not (open-stream-p wire)))))
          (it "closes streams without underlying wires"
              (let ((stream (ollama-kit::%make-ollama-stream :stream nil)))
                (stream-close stream)
                (assert (stream-closed-p stream)))))
