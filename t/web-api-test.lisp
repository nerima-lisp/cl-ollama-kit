(in-package #:ollama-kit/test)

(describe "Ollama web API contracts"
          (it "posts search and fetch requests with the documented payloads"
              (let* ((captured (list nil))
                     (client
                      (client-with-request-function
                       (lambda (request &key timeout)
                         (declare (ignore timeout))
                         (setf (car captured) request)
                         (response-with-text "{}")))))
                (let ((value (web-search client "Common Lisp" :max-results 3)))
                  (assert (http-request-p (car captured)))
                  (let ((body (request-json-object (car captured))))
                    (assert (hash-table-p value))
                    (assert (eq :post (http-request-method (car captured))))
                    (assert
                     (search "/api/web_search"
                             (http-request-url (car captured))))
                    (assert (equal "Common Lisp" (gethash "query" body)))
                    (assert (= 3 (gethash "max_results" body)))))
                (let ((value (web-fetch client "https://example.com/docs")))
                  (assert (http-request-p (car captured)))
                  (let ((body (request-json-object (car captured))))
                    (assert (hash-table-p value))
                    (assert (eq :post (http-request-method (car captured))))
                    (assert
                     (search "/api/web_fetch" (http-request-url (car captured))))
                    (assert
                     (equal "https://example.com/docs" (gethash "url" body)))))))
          (it "rejects invalid web search and fetch arguments"
              (let ((client
                     (client-with-request-function
                      (lambda (request &key timeout)
                        (declare (ignore request timeout))
                        (response-with-text "{}")))))
                (dolist
                    (thunk
                     (list
                      (lambda ()
                        (web-search client nil))
                      (lambda ()
                        (web-search client "query" :max-results 0))
                      (lambda ()
                        (web-search client "query" :max-results 11))
                      (lambda ()
                        (web-search client "query" :max-results "3"))
                      (lambda ()
                        (web-fetch client nil))))
                  (handler-case (progn
                                  (funcall thunk)
                                  (assert nil))
                    (ollama-argument-error ()
                      t))))))
