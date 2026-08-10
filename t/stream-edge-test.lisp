(in-package #:ollama-kit/test)

(describe "Stream concurrency composition"
  (it "bridges a stream through an explicit task scope"
    (cl-concurrent-kit:with-task-scope (scope)
      (let ((stream
              (open-ollama-stream
               (queued-client
                (response-with-text
                 (format nil "{\"n\":1}~%{\"n\":2}~%")))
               :post "/generate")))
        (multiple-value-bind (channel completion)
            (stream-channel stream :buffer-size 2 :scope scope)
          (multiple-value-bind (first first-p)
              (cl-concurrent-kit:recv channel)
            (assert first-p)
            (assert (= 1 (gethash "n" first))))
          (multiple-value-bind (second second-p)
              (cl-concurrent-kit:recv channel)
            (assert second-p)
            (assert (= 2 (gethash "n" second))))
          (cl-concurrent-kit:await completion)
          (multiple-value-bind (eof present-p)
              (cl-concurrent-kit:recv channel)
            (declare (ignore eof))
            (assert (not present-p)))))))

  (it "bridges a stream through an explicit executor"
    (cl-concurrent-kit:with-executor (executor :size 1)
      (let ((stream
              (open-ollama-stream
               (queued-client
                (response-with-text
                 (format nil "{\"n\":1}~%{\"n\":2}~%")))
               :post "/generate")))
        (multiple-value-bind (channel completion)
            (stream-channel stream :executor executor)
          (multiple-value-bind (first first-p)
              (cl-concurrent-kit:recv channel)
            (assert first-p)
            (assert (= 1 (gethash "n" first))))
          (multiple-value-bind (second second-p)
              (cl-concurrent-kit:recv channel)
            (assert second-p)
            (assert (= 2 (gethash "n" second))))
          (cl-concurrent-kit:await completion)
          (multiple-value-bind (eof present-p)
              (cl-concurrent-kit:recv channel)
            (declare (ignore eof))
            (assert (not present-p))))))))
