(require :asdf)

(defun script-directory ()
  (uiop:pathname-directory-pathname
   (or *load-truename* *load-pathname* (uiop:getcwd))))

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

(let ((root (script-directory)))
  (configure-local-source-registry root)
  (asdf:test-system "cl-ollama-kit/test")
  (uiop:quit 0))
