(in-package #:ollama-kit/test)

(progn
  (defun %sse-stream-test-octets (string)
    (cl-codec-kit:string-to-octets string :encoding :utf-8))
  (describe "SSE streaming contract"
            (it "keeps UTF-8 data across byte and CRLF boundaries"
                (let* ((wire
                        (format nil
                                "data: {\"text\":\"こんにちは\",\"ok\":true}~C~%~C~%"
                                (code-char 13)
                                (code-char 13)))
                       (octets (%sse-stream-test-octets wire))
                       (events nil)
                       (parser
                        (ollama-kit::%make-stream-parser :sse
                                                         512
                                                         (lambda (event)
                                                           (push event events)))))
                  (loop for index below (length octets)
                        for outcome = (ollama-kit::%feed-stream-parser parser
                                                                       (subseq
                                                                        octets
                                                                        index
                                                                        (1+
                                                                         index)))
                        when (eq :stop outcome)
                          do (return))
                  (ollama-kit::%finish-stream-parser parser)
                  (assert (= 1 (length events)))
                  (assert (equal "こんにちは" (gethash "text" (first events))))
                  (assert (eq t (gethash "ok" (first events))))))
            (it "streams multi-line OpenAI events and stops at DONE over HTTP"
                (let* ((wire
                        (format nil
                                ": heartbeat~%x-unknown: ignored~%data: {\"text\":~%data: \"hello\"}~%~%data: [DONE]~%~%data: {\"text\":\"after\"}~%~%"))
                       (server
                        (make-loopback-http-server :chunks
                                                   (list
                                                    (%sse-stream-test-octets
                                                     wire))))
                       (client
                        (make-client :base-url
                                     (loopback-http-server-url server)))
                       (events nil))
                  (unwind-protect
                      (progn
                        (openai-chat-completions-stream client
                                                        (json-object "model"
                                                                     "tiny"
                                                                     "messages"
                                                                     #())
                                                        (lambda (event)
                                                          (push event events)))
                        (assert
                         (http-message-kit:http-request-p
                          (loopback-http-server-request server)))
                        (assert (= 1 (length events)))
                        (assert (equal "hello" (gethash "text" (first events))))
                        (assert (loopback-http-server-await-eof server 1.5)))
                    (close-client client)
                    (close-loopback-http-server server))
                  (assert (loopback-http-server-thread-joined-p server))
                  (assert (loopback-http-server-listener-closed-p server))))
            (it "drops an unterminated SSE event at HTTP EOF"
                (let* ((wire (format nil "data: {\"text\":\"discarded\"}~%"))
                       (server
                        (make-loopback-http-server :chunks
                                                   (list
                                                    (%sse-stream-test-octets
                                                     wire))))
                       (client
                        (make-client :base-url
                                     (loopback-http-server-url server)))
                       (events nil))
                  (unwind-protect
                      (progn
                        (openai-chat-completions-stream client
                                                        (json-object "model"
                                                                     "tiny"
                                                                     "messages"
                                                                     #())
                                                        (lambda (event)
                                                          (push event events)))
                        (assert
                         (http-message-kit:http-request-p
                          (loopback-http-server-request server)))
                        (assert (null events))
                        (close-client client)
                        (assert (loopback-http-server-await-eof server 1.5)))
                    (close-client client)
                    (close-loopback-http-server server))
                  (assert (loopback-http-server-thread-joined-p server))
                  (assert (loopback-http-server-listener-closed-p server))))
            (it-each
             (("complete event" "data: {\"ok\":true}~%~%" 1)
              ("unterminated event" "data: {\"ok\":true}~%" 0))
             "emits ~A at EOF according to the blank-line terminator rule"
             (ending wire-template expected-count)
             (let* ((wire (format nil wire-template))
                    (events nil)
                    (parser
                     (ollama-kit::%make-stream-parser :sse
                                                      128
                                                      (lambda (event)
                                                        (push event events)))))
               (ollama-kit::%feed-stream-parser parser
                                                (%sse-stream-test-octets wire))
               (ollama-kit::%finish-stream-parser parser)
               (assert (= expected-count (length events)))
               (when (plusp expected-count)
                 (assert (eq t (gethash "ok" (first events)))))))
            (it "maps cl-sse-kit framing and input limits to protocol errors"
                (let ((parser
                       (ollama-kit::%make-stream-parser :sse
                                                        16
                                                        (lambda (event)
                                                          (declare (ignore
                                                                    event))))))
                  (assert
                   (%signals-p 'ollama-protocol-error
                               (lambda ()
                                 (ollama-kit::%feed-stream-parser parser
                                                                  (%sse-stream-test-octets
                                                                   (format nil
                                                                           "data: {\"value\":true}~%~%"))))))))
            (it
             "propagates a callback condition without mapping it to a parser error"
             (let ((parser
                    (ollama-kit::%make-stream-parser :sse
                                                     128
                                                     (lambda (event)
                                                       (declare (ignore event))
                                                       (error
                                                        "callback failure")))))
               (assert
                (%signals-p 'simple-error
                            (lambda ()
                              (ollama-kit::%feed-stream-parser parser
                                                               (%sse-stream-test-octets
                                                                (format nil
                                                                        "data: {\"ok\":true}~%~%"))))))))))
