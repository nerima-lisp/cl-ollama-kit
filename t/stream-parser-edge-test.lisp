(in-package #:ollama-kit/test)

(progn
  (defun %stream-test-octets (string)
    (cl-codec-kit:string-to-octets string :encoding :utf-8))
  (defun %stream-test-feed-one-octet-at-a-time (parser octets)
    (loop for index below (length octets)
          for outcome = (ollama-kit::%feed-stream-parser parser
                                                         (subseq octets
                                                                 index
                                                                 (1+ index)))
          when (eq :stop outcome)
            do (return :stop)))
  (describe "Incremental NDJSON framing"
            (it-each (("LF" :lf) ("CRLF" :crlf) ("EOF" :eof))
                     "decodes one JSON record terminated by ~A"
                     (ending wire-ending)
                     (let* ((wire
                             (ecase wire-ending
                               (:lf (format nil "{\"id\":1}~%"))
                               (:crlf (format nil "{\"id\":1}~C~%" #\Return))
                               (:eof "{\"id\":1}")))
                            (events nil)
                            (parser
                             (ollama-kit::%make-stream-parser :ndjson
                                                              128
                                                              (lambda (event)
                                                                (push event
                                                                      events)))))
                       (ollama-kit::%feed-stream-parser parser
                                                        (%stream-test-octets
                                                         wire))
                       (ollama-kit::%finish-stream-parser parser)
                       (assert (= 1 (length events)))
                       (assert (= 1 (gethash "id" (first events))))))
            (it "preserves records across UTF-8 and CRLF chunk boundaries"
                (let* ((wire
                        (format nil
                                "{\"text\":\"日本😀\",\"done\":true}~C~%"
                                #\Return))
                       (octets (%stream-test-octets wire))
                       (events nil)
                       (parser
                        (ollama-kit::%make-stream-parser :ndjson
                                                         128
                                                         (lambda (event)
                                                           (push event events)))))
                  (%stream-test-feed-one-octet-at-a-time parser octets)
                  (ollama-kit::%finish-stream-parser parser)
                  (assert (= 1 (length events)))
                  (assert (equal "日本😀" (gethash "text" (first events))))
                  (assert (eq t (gethash "done" (first events))))))
            (it "ignores blank records and enforces the total input limit"
                (let* ((events nil)
                       (parser
                        (ollama-kit::%make-stream-parser :ndjson
                                                         32
                                                         (lambda (event)
                                                           (push event events)))))
                  (ollama-kit::%feed-stream-parser parser
                                                   (%stream-test-octets
                                                    (format nil
                                                            "~%  ~%{\"n\":1}~%")))
                  (assert (= 1 (length events)))
                  (let ((bounded
                         (ollama-kit::%make-stream-parser :ndjson
                                                          8
                                                          (lambda (event)
                                                            (declare (ignore
                                                                      event))))))
                    (assert
                     (%signals-p 'ollama-protocol-error
                                 (lambda ()
                                   (ollama-kit::%feed-stream-parser bounded
                                                                    (%stream-test-octets
                                                                     (format nil
                                                                             "{\"n\":1}~%{}~%")))))))))
            (it "rejects malformed JSON and incomplete UTF-8 at EOF"
                (let ((malformed
                       (ollama-kit::%make-stream-parser :ndjson
                                                        128
                                                        (lambda (event)
                                                          (declare (ignore
                                                                    event))))))
                  (assert
                   (%signals-p 'ollama-protocol-error
                               (lambda ()
                                 (ollama-kit::%feed-stream-parser malformed
                                                                  (%stream-test-octets
                                                                   "{\"broken\":}"))
                                 (ollama-kit::%finish-stream-parser malformed)))))
                (let ((incomplete
                       (ollama-kit::%make-stream-parser :ndjson
                                                        128
                                                        (lambda (event)
                                                          (declare (ignore
                                                                    event))))))
                  (ollama-kit::%feed-stream-parser incomplete
                                                   (%stream-test-octets
                                                    "{\"text\":\""))
                  (ollama-kit::%feed-stream-parser incomplete
                                                   (make-array 2
                                                               :element-type
                                                               '(unsigned-byte
                                                                 8)
                                                               :initial-contents
                                                               '(240 159)))
                  (assert
                   (%signals-p 'ollama-protocol-error
                               (lambda ()
                                 (ollama-kit::%finish-stream-parser incomplete))))))
            (it "propagates callback conditions and stops on :STOP"
                (let ((condition-parser
                       (ollama-kit::%make-stream-parser :ndjson
                                                        128
                                                        (lambda (event)
                                                          (declare (ignore
                                                                    event))
                                                          (error
                                                           "callback failure")))))
                  (assert
                   (%signals-p 'simple-error
                               (lambda ()
                                 (ollama-kit::%feed-stream-parser
                                  condition-parser
                                  (%stream-test-octets
                                   (format nil "{\"n\":1}~%")))))))
                (let* ((events nil)
                       (parser
                        (ollama-kit::%make-stream-parser :ndjson
                                                         128
                                                         (lambda (event)
                                                           (push event events)
                                                           :stop))))
                  (assert
                   (eq :stop
                       (ollama-kit::%feed-stream-parser parser
                                                        (%stream-test-octets
                                                         (format nil
                                                                 "{\"n\":1}~%{\"n\":2}~%")))))
                  (assert (= 1 (length events)))))
            (it "parses NDJSON across HTTP chunks split inside UTF-8 and CRLF"
                (let* ((emoji-octets (%stream-test-octets "😀"))
                       (server
                        (make-loopback-http-server :chunks
                                                   (list
                                                    (concatenate
                                                     '(vector (unsigned-byte 8))
                                                     (%stream-test-octets
                                                      "{\"response\":\"日本")
                                                     (subseq emoji-octets 0 1))
                                                    (concatenate
                                                     '(vector (unsigned-byte 8))
                                                     (subseq emoji-octets 1)
                                                     (%stream-test-octets
                                                      (format nil
                                                              "\",\"done\":true}~C"
                                                              #\Return)))
                                                    (%stream-test-octets
                                                     (format nil "~%")))
                                                   :chunk-delay
                                                   0.01))
                       (client
                        (make-client :base-url
                                     (loopback-http-server-url server)))
                       (events nil)
                       (client-closed-p nil))
                  (unwind-protect
                      (progn
                        (generate-stream client
                                         "tiny"
                                         "prompt"
                                         (lambda (event)
                                           (push event events)))
                        (assert (= 1 (length events)))
                        (assert
                         (equal "日本😀" (gethash "response" (first events))))
                        (assert (eq t (gethash "done" (first events))))
                        (close-client client)
                        (setf client-closed-p t)
                        (assert (loopback-http-server-await-eof server 1.5)))
                    (unless client-closed-p
                      (close-client client))
                    (close-loopback-http-server server))))
            (it-each
             (("string error" "{\"error\":\"server unavailable\"}"
                              :signal
                              "server unavailable"
                              nil)
              ("object error" "{\"error\":{\"message\":\"denied\",\"code\":7}}"
                              :signal
                              "denied"
                              7)
              ("object without message" "{\"error\":{\"code\":9}}"
                                        :deliver
                                        nil
                                        9))
             "handles NDJSON ~A data"
             (kind wire outcome expected-message expected-code)
             (let* ((events nil)
                    (condition nil)
                    (parser
                     (ollama-kit::%make-stream-parser :ndjson
                                                      128
                                                      (lambda (event)
                                                        (push event events)))))
               (handler-case (ollama-kit::%feed-stream-parser parser
                                                              (%stream-test-octets
                                                               (format nil
                                                                       "~A~%"
                                                                       wire)))
                 (ollama-stream-error (caught)
                   (setf condition caught)))
               (ecase outcome
                 (:signal
                   (assert (typep condition 'ollama-stream-error))
                   (assert (null events))
                   (assert
                    (equal expected-message (ollama-error-message condition)))
                   (assert (= 1 (ollama-stream-error-line condition)))
                   (let* ((event (ollama-stream-error-event condition))
                          (error-data (gethash "error" event)))
                     (assert
                      (eq event (ollama-protocol-error-detail condition)))
                     (if expected-code
                         (progn
                           (assert (hash-table-p error-data))
                           (assert
                            (equal expected-message
                                   (gethash "message" error-data)))
                           (assert
                            (= expected-code (gethash "code" error-data))))
                         (assert (equal expected-message error-data)))))
                 (:deliver
                   (assert (null condition))
                   (assert (= 1 (length events)))
                   (let* ((event (first events))
                          (error-data (gethash "error" event)))
                     (assert (hash-table-p event))
                     (assert (hash-table-p error-data))
                     (assert (= expected-code (gethash "code" error-data)))
                     (multiple-value-bind (message present-p)
                         (gethash "message" error-data)
                       (declare (ignore message))
                       (assert (not present-p))))))))
            (it "rejects scalar JSON stream events with protocol details"
                (let* ((events nil)
                       (condition nil)
                       (parser
                        (ollama-kit::%make-stream-parser :ndjson
                                                         128
                                                         (lambda (event)
                                                           (push event events)))))
                  (handler-case (ollama-kit::%feed-stream-parser parser
                                                                 (%stream-test-octets
                                                                  (format nil
                                                                          "42~%")))
                    (ollama-protocol-error (caught)
                      (setf condition caught)))
                  (assert (typep condition 'ollama-protocol-error))
                  (assert
                   (equal "Ollama stream events must be JSON objects."
                          (ollama-error-message condition)))
                  (assert (= 42 (ollama-protocol-error-detail condition)))
                  (assert (null events))))
            (it "re-signals the same SSE callback condition"
                (let* ((detail (list :callback-detail))
                       (expected
                        (make-condition 'sse-kit:sse-error
                                        :message
                                        "callback SSE failure"
                                        :operation
                                        :callback
                                        :detail
                                        detail))
                       (observed nil)
                       (parser
                        (ollama-kit::%make-stream-parser :sse
                                                         128
                                                         (lambda (event)
                                                           (declare (ignore
                                                                     event))
                                                           (error expected)))))
                  (handler-case (ollama-kit::%feed-stream-parser parser
                                                                 (%stream-test-octets
                                                                  (format nil
                                                                          "data: {\"ok\":true}~%~%")))
                    (sse-kit:sse-error (caught)
                      (setf observed caught)))
                  (assert (typep observed 'sse-kit:sse-error))
                  (assert (eq expected observed))
                  (assert
                   (equal "callback SSE failure"
                          (sse-kit:sse-error-message observed)))
                  (assert (eq :callback (sse-kit:sse-error-operation observed)))
                  (assert (eq detail (sse-kit:sse-error-detail observed)))))
            (it "maps the SSE comment limit reached at EOF to protocol detail"
                (let* ((wire
                        (with-output-to-string (stream)
                          (loop repeat 10001
                                do (write-char #\: stream) (write-char #\Return
                                                                       stream))))
                       (octets (%stream-test-octets wire))
                       (condition nil)
                       (parser
                        (ollama-kit::%make-stream-parser :sse
                                                         32768
                                                         (lambda (event)
                                                           (declare (ignore
                                                                     event))))))
                  (assert (= 20002 (length octets)))
                  (ollama-kit::%feed-stream-parser parser octets)
                  (handler-case (ollama-kit::%finish-stream-parser parser)
                    (ollama-protocol-error (caught)
                      (setf condition caught)))
                  (assert (typep condition 'ollama-protocol-error))
                  (assert
                   (equal
                    "SSE response contains invalid framing or exceeds a limit."
                    (ollama-error-message condition)))
                  (let ((detail (ollama-protocol-error-detail condition)))
                    (assert (typep detail 'sse-kit:sse-size-limit-exceeded))
                    (assert
                     (= 10000 (sse-kit:sse-size-limit-exceeded-limit detail)))
                    (assert
                     (= 10001 (sse-kit:sse-size-limit-exceeded-observed detail)))
                    (assert
                     (eq :comments
                         (sse-kit:sse-size-limit-exceeded-kind detail))))))))
