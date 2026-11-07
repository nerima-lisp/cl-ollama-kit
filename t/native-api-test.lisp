(in-package #:ollama-kit/test)

(progn
  (defun %call-with-native-loopback-response (payload content-type function)
    (let* ((server
             (make-loopback-http-server
              :headers
              (list (http-message-kit:make-http-header "content-type" content-type))
              :body
              (cl-codec-kit:string-to-octets payload :encoding :utf-8)
              :keep-alive-p nil))
           (client
             (make-client :base-url
                          (concatenate 'string
                                       (loopback-http-server-url server)
                                       "/api"))))
      (unwind-protect
           (funcall function client server)
        (close-client client))))

  (defun %assert-native-loopback-request (server method path)
  (let ((request (loopback-http-server-request server)))
    (assert (http-message-kit:http-request-p request))
    (assert (string-equal (symbol-name method)
                          (http-message-kit:http-request-method request)))
    (assert
     (string= (concatenate 'string "/api" path)
              (http-message-kit:http-request-target request)))
    request))

  (defun %native-first-model-name (value)
    (let ((models (gethash "models" value)))
      (assert (and (vectorp models) (plusp (length models))))
      (gethash "name" (aref models 0))))

  (defun %native-version-value (value)
    (gethash "version" value))

  (describe "native API request contracts"
    (it-each
     ((list-models
       "/tags"
       :get
       "{\"models\":[{\"name\":\"fixture-model:latest\"}]}"
       %native-first-model-name
       "fixture-model:latest")
      (list-running-models
       "/ps"
       :get
       "{\"models\":[{\"name\":\"fixture-model:latest\"}]}"
       %native-first-model-name
       "fixture-model:latest")
      (version
       "/version"
       :get
       "{\"version\":\"0.5.1-fixture\"}"
       %native-version-value
       "0.5.1-fixture"))
     "decodes the ~A response from ~A"
     (operation path method response-body response-reader expected-value)
     (%call-with-native-loopback-response
      response-body
      "application/json"
      (lambda (client server)
        (let* ((value (funcall operation client))
               (request (%assert-native-loopback-request server method path)))
          (assert (null (http-message-kit:http-request-body request)))
          (assert (equal expected-value (funcall response-reader value)))))))

    (it "preserves explicit false, zero, and enum-valued generation options"
      (%call-with-native-loopback-response
       "{\"model\":\"fixture-model\",\"created_at\":\"2026-01-01T00:00:00Z\",\"response\":\"painted\",\"done\":true}"
       "application/json"
       (lambda (client server)
         (let* ((value
                  (generate client
                            "fixture-model"
                            "draw"
                            :format :json
                            :raw nil
                            :think :high
                            :width 768
                            :height 512
                            :steps 4
                            :keep-alive 0
                            :logprobs nil
                            :top-logprobs 0))
                (request
                  (%assert-native-loopback-request server :post "/generate"))
                (body (request-json-object request)))
           (multiple-value-bind (raw present-p) (gethash "raw" body)
             (assert present-p)
             (assert (eq json-kit:+json-false+ raw)))
           (multiple-value-bind (think present-p) (gethash "think" body)
             (assert present-p)
             (assert (equal "high" think)))
           (multiple-value-bind (keep-alive present-p)
               (gethash "keep_alive" body)
             (assert present-p)
             (assert (= 0 keep-alive)))
           (multiple-value-bind (logprobs present-p)
               (gethash "logprobs" body)
             (assert present-p)
             (assert (eq json-kit:+json-false+ logprobs)))
           (multiple-value-bind (top-logprobs present-p)
               (gethash "top_logprobs" body)
             (assert present-p)
             (assert (= 0 top-logprobs)))
           (assert (= 768 (gethash "width" body)))
           (assert (= 512 (gethash "height" body)))
           (assert (= 4 (gethash "steps" body)))
           (assert (equal "json" (gethash "format" body)))
           (assert (eq json-kit:+json-false+ (gethash "stream" body)))
           (assert (equal "fixture-model" (gethash "model" value)))
           (assert (equal "painted" (gethash "response" value)))
           (assert (eq t (gethash "done" value)))))))

    (it "preserves the JSON false sentinel for boolean-or-enum options"
      (%call-with-native-loopback-response
       "{\"model\":\"fixture-model\",\"response\":\"reasoned\",\"done\":true}"
       "application/json"
       (lambda (client server)
         (let* ((value
                  (generate client
                            "fixture-model"
                            "prompt"
                            :think
                            json-kit:+json-false+))
                (request
                  (%assert-native-loopback-request server :post "/generate"))
                (body (request-json-object request)))
           (assert (json-kit:json-false-p (gethash "think" body)))
           (assert (eq json-kit:+json-false+ (gethash "stream" body)))
           (assert (equal "reasoned" (gethash "response" value)))))))

    (it "parses scalar embedding input and the returned vector"
      (%call-with-native-loopback-response
       "{\"model\":\"fixture-model\",\"embeddings\":[[0.5,0.25]]}"
       "application/json"
       (lambda (client server)
         (let* ((value (embed client "fixture-model" "single"))
                (request (%assert-native-loopback-request server :post "/embed"))
                (body (request-json-object request))
                (embedding (aref (gethash "embeddings" value) 0)))
           (assert (equal "fixture-model" (gethash "model" body)))
           (assert (equal "single" (gethash "input" body)))
           (assert (equal "fixture-model" (gethash "model" value)))
           (assert (< (abs (- 0.5 (aref embedding 0))) 0.000001))))))

    (it-each
     (("vector input" #("one" "two") #("one" "two"))
      ("list input" ("one" "two") #("one" "two")))
     "preserves ~A embedding inputs and their options"
     (input-kind input expected-input)
     (%call-with-native-loopback-response
      "{\"model\":\"fixture-model\",\"embeddings\":[[0.5,0.25],[0.75,0.125]]}"
      "application/json"
      (lambda (client server)
        (let* ((value
                 (embed client
                        "fixture-model"
                        input
                        :truncate nil
                        :dimensions 768
                        :keep-alive "5m"))
               (request (%assert-native-loopback-request server :post "/embed"))
               (body (request-json-object request))
               (embeddings (gethash "embeddings" value)))
          (assert (equal "fixture-model" (gethash "model" body)))
          (assert (vectorp (gethash "input" body)))
          (assert (equalp expected-input (gethash "input" body)))
          (assert (eq json-kit:+json-false+ (gethash "truncate" body)))
          (assert (= 768 (gethash "dimensions" body)))
          (assert (equal "5m" (gethash "keep_alive" body)))
          (assert (= 2 (length embeddings)))
          (assert (< (abs (- 0.75 (aref (aref embeddings 1) 0)))
                     0.000001))))))

    (it "validates native embedding input and option types before transport"
      (%call-with-native-loopback-response
       "{}"
       "application/json"
       (lambda (client server)
         (assert
          (%signals-p 'ollama-argument-error
                      (lambda () (embed client "fixture-model" 42))))
         (assert
          (%signals-p 'ollama-argument-error
                      (lambda ()
                        (embed client "fixture-model" "text" :dimensions 1.5))))
         (assert
          (%signals-p 'ollama-argument-error
                      (lambda ()
                        (embed client "fixture-model" "text" :keep-alive 5))))
         (assert (null (loopback-http-server-request server))))))

    (it "sends image-generation controls and reads callback events"
      (%call-with-native-loopback-response
       (format nil
               "{\"model\":\"fixture-model\",\"response\":\"image-ready\",\"done\":true}~%")
       "application/x-ndjson"
       (lambda (client server)
         (let ((events nil))
           (generate-stream client
                            "fixture-model"
                            "draw"
                            (lambda (event) (push event events))
                            :width 1024
                            :height 768
                            :steps 12)
           (let* ((request
                    (%assert-native-loopback-request server :post "/generate"))
                  (body (request-json-object request))
                  (event (first events)))
             (assert (equal "fixture-model" (gethash "model" body)))
             (assert (equal "draw" (gethash "prompt" body)))
             (assert (= 1024 (gethash "width" body)))
             (assert (= 768 (gethash "height" body)))
             (assert (= 12 (gethash "steps" body)))
             (assert (eq t (gethash "stream" body)))
             (assert (= 1 (length events)))
             (assert (hash-table-p event))
             (assert (equal "image-ready" (gethash "response" event)))
             (assert (eq t (gethash "done" event))))))))

    (it "parses a native chat completion"
      (%call-with-native-loopback-response
       "{\"model\":\"fixture-model\",\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"done\":true}"
       "application/json"
       (lambda (client server)
         (let* ((value
                  (chat client
                        "fixture-model"
                        (list (make-message "user" "hello"))))
                (request (%assert-native-loopback-request server :post "/chat"))
                (body (request-json-object request))
                (message (gethash "message" value))
                (messages (gethash "messages" body)))
           (assert (equal "fixture-model" (gethash "model" body)))
           (assert (= 1 (length messages)))
           (assert (equal "user" (gethash "role" (aref messages 0))))
           (assert (equal "hello" (gethash "content" (aref messages 0))))
           (assert (eq json-kit:+json-false+ (gethash "stream" body)))
           (assert (equal "assistant" (gethash "role" message)))
           (assert (equal "Hello" (gethash "content" message)))
           (assert (eq t (gethash "done" value)))))))

    (it "delivers ordered native chat events"
      (%call-with-native-loopback-response
       (format nil
               "{\"model\":\"fixture-model\",\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"done\":false}~%{\"model\":\"fixture-model\",\"message\":{\"role\":\"assistant\",\"content\":\".\"},\"done\":true}~%")
       "application/x-ndjson"
       (lambda (client server)
         (let ((events nil))
           (chat-stream client
                        "fixture-model"
                        (list (make-message "user" "hello"))
                        (lambda (event) (push event events)))
           (let* ((request (%assert-native-loopback-request server :post "/chat"))
                  (body (request-json-object request))
                  (messages (gethash "messages" body))
                  (ordered-events (nreverse events))
                  (first-message (gethash "message" (first ordered-events)))
                  (last-message (gethash "message" (second ordered-events))))
             (assert (equal "fixture-model" (gethash "model" body)))
             (assert (vectorp messages))
             (assert (= 1 (length messages)))
             (assert (equal "user" (gethash "role" (aref messages 0))))
             (assert (equal "hello" (gethash "content" (aref messages 0))))
             (assert (eq t (gethash "stream" body)))
             (assert (= 2 (length ordered-events)))
             (assert (equal "Hello" (gethash "content" first-message)))
             (assert (equal "." (gethash "content" last-message)))
             (assert (eq json-kit:+json-false+
                         (gethash "done" (first ordered-events))))
             (assert (eq t (gethash "done" (second ordered-events)))))))))

    (it "parses native model details from the show endpoint"
      (%call-with-native-loopback-response
       "{\"modelfile\":\"FROM fixture-model\",\"parameters\":\"temperature 0.7\",\"template\":\"fixture-template\",\"details\":{\"format\":\"gguf\"}}"
       "application/json"
       (lambda (client server)
         (let* ((value (show-model client "fixture-model"))
                (request (%assert-native-loopback-request server :post "/show"))
                (body (request-json-object request))
                (details (gethash "details" value)))
           (assert (equal "fixture-model" (gethash "model" body)))
           (multiple-value-bind (verbose present-p) (gethash "verbose" body)
             (declare (ignore verbose))
             (assert (not present-p)))
           (assert (equal "FROM fixture-model" (gethash "modelfile" value)))
           (assert (equal "temperature 0.7" (gethash "parameters" value)))
           (assert (equal "gguf" (gethash "format" details)))))))

    (it "copies a model through the native endpoint"
      (%call-with-native-loopback-response
       "{\"status\":\"success\",\"model\":\"destination\"}"
       "application/json"
       (lambda (client server)
         (let* ((value (copy-model client "source" "destination"))
                (request (%assert-native-loopback-request server :post "/copy"))
                (body (request-json-object request)))
           (assert (equal "source" (gethash "source" body)))
           (assert (equal "destination" (gethash "destination" body)))
           (assert (equal "success" (gethash "status" value)))
           (assert (equal "destination" (gethash "model" value)))))))

    (it "deletes a model through the native endpoint"
      (%call-with-native-loopback-response
       "{\"deleted\":true}"
       "application/json"
       (lambda (client server)
         (let* ((value (delete-model client "fixture-model"))
                (request (%assert-native-loopback-request server :delete "/delete"))
                (body (request-json-object request)))
           (assert (equal "fixture-model" (gethash "model" body)))
           (assert (eq t (gethash "deleted" value)))))))

    (it-each
     ((pull-model "/pull" "registry.example/fixture:latest")
      (push-model "/push" "registry.example/fixture:latest"))
     "sends a non-streaming ~A request and decodes its status"
     (operation path model)
     (%call-with-native-loopback-response
      "{\"status\":\"success\",\"completed\":12}"
      "application/json"
      (lambda (client server)
        (let* ((value (funcall operation client model))
               (request (%assert-native-loopback-request server :post path))
               (body (request-json-object request)))
          (assert (equal model (gethash "model" body)))
          (assert (eq json-kit:+json-false+ (gethash "stream" body)))
          (assert (equal "success" (gethash "status" value)))
          (assert (= 12 (gethash "completed" value)))))))

    (it "sends create renderer and parser options"
      (%call-with-native-loopback-response
       "{\"status\":\"success\",\"model\":\"custom\"}"
       "application/json"
       (lambda (client server)
         (let* ((value
                  (create-model client "custom" :renderer "ggml" :parser "json"))
                (request (%assert-native-loopback-request server :post "/create"))
                (body (request-json-object request)))
           (assert (equal "custom" (gethash "model" body)))
           (assert (equal "ggml" (gethash "renderer" body)))
           (assert (equal "json" (gethash "parser" body)))
           (assert (eq json-kit:+json-false+ (gethash "stream" body)))
           (assert (equal "success" (gethash "status" value)))
           (assert (equal "custom" (gethash "model" value)))))))

    (it-each
     ((create-model-stream "/create" "custom")
      (pull-model-stream "/pull" "registry.example/fixture:latest")
      (push-model-stream "/push" "registry.example/fixture:latest"))
     "delivers ordered ~A status events"
     (operation path model)
     (%call-with-native-loopback-response
      (format nil
              "{\"status\":\"starting\",\"digest\":\"sha256:first\",\"completed\":1}~%{\"status\":\"success\",\"digest\":\"sha256:second\",\"completed\":2}~%")
      "application/x-ndjson"
      (lambda (client server)
        (let ((events nil))
          (funcall operation client model (lambda (event) (push event events)))
          (let* ((request (%assert-native-loopback-request server :post path))
                 (body (request-json-object request))
                 (ordered-events (nreverse events)))
            (assert (equal model (gethash "model" body)))
            (assert (eq t (gethash "stream" body)))
            (assert (= 2 (length ordered-events)))
            (assert (equal '("starting" "success")
                           (mapcar (lambda (event) (gethash "status" event))
                                   ordered-events)))
            (assert (equal "sha256:first"
                           (gethash "digest" (first ordered-events))))
            (assert (equal "sha256:second"
                           (gethash "digest" (second ordered-events))))
            (assert (= 2 (gethash "completed" (second ordered-events)))))))))

    (it "distinguishes omitted message fields from supplied JSON null"
      (let ((message
              (make-message "user" "hello" :name json-kit:+json-null+)))
        (multiple-value-bind (name present-p) (gethash "name" message)
          (assert present-p)
          (assert (eq json-kit:+json-null+ name)))
        (multiple-value-bind (thinking present-p) (gethash "thinking" message)
          (declare (ignore thinking))
          (assert (not present-p)))))))
