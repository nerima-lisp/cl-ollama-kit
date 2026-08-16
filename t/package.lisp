(defpackage #:ollama-kit/test
            (:use #:cl #:ollama-kit)
            (:shadowing-import-from #:cl-weave #:describe)
            (:import-from #:cl-weave
                          #:it
                          #:it-each
                          #:it-property
                          #:it-fuzz
                          #:gen-integer
                          #:expect
                          #:run-all
                          #:with-continuation-values
                          #:with-soft-assertions)
            (:export #:run-tests))

(in-package #:ollama-kit/test)

(defun run-tests (&key (reporter :spec)
                       (stream *standard-output*)
                       name-filter
                       location-filter
                       test-path-filter
                       include-tags
                       exclude-tags
                       shard
                       order
                       seed
                       bail
                       retry
                       (timeout-ms 10000)
                       max-workers
                       coverage
                       coverage-output
                       coverage-report-directory
                       coverage-include-pathnames
                       coverage-exclude-pathnames
                       coverage-minimum-expression
                       coverage-minimum-branch
                       (pass-with-no-tests nil)
                       (coverage-reset t))
  "Run the complete cl-ollama-kit specification suite."
  (unless
      (run-all :reporter
               reporter
               :stream
               stream
               :name-filter
               name-filter
               :location-filter
               location-filter
               :test-path-filter
               test-path-filter
               :include-tags
               include-tags
               :exclude-tags
               exclude-tags
               :shard
               shard
               :order
               order
               :seed
               seed
               :bail
               bail
               :retry
               retry
               :timeout-ms
               timeout-ms
               :max-workers
               max-workers
               :pass-with-no-tests
               pass-with-no-tests
               :coverage
               coverage
               :coverage-output
               coverage-output
               :coverage-report-directory
               coverage-report-directory
               :coverage-include-pathnames
               coverage-include-pathnames
               :coverage-exclude-pathnames
               coverage-exclude-pathnames
               :coverage-minimum-expression
               coverage-minimum-expression
               :coverage-minimum-branch
               coverage-minimum-branch
               :coverage-reset
               coverage-reset)
    (error "cl-ollama-kit test suite failed"))
  (format stream
          "~&cl-ollama-kit/test: successful completion with 0 failures~%")
  t)
