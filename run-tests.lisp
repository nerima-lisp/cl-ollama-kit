(require :asdf)

(defun script-directory ()
  (uiop:pathname-directory-pathname
   (or *load-truename* *load-pathname* (uiop:getcwd))))

(defun configure-local-source-registry (root)
  (let ((parent (merge-pathnames "../" root)))
    (let ((local-directories
            (loop for dependency in '("cl-boundary-kit/"
                                      "cl-codec-kit/"
                                      "cl-concurrent-kit/"
                                      "cl-json-kit/"
                                      "cl-weave/")
                  for directory = (merge-pathnames dependency parent)
                  when (uiop:directory-exists-p directory)
                    collect `(:directory ,directory))))
    (asdf:initialize-source-registry
     `(:source-registry (:directory ,root)
       ,@local-directories
       :inherit-configuration)))))

(let ((root (script-directory)))
  (configure-local-source-registry root)
  (unless (and (asdf:find-system "cl-boundary-kit" nil)
               (asdf:find-system "cl-codec-kit" nil)
               (asdf:find-system "cl-concurrent-kit" nil)
               (asdf:find-system "cl-json-kit" nil)
               (asdf:find-system "cl-weave" nil))
    (error "Test dependencies are unavailable. Use the flake check or a Nix development shell."))
  (format t "~&Running cl-ollama-kit/test from ~A~%" root)
  (asdf:test-system "cl-ollama-kit/test")
  (format t "~&cl-ollama-kit/test completed successfully.~%")
  (uiop:quit 0))
