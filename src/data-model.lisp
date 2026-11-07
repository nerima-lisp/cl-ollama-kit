#.(progn (in-package :ollama-kit) nil)

(defparameter +default-base-url+
  "http://localhost:11434/api"
  "The default native API endpoint used by MAKE-CLIENT.")

(defparameter +openai-default-base-url+
  "http://localhost:11434/v1"
  "The default OpenAI-compatible endpoint used by MAKE-OPENAI-CLIENT.")

(defparameter +anthropic-default-base-url+
  "http://localhost:11434/v1"
  "The default Anthropic-compatible endpoint used by MAKE-ANTHROPIC-CLIENT.")

(defparameter +client-option-keys+
  '(:base-url :http-client :headers :api-key
              :timeout :response-timeout :idle-timeout
              :max-input-length :max-request-length
              :allow-insecure-http))


(defparameter +standard-http-methods+
  '(("ACL" . :acl) ("BASELINE-CONTROL" . :baseline-control)
                   ("BIND" . :bind)
                   ("CHECKIN" . :checkin)
                   ("CONNECT" . :connect)
                   ("COPY" . :copy)
                   ("DELETE" . :delete)
                   ("GET" . :get)
                   ("HEAD" . :head)
                   ("LABEL" . :label)
                   ("LINK" . :link)
                   ("LOCK" . :lock)
                   ("MERGE" . :merge)
                   ("MKACTIVITY" . :mkactivity)
                   ("MKCALENDAR" . :mkcalendar)
                   ("MKCOL" . :mkcol)
                   ("MOVE" . :move)
                   ("M-SEARCH" . :m-search)
                   ("NOTIFY" . :notify)
                   ("OPTIONS" . :options)
                   ("PATCH" . :patch)
                   ("POST" . :post)
                   ("PRI" . :pri)
                   ("PROPFIND" . :propfind)
                   ("PROPPATCH" . :proppatch)
                   ("PURGE" . :purge)
                   ("PUT" . :put)
                   ("REBIND" . :rebind)
                   ("REPORT" . :report)
                   ("SEARCH" . :search)
                   ("SUBSCRIBE" . :subscribe)
                   ("TRACE" . :trace)
                   ("UNBIND" . :unbind)
                   ("UNLINK" . :unlink)
                   ("UNLOCK" . :unlock)
                   ("UNMERGE" . :unmerge)
                   ("UPDATE" . :update)
                   ("VERSION-CONTROL" . :version-control))
  "Known HTTP methods mapped to stable keyword values.

Unknown extension methods remain strings so untrusted method names never
become dynamically interned keywords.")

(defstruct
    (client
     (:constructor %make-client
                   (&key base-url
                         http-client
                         owned-http-client-p
                         headers
                         timeout
                         response-timeout
                         idle-timeout
                         max-input-length
                         max-request-length
                         api-key-p
                         allow-insecure-http)))
  "Configuration and transport client for an Ollama client."
  (base-url +default-base-url+ :type string)
  http-client
  (owned-http-client-p nil :type boolean)
  headers
  timeout
  (response-timeout 300)
  (idle-timeout 120)
  (max-input-length 16777216 :type (integer 1 *))
  (max-request-length 16777216 :type (integer 1 *))
  api-key-p
  allow-insecure-http)


(defparameter +json-unspecified+
  (gensym "JSON-UNSPECIFIED-"))

(defparameter +timeout-unspecified+
  (gensym "TIMEOUT-UNSPECIFIED-"))

