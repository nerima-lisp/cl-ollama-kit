(in-package #:ollama-kit/test)

(progn
  (defun %stream-test-octets (string)
    (cl-codec-kit:string-to-octets string :encoding :utf-8))

  (defun %stream-test-feed-one-octet-at-a-time (parser octets)
    (loop for index below (length octets)
          for outcome = (ollama-kit::%feed-stream-parser
                         parser
                         (subseq octets index (1+ index)))
          when (eq :stop outcome)
            do (return :stop)))

  (describe "Incremental NDJSON framing"
    (it-each
     (("LF" (format nil "{\"id\":1}~%"))
      ("CRLF" (format nil "{\"id\":1}~C~%" #\Return))
      ("EOF" "{\"id\":1}"))
     "decodes one JSON record terminated by ~A"
     (ending wire)
     (let ((events nil)
           (parser (ollama-kit::%make-stream-parser
                    :ndjson
                    128
                    (lambda (event)
                      (push event events)))))
       (ollama-kit::%feed-stream-parser parser (%stream-test-octets wire))
       (ollama-kit::%finish-stream-parser parser)
       (assert (= 1 (length events)))
       (assert (= 1 (gethash "id" (first events))))))

    (it "preserves records across UTF-8 and CRLF chunk boundaries"
        (let* ((wire (format nil "{\"text\":\"日本😀\",\"done\":true}~C~%"
                             #\Return))
               (octets (%stream-test-octets wire))
               (events nil)
               (parser (ollama-kit::%make-stream-parser
                        :ndjson
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
               (parser (ollama-kit::%make-stream-parser
                        :ndjson
                        32
                        (lambda (event)
                          (push event events)))))
          (ollama-kit::%feed-stream-parser
           parser
           (%stream-test-octets
            (format nil "~%  ~%{\"n\":1}~%")))
          (assert (= 1 (length events)))
          (let ((bounded (ollama-kit::%make-stream-parser :ndjson 8 (lambda (event)
                                                          (declare (ignore event))))))
            (assert (%signals-p
                     'ollama-protocol-error
                     (lambda ()
                       (ollama-kit::%feed-stream-parser
                        bounded
                        (%stream-test-octets
                         (format nil "{\"n\":1}~%{}~%"))))))))

    (it "rejects malformed JSON and incomplete UTF-8 at EOF"
        (let ((malformed (ollama-kit::%make-stream-parser :ndjson 128 (lambda (event)
                                                            (declare (ignore event))))))
          (assert (%signals-p
                   'ollama-protocol-error
                   (lambda ()
                     (ollama-kit::%feed-stream-parser
                      malformed
                      (%stream-test-octets "{\"broken\":}"))
                     (ollama-kit::%finish-stream-parser malformed)))))
        (let ((incomplete (ollama-kit::%make-stream-parser :ndjson 128 (lambda (event)
                                                             (declare (ignore event))))))
          (ollama-kit::%feed-stream-parser incomplete
                               (%stream-test-octets "{\"text\":\""))
          (ollama-kit::%feed-stream-parser incomplete #(240 159))
          (assert (%signals-p
                   'ollama-protocol-error
                   (lambda ()
                     (ollama-kit::%finish-stream-parser incomplete))))))

    (it "propagates callback conditions and stops on :STOP"
        (let ((condition-parser
                (ollama-kit::%make-stream-parser
                 :ndjson
                 128
                 (lambda (event)
                   (declare (ignore event))
                   (error "callback failure")))))
          (assert (%signals-p
                   'simple-error
                   (lambda ()
                     (ollama-kit::%feed-stream-parser
                      condition-parser
                      (%stream-test-octets (format nil "{\"n\":1}~%"))))))
        (let ((events nil)
              (parser (ollama-kit::%make-stream-parser
                       :ndjson
                       128
                       (lambda (event)
                         (push event events)
                         :stop))))
          (assert (eq :stop
                      (ollama-kit::%feed-stream-parser
                       parser
                       (%stream-test-octets
                        (format nil "{\"n\":1}~%{\"n\":2}~%")))))
          (assert (= 1 (length events)))))))
))
