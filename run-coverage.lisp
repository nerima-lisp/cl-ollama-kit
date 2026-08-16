(require :asdf)

(let* ((working-directory (uiop:ensure-directory-pathname (uiop:getcwd)))
       (entry-directory
        (uiop:pathname-directory-pathname
         (or *load-truename* *load-pathname* working-directory)))
       (support
        (or
         (let ((candidate
                (merge-pathnames "run-support.lisp" working-directory)))
           (and (probe-file candidate) candidate))
         (merge-pathnames "run-support.lisp" entry-directory))))
  (load support))

#+sbcl
(progn
  (require :sb-cover)
  (let ((policy (find-symbol "STORE-COVERAGE-DATA" "SB-COVER")))
    (unless policy
      (error "SB-COVER compiler policy is not available."))
    (proclaim `(optimize (,policy 3)))))

(defun ensure-non-empty-file (pathname description)
  (unless
      (and (probe-file pathname)
           (with-open-file
               (stream pathname
                       :direction
                       :input
                       :element-type
                       '(unsigned-byte 8))
             (plusp (file-length stream))))
    (error "Coverage ~A is missing or empty: ~A" description pathname)))

(defun ensure-non-empty-report (directory)
  (unless (and (probe-file directory) (uiop:directory-files directory))
    (error "Coverage report directory is missing or empty: ~A" directory)))

(defun coverage-directory ()
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "CL_OLLAMA_KIT_COVERAGE_DIRECTORY")
       (merge-pathnames
        (format nil
                "cl-ollama-kit-~D-~D/"
                (get-universal-time)
                (random 1000000000))
        (uiop:temporary-directory)))))

(defun declarative-coverage-exclusions (source-directory)
  "Return source files whose forms are evaluated while ASDF loads the system.

CL-WEAVE starts its public coverage session around the test runner, after
ASDF has loaded the system.  These files contain only package, condition,
structure, and constant declarations; executable implementation files remain
in the measured source set."
  (mapcar
   (lambda (name)
     (merge-pathnames name source-directory))
   '("package.lisp" "conditions.lisp" "data-model.lisp")))

(defun ensure-positive-coverage-targets (include-pathnames exclude-pathnames)
  (let ((statistics
         (uiop:symbol-call '#:cl-weave
                           '#:coverage-statistics
                           :include-pathnames
                           include-pathnames
                           :exclude-pathnames
                           exclude-pathnames)))
    (dolist (key '(:expression-total :branch-total))
      (unless (plusp (getf statistics key))
        (error "Coverage target ~A is empty: ~S" key statistics)))
    (format t "~&Coverage statistics: ~S~%" statistics)
    statistics))

(let* ((root (project-directory))
       (source-directory (merge-pathnames "src/" root))
       (output-directory (coverage-directory))
       (coverage-output (merge-pathnames "coverage.data" output-directory))
       (report-directory (merge-pathnames "report/" output-directory))
       (coverage-exclusions (declarative-coverage-exclusions source-directory))
       (coverage-includes (list source-directory)))
  (configure-local-source-registry root :include-test-dependencies t)
  (ensure-directories-exist coverage-output)
  ;; SB-COVER records forms when their FASLs are compiled under the policy.
  ;; Compile explicitly before loading so a stale, non-instrumented ASDF
  ;; artifact cannot make the report vacuously empty.
  (unless (asdf:compile-system "cl-ollama-kit" :force t)
    (error "Unable to compile cl-ollama-kit for coverage"))
  (unless (asdf:load-system "cl-ollama-kit/test")
    (error "Unable to load cl-ollama-kit/test"))
  (format t "~&Coverage artifacts: ~A~%" output-directory)
  (uiop:symbol-call '#:ollama-kit/test '#:run-tests
                    :coverage t
                    :coverage-output coverage-output
                    :coverage-report-directory report-directory
                    :coverage-include-pathnames coverage-includes
                    :coverage-exclude-pathnames coverage-exclusions
                    :coverage-minimum-expression 100
                    :coverage-minimum-branch 100
                    ;; Keep counters collected while the instrumented system
                    ;; is compiled and loaded.  The public cl-weave runner
                    ;; starts after ASDF loading, so resetting here would
                     ;; erase macro-expansion and compile-time coverage.
                     :coverage-reset nil)
  (ensure-positive-coverage-targets coverage-includes coverage-exclusions)
  (ensure-non-empty-file coverage-output "data")
  (ensure-non-empty-report report-directory)
  (uiop:quit 0))
