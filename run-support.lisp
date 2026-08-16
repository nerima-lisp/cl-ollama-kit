(require :asdf)

(defparameter *cl-ollama-kit-script-directory*
  (uiop:pathname-directory-pathname
   (or *load-truename* *load-pathname* (uiop:getcwd))))

(defun script-directory ()
  *cl-ollama-kit-script-directory*)

(defun project-directory ()
  (let ((working-directory
          (uiop:ensure-directory-pathname (uiop:getcwd))))
    ;; cl-nix-forge executes an entry point from its store path while
    ;; retaining the unpacked project as the working directory.
    (if (probe-file (merge-pathnames "cl-ollama-kit.asd" working-directory))
        working-directory
        (script-directory))))

(defun local-system-directories (root systems)
  (let* ((parents
          (list (merge-pathnames "../" root)
                (merge-pathnames "../../" root)
                (merge-pathnames "../../../" root)))
         (directories
          (loop for parent in parents
                append (loop for system in systems
                             for directory = (merge-pathnames
                                              (format nil "~A/" system)
                                              parent)
                             when (probe-file
                                   (merge-pathnames (format nil "~A.asd" system)
                                                    directory))
                               collect directory))))
    (remove-duplicates directories :test #'equal)))

(defun configure-local-source-registry (root &key include-test-dependencies)
  (let ((systems
         (append
          '("cl-boundary-kit" "cl-codec-kit" "cl-concurrent-kit" "cl-json-kit")
          (when include-test-dependencies
            '("cl-weave" "cl-sse-kit")))))
    (asdf:initialize-source-registry
     `(:source-registry (:directory ,root)
                        ,@(mapcar
                           (lambda (directory)
                             `(:directory ,directory))
                           (local-system-directories root systems))
                        :inherit-configuration))))
