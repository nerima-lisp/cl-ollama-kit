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

(defparameter +client-option-table+
  (list (list :http-client nil '%validate-client-http-client-option)
        ;; Bounds the entire HTTP exchange; response and idle timeouts are
        ;; the default guards.
        (list :timeout nil '%validate-client-timeout-option)
        (list :response-timeout 300 '%validate-client-timeout-option)
        (list :idle-timeout 120 '%validate-client-timeout-option)
        (list :allow-insecure-http nil '%validate-client-boolean-option)
        (list :api-key nil '%validate-client-api-key-option)
        (list :max-input-length 16777216 '%validate-client-limit-option)
        (list :max-request-length 16777216 '%validate-client-limit-option)
        (list :headers nil '%validate-client-headers-option)
        (list :base-url +default-base-url+ '%validate-client-base-url-option)))

(defparameter +client-option-keys+
  (mapcar #'first +client-option-table+))

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
  (base-url (second (assoc :base-url +client-option-table+)) :type string)
  (http-client (second (assoc :http-client +client-option-table+)))
  (owned-http-client-p nil :type boolean)
  (headers (second (assoc :headers +client-option-table+)))
  (timeout (second (assoc :timeout +client-option-table+)))
  (response-timeout (second (assoc :response-timeout +client-option-table+)))
  (idle-timeout (second (assoc :idle-timeout +client-option-table+)))
  (max-input-length (second (assoc :max-input-length +client-option-table+))
                    :type
                    (integer 1 *))
  (max-request-length (second (assoc :max-request-length +client-option-table+))
                      :type
                      (integer 1 *))
  (api-key-p (not (null (second (assoc :api-key +client-option-table+)))))
  (allow-insecure-http
   (second (assoc :allow-insecure-http +client-option-table+))))

(defparameter +json-unspecified+
  (gensym "JSON-UNSPECIFIED-"))

(defparameter +timeout-unspecified+
  (gensym "TIMEOUT-UNSPECIFIED-"))
