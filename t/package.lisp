(defpackage #:ollama-kit/test
  (:use #:cl #:ollama-kit)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it #:it-each #:it-property #:it-fuzz #:gen-integer #:expect #:run-all
                #:with-continuation-values #:with-soft-assertions)
  (:export #:run-tests))

(in-package #:ollama-kit/test)

(defun run-tests (&key coverage coverage-output coverage-report-directory
                    coverage-include-pathnames coverage-exclude-pathnames
                    coverage-minimum-expression coverage-minimum-branch
                    (coverage-reset t))
  "Run the complete cl-ollama-kit specification suite."
  (unless (run-all :reporter :spec
                   :pass-with-no-tests nil
                   :timeout-ms 10000
                   :coverage coverage
                   :coverage-output coverage-output
                   :coverage-report-directory coverage-report-directory
                   :coverage-include-pathnames coverage-include-pathnames
                   :coverage-exclude-pathnames coverage-exclude-pathnames
                   :coverage-minimum-expression coverage-minimum-expression
                   :coverage-minimum-branch coverage-minimum-branch
                   :coverage-reset coverage-reset)
    (error "cl-ollama-kit test suite failed"))
  (format t "~&cl-ollama-kit/test: successful completion with 0 failures~%")
  t)

(defun response (body &key (status 200) (stream nil))
  (make-http-response
   :status status
   :headers `(("content-type" . "application/json"))
   :body (if stream nil body)
   :stream stream))

(defun response-with-text (text &key (status 200))
  (response (cl-codec-kit:string-to-octets text :encoding :utf-8)
            :status status))

(defun queued-client (&rest responses)
  (make-client
   :network-boundary
   (cl-boundary-kit:make-test-network-boundary :responses responses)))

(defun client-with-request-function (request-fn &rest options)
  (apply #'make-client
         :network-boundary
         (cl-boundary-kit:make-network-boundary :request-fn request-fn)
         options))

(defun openai-client-with-request-function (request-fn &rest options)
  (apply #'make-openai-client
         :network-boundary
         (cl-boundary-kit:make-network-boundary :request-fn request-fn)
         options))
