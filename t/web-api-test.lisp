(in-package #:ollama-kit/test)

(describe "Ollama web API contracts"
  (it-each
   ((:search 3 nil)
    (:search 3 t)
    (:fetch 3 nil))
   "sends a ~A request with max-results supplied: ~A"
   (operation result-limit explicit-p)
   (let* ((response-body
            (if (eq operation :search)
                "{\"results\":[{\"title\":\"Common Lisp\",\"url\":\"https://lisp.example/result\",\"content\":\"Intro\"}]}"
                "{\"title\":\"API docs\",\"url\":\"https://example.com/docs\",\"content\":\"Page text\"}"))
          (server
            (make-loopback-http-server
             :headers
             (list (http-message-kit:make-http-header
                    "content-type"
                    "application/json"))
             :body
             (cl-codec-kit:string-to-octets response-body :encoding :utf-8)))
          (client
            (make-client
             :base-url
             (concatenate 'string (loopback-http-server-url server) "/api"))))
     (unwind-protect
          (let* ((value
                   (ecase operation
                     (:search
                      (if explicit-p
                          (web-search client "Common Lisp"
                                      :max-results result-limit)
                          (web-search client "Common Lisp")))
                     (:fetch
                      (web-fetch client "https://example.com/docs"))))
                 (request (loopback-http-server-request server))
                 (request-body (request-json-object request)))
            (assert (http-message-kit:http-request-p request))
            (assert (hash-table-p value))
            (assert (string-equal
                     "POST"
                     (http-message-kit:http-request-method request)))
            (assert
             (equal (if (eq operation :search)
                        "/api/web_search"
                        "/api/web_fetch")
                    (http-message-kit:http-request-target request)))
            (ecase operation
              (:search
               (assert (= (if explicit-p 2 1)
                          (hash-table-count request-body)))
               (assert (equal "Common Lisp"
                              (gethash "query" request-body)))
               (if explicit-p
                   (assert (= result-limit
                              (gethash "max_results" request-body)))
                   (assert (not (nth-value 1
                                           (gethash "max_results"
                                                    request-body)))))
               (let* ((results (gethash "results" value))
                      (result (and (vectorp results)
                                   (= 1 (length results))
                                   (aref results 0))))
                 (assert result)
                 (assert (equal "Common Lisp"
                                (gethash "title" result)))
                 (assert (equal "https://lisp.example/result"
                                (gethash "url" result)))
                 (assert (equal "Intro"
                                (gethash "content" result)))))
              (:fetch
               (assert (= 1 (hash-table-count request-body)))
               (assert (equal "https://example.com/docs"
                              (gethash "url" request-body)))
               (assert (equal "API docs" (gethash "title" value)))
               (assert (equal "https://example.com/docs"
                              (gethash "url" value)))
               (assert (equal "Page text" (gethash "content" value))))))
       (close-client client))))
  (it "rejects invalid web search and fetch arguments"
    (let ((client (make-client)))
      (unwind-protect
           (dolist
               (thunk
                 (list
                  (lambda () (web-search client nil))
                  (lambda () (web-search client "query" :max-results 0))
                  (lambda () (web-search client "query" :max-results 11))
                  (lambda () (web-search client "query" :max-results "3"))
                  (lambda () (web-fetch client nil))))
             (handler-case
                 (progn
                   (funcall thunk)
                   (assert nil))
               (ollama-argument-error () t)))
        (close-client client)))))
