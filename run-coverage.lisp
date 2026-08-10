(require :asdf)

#+sbcl
(progn
  (require :sb-cover)
  (let ((policy (find-symbol "STORE-COVERAGE-DATA" "SB-COVER")))
    (unless policy
      (error "SB-COVER compiler policy is not available."))
    (proclaim `(optimize (,policy 3)))))

(defun project-directory ()
  (let* ((working-directory
           (uiop:ensure-directory-pathname (uiop:getcwd)))
         (load-directory
           (uiop:pathname-directory-pathname
            (or *load-truename* *load-pathname* working-directory))))
    ;; cl-nix-forge loads an entry point from its own store path while
    ;; executing it in the unpacked project tree.  Prefer that tree when it
    ;; contains this system; standalone local invocation still falls back to
    ;; the directory containing this script.
    (if (probe-file (merge-pathnames "cl-ollama-kit.asd" working-directory))
        working-directory
        load-directory)))

(defun configure-local-source-registry (root)
  (let ((parent (merge-pathnames "../" root)))
    (asdf:initialize-source-registry
     `(:source-registry
       (:directory ,root)
       (:directory ,(merge-pathnames "cl-boundary-kit/" parent))
       (:directory ,(merge-pathnames "cl-codec-kit/" parent))
       (:directory ,(merge-pathnames "cl-concurrent-kit/" parent))
       (:directory ,(merge-pathnames "cl-json-kit/" parent))
       (:directory ,(merge-pathnames "cl-weave/" parent))
       :inherit-configuration))))

(defun ensure-non-empty-file (pathname description)
  (unless (and (probe-file pathname)
               (with-open-file (stream pathname
                                       :direction :input
                                       :element-type '(unsigned-byte 8))
                 (plusp (file-length stream))))
    (error "Coverage ~A is missing or empty: ~A" description pathname)))

(defun ensure-non-empty-report (directory)
  (unless (and (probe-file directory)
               (uiop:directory-files directory))
    (error "Coverage report directory is missing or empty: ~A" directory)))

(defun coverage-directory ()
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "CL_OLLAMA_KIT_COVERAGE_DIRECTORY")
       (merge-pathnames
        (format nil "cl-ollama-kit-~D-~D/"
                (get-universal-time)
                (random 1000000000))
        (uiop:temporary-directory)))))

(defun declarative-coverage-exclusions (source-directory)
  "Return source files whose forms are evaluated while ASDF loads the system.

CL-WEAVE starts its public coverage session around the test runner, after
ASDF has loaded the system.  These files contain only package, condition,
structure, and constant declarations; executable implementation files remain
in the measured source set."
  (mapcar (lambda (name)
            (merge-pathnames name source-directory))
          '("package.lisp" "conditions.lisp" "data-model.lisp")))

(let* ((root (project-directory))
       (source-directory (merge-pathnames "src/" root))
       (output-directory (coverage-directory))
       (coverage-output (merge-pathnames "coverage.data" output-directory))
       (report-directory (merge-pathnames "report/" output-directory)))
  (configure-local-source-registry root)
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
                    :coverage-include-pathnames (list source-directory)
                    :coverage-exclude-pathnames
                    (declarative-coverage-exclusions source-directory)
                    :coverage-minimum-expression 100
                    :coverage-minimum-branch 100
                    ;; Keep counters collected while the instrumented system
                    ;; is compiled and loaded.  The public cl-weave runner
                    ;; starts after ASDF loading, so resetting here would
                    ;; erase macro-expansion and compile-time coverage.
                    :coverage-reset nil)
  (ensure-non-empty-file coverage-output "data")
  (ensure-non-empty-report report-directory)
  (uiop:quit 0))
