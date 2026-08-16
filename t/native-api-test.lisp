(in-package #:ollama-kit/test)

(describe "native API request contracts"
          (it-each
           ((list-models "/tags" :get) (list-running-models "/ps" :get)
                                       (version "/version" :get))
           "uses ~A for ~A"
           (operation path expected-method)
           (let* ((captured (list nil))
                  (client
                   (client-with-request-function
                    (lambda (request &key timeout)
                      (declare (ignore timeout))
                      (setf (car captured) request)
                      (response-with-text "{}")))))
             (let ((value (funcall operation client)))
               (declare (ignore value))
               (let ((request (car captured)))
                 (assert (http-request-p request))
                 (expect (http-request-method request)
                         :to-equal
                         expected-method)
                 (expect (http-request-url request)
                         :to-equal
                         (concatenate 'string "http://localhost:11434/api" path))
                 (expect (http-request-body request) :to-equal nil)))))
          (it "preserves explicit false, zero, and enum-valued options"
              (let ((captured nil))
                (let ((client
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (response-with-text "{}")))))
                  (generate client
                            "model"
                            "prompt"
                            :format
                            :json
                            :raw
                            nil
                            :think
                            :high
                            :width
                            768
                            :height
                            512
                            :steps
                            4
                            :keep-alive
                            0
                            :logprobs
                            nil
                            :top-logprobs
                            0))
                (let ((body (request-json-object captured)))
                  (multiple-value-bind (value present-p) (gethash "raw" body)
                    (assert present-p)
                    (assert (eq json-kit:+json-false+ value)))
                  (multiple-value-bind (value present-p) (gethash "think" body)
                    (assert present-p)
                    (assert (equal "high" value)))
                  (multiple-value-bind (value present-p)
                      (gethash "keep_alive" body)
                    (assert present-p)
                    (assert (= 0 value)))
                  (multiple-value-bind (value present-p)
                      (gethash "logprobs" body)
                    (assert present-p)
                    (assert (eq json-kit:+json-false+ value)))
                  (multiple-value-bind (value present-p)
                      (gethash "top_logprobs" body)
                    (assert present-p)
                    (assert (= 0 value)))
                  (assert (= 768 (gethash "width" body)))
                  (assert (= 512 (gethash "height" body)))
                  (assert (= 4 (gethash "steps" body)))
                  (assert (equal "json" (gethash "format" body)))
                  (assert (eq json-kit:+json-false+ (gethash "stream" body)))
                  (assert (equal :post (http-request-method captured)))
                  (assert
                   (equal "http://localhost:11434/api/generate"
                          (http-request-url captured))))))
          (it "preserves the JSON false sentinel for boolean-or-enum options"
              (let ((captured nil))
                (let ((client
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (response-with-text "{}")))))
                  (generate client
                            "model"
                            "prompt"
                            :think
                            json-kit:+json-false+))
                (assert
                 (json-kit:json-false-p
                  (gethash "think" (request-json-object captured))))))
          (it "preserves scalar and sequence embedding inputs"
              (let* ((captured (list nil))
                     (client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore timeout))
                         (setf (car captured) request)
                         (response-with-text "{}")))))
                (let ((value (embed client "model" "single")))
                  (declare (ignore value))
                  (let ((body (request-json-object (car captured))))
                    (assert (equal "single" (gethash "input" body)))))
                (let ((value
                       (embed client
                              "model"
                              #("one" "two")
                              :truncate
                              nil
                              :dimensions
                              768
                              :keep-alive
                              "5m")))
                  (declare (ignore value))
                  (let ((body (request-json-object (car captured))))
                    (assert (vectorp (gethash "input" body)))
                    (assert (equalp #("one" "two") (gethash "input" body)))
                    (assert
                     (eq json-kit:+json-false+ (gethash "truncate" body)))
                    (assert (= 768 (gethash "dimensions" body)))
                    (assert (equal "5m" (gethash "keep_alive" body)))))))
          (it "validates native embedding input and option types"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (error
                         "embedding validation should run before transport")))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (embed client "model" 42))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (embed client "model" "text" :dimensions 1.5))))
                (assert
                 (%signals-p 'ollama-argument-error
                             (lambda ()
                               (embed client "model" "text" :keep-alive 5))))))
          (it "sends image generation controls for native streaming"
              (let ((captured nil)
                    (stream nil))
                (setf stream (generate-stream
                              (client-with-request-function
                               (lambda (request &key timeout)
                                 (declare (ignore timeout))
                                 (setf captured request)
                                 (make-http-response :status
                                                     200
                                                     :headers
                                                     '(("content-type" .
                                                                       "application/x-ndjson"))
                                                     :stream
                                                     (make-string-input-stream
                                                      (format nil "{}~%")))))
                              "model"
                              "draw"
                              :width
                              1024
                              :height
                              768
                              :steps
                              12))
                (unwind-protect
                    (let ((body (request-json-object captured)))
                      (assert (= 1024 (gethash "width" body)))
                      (assert (= 768 (gethash "height" body)))
                      (assert (= 12 (gethash "steps" body)))
                      (assert (eq t (gethash "stream" body))))
                  (stream-close stream))))
          (it "sends create renderer and parser options"
              (let ((captured nil))
                (let ((client
                       (client-with-request-function
                        (lambda (request &key timeout)
                          (declare (ignore timeout))
                          (setf captured request)
                          (response-with-text "{}")))))
                  (create-model client "custom" :renderer "ggml" :parser "json"))
                (let ((body (request-json-object captured)))
                  (assert (equal "ggml" (gethash "renderer" body)))
                  (assert (equal "json" (gethash "parser" body)))
                  (assert (eq json-kit:+json-false+ (gethash "stream" body))))))
          (it "distinguishes omitted message fields from supplied JSON null"
              (let ((message
                     (make-message "user" "hello" :name json-kit:+json-null+)))
                (multiple-value-bind (name present-p) (gethash "name" message)
                  (assert present-p)
                  (assert (eq json-kit:+json-null+ name)))
                (multiple-value-bind (thinking present-p)
                    (gethash "thinking" message)
                  (declare (ignore thinking))
                  (assert (not present-p))))))
