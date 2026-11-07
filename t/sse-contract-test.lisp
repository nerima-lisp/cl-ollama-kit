(in-package #:ollama-kit/test)

(progn
  (defun %sse-stream-test-octets (string)
    (cl-codec-kit:string-to-octets string :encoding :utf-8))

  (describe "SSE streaming contract"
    (it "parses explicit events across byte, UTF-8, and CRLF splits and stops at DONE"
        (let* ((crlf (format nil "~C~%" #\Return))
               (wire (format nil
                             ": heartbeat~Aevent: message~Aid: 7~Aunknown: ignored~Adata: {\"text\":\"こんにちは\",~Adata: \"ok\":true}~A~Adata: [DONE]~A~Adata: {\"after\":true}~A~A"
                             crlf crlf crlf crlf crlf crlf crlf crlf crlf crlf crlf))
               (octets (%sse-stream-test-octets wire))
               (events nil)
               (parser (ollama-kit::%make-stream-parser
                        :sse
                        512
                        (lambda (event)
                          (push event events)))))
          (loop for index below (length octets)
                for outcome = (ollama-kit::%feed-stream-parser
                               parser
                               (subseq octets index (1+ index)))
                when (eq :stop outcome)
                  do (return))
          (assert (eq :stop (ollama-kit::%finish-stream-parser parser)))
          (assert (= 1 (length events)))
          (assert (equal "こんにちは" (gethash "text" (first events))))
          (assert (eq t (gethash "ok" (first events))))))

    (it-each
     (("complete event" (format nil "data: {\"ok\":true}~%~%") 1)
      ("unterminated event" (format nil "data: {\"ok\":true}~%") 0))
     "emits ~A at EOF according to the blank-line terminator rule"
     (ending wire expected-count)
     (let ((events nil)
           (parser (ollama-kit::%make-stream-parser
                    :sse
                    128
                    (lambda (event)
                      (push event events)))))
       (ollama-kit::%feed-stream-parser parser (%sse-stream-test-octets wire))
       (ollama-kit::%finish-stream-parser parser)
       (assert (= expected-count (length events)))
       (when (plusp expected-count)
         (assert (eq t (gethash "ok" (first events)))))))

    (it "maps cl-sse-kit framing and input limits to protocol errors"
        (let ((parser (ollama-kit::%make-stream-parser :sse 16 (lambda (event)
                                                     (declare (ignore event))))))
          (assert (%signals-p
                   'ollama-protocol-error
                   (lambda ()
                     (ollama-kit::%feed-stream-parser
                      parser
                      (%sse-stream-test-octets
                       (format nil "data: {\"value\":true}~%~%")))))))

    (it "propagates a callback condition without mapping it to a parser error"
        (let ((parser (ollama-kit::%make-stream-parser
                       :sse
                       128
                       (lambda (event)
                         (declare (ignore event))
                         (error "callback failure")))))
          (assert (%signals-p
                   'simple-error
                   (lambda ()
                     (ollama-kit::%feed-stream-parser
                      parser
                      (%sse-stream-test-octets
                       (format nil "data: {\"ok\":true}~%~%")))))))))
))
