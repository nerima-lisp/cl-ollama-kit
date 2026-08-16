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

(let ((root (project-directory)))
  (configure-local-source-registry root :include-test-dependencies t)
  (asdf:test-system "cl-ollama-kit/test")
  (uiop:quit 0))
