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
  ;; Nix dependency sources are read-only; compile FASLs under this build's writable directory.
  (let ((translations (uiop:getenv "ASDF_OUTPUT_TRANSLATIONS")))
    (when (and (uiop:getenv "NIX_BUILD_TOP")
               (or (not translations) (string= translations "/:/")))
      (let* ((build-top
               (uiop:ensure-directory-pathname
                (uiop:getenv "NIX_BUILD_TOP")))
             (fasl-root
               (merge-pathnames "cl-ollama-kit-fasl/" build-top)))
        (ensure-directories-exist
         (merge-pathnames "placeholder" fasl-root))
        (asdf:initialize-output-translations
         `(:output-translations
           (t (,fasl-root :implementation))
           :ignore-inherited-configuration)))))
  ;; Nix supplies the pinned dependency registry; keep sibling discovery for standalone runs.
  (unless (uiop:getenv "CL_SOURCE_REGISTRY")
    (let ((systems
           (append
            '("cl-boundary-kit"
              "cl-codec-kit"
              "cl-concurrent-kit"
              "cl-crypto-kit"
              "cl-date-kit"
              "cl-deflate-kit"
              "cl-host-kit"
              "cl-hpack-codec-kit"
              "cl-http-kit"
              "cl-http-message-kit"
              "cl-json-kit"
              "cl-resilience-kit"
              "cl-sse-kit"
              "cl-tls-kit")
            (when include-test-dependencies
              '("cl-weave" "cl-sse-kit")))))
      (asdf:initialize-source-registry
       `(:source-registry (:directory ,root)
                          ,@(mapcar
                             (lambda (directory)
                               `(:directory ,directory))
                             (local-system-directories root systems))
                          :inherit-configuration)))))
