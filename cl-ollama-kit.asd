(in-package #:asdf-user)

(asdf:defsystem "cl-ollama-kit"
  :description "A transport-independent Common Lisp client for the Ollama API."
  :author "nerima-lisp contributors"
  :maintainer "nerima-lisp contributors"
  :version "2.0.0"
  :license "MIT"
  :depends-on ((:version "cl-boundary-kit" "2.3.0")
               (:version "cl-codec-kit" "0.5.0")
               (:version "cl-concurrent-kit" "0.6.1")
               (:version "cl-json-kit" "1.2.0"))
  :pathname "src"
  :serial t
  ;; Compile serial source components in the library package once it exists.
  ;; The fallback keeps the initial package definition readable, while this
  ;; ASDF reader context avoids package-switch forms in every component.
  :around-compile (lambda (thunk)
                    (let ((*package* (or (find-package '#:ollama-kit)
                                         *package*)))
                      (funcall thunk)))
  :components ((:file "package")
               (:file "conditions")
               (:file "data-model")
               (:file "http-validation")
               (:file "input-limits")
               (:file "url-components")
               (:file "url-validation")
               (:file "model")
               (:file "http-model")
               (:file "json")
               (:file "http-encoding")
               (:file "http-decoding")
               (:file "transport")
               (:file "cps")
               (:file "stream-core")
               (:file "stream-parser")
               (:file "stream")
               (:file "native-macros")
               (:file "native-options")
               (:file "native-generation")
               (:file "native-models")
               (:file "native-blob")
               (:file "web-api")
               (:file "openai-api"))
  :in-order-to ((test-op (test-op "cl-ollama-kit/test"))))

(asdf:defsystem "cl-ollama-kit/test"
  :description "Tests for cl-ollama-kit."
  :depends-on ((:version "cl-ollama-kit" "2.0.0")
               (:version "cl-weave" "1.3.0"))
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "client-test")
               (:file "stream-test")
               (:file "api-test")
               (:file "coverage-test")
               (:file "data-contract-test")
               (:file "stream-edge-test")
               (:file "codec-edge-test")
               (:file "transport-edge-test")
               (:file "stream-parser-edge-test")
               (:file "property-test"))
  :perform (asdf:test-op (operation component)
             (declare (ignore operation component))
             (uiop:symbol-call '#:ollama-kit/test '#:run-tests)))
