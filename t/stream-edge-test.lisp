(in-package #:ollama-kit/test)

(describe "stream callback option edge cases"
          (it-each
           (("Ollama response" (function call-with-ollama-stream) :response-timeout)
            ("Ollama idle" (function call-with-ollama-stream) :idle-timeout)
            ("OpenAI response" (function call-with-openai-stream) :response-timeout)
            ("OpenAI idle" (function call-with-openai-stream) :idle-timeout)
            ("Anthropic response" (function call-with-anthropic-stream) :response-timeout)
            ("Anthropic idle" (function call-with-anthropic-stream) :idle-timeout))
           "rejects invalid ~A timeout before transport"
           (name stream-function timeout-option)
           (let ((client (make-client)))
             (unwind-protect
                 (assert
                  (handler-case
                      (progn
                        (funcall stream-function
                                 client
                                 :post
                                 "/stream"
                                 (function identity)
                                 timeout-option
                                 -1)
                        nil)
                    (ollama-argument-error ()
                      t)))
               (close-client client)))))
(describe "stream callback HTTP lifecycle"
  (it "releases the HTTP connection when the callback returns :stop"
    (let* ((body
             (cl-codec-kit:string-to-octets
              (format nil "{\"response\":\"fixture\",\"done\":false}~%")
              :encoding
              :utf-8))
           (server (make-loopback-http-server :chunks (list body)))
           (client
             (make-client :base-url (loopback-http-server-url server)))
           (callback-count 0))
      (unwind-protect
          (progn
            (generate-stream
             client
             "test"
             "prompt"
             (lambda (event)
               (declare (ignore event))
               (incf callback-count)
               :stop))
            (assert (= 1 callback-count))
            (assert (loopback-http-server-await-eof server 1.5)))
        (close-client client)
        (close-loopback-http-server server))
      (assert (loopback-http-server-thread-joined-p server))
      (assert (loopback-http-server-listener-closed-p server)))))
