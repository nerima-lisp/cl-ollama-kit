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
  '(:base-url :network-boundary
              :headers
              :api-key
              :timeout
              :max-input-length
              :max-request-length
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
                         network-boundary
                         headers
                         timeout
                         max-input-length
                         max-request-length
                         api-key-p
                         allow-insecure-http)))
  "Configuration and transport boundary for an Ollama client."
  (base-url +default-base-url+ :type string)
  network-boundary
  headers
  timeout
  (max-input-length 16777216 :type (integer 1 *))
  (max-request-length 16777216 :type (integer 1 *))
  api-key-p
  allow-insecure-http)

(defparameter +json-unspecified+
  (gensym "JSON-UNSPECIFIED-"))

(defparameter +timeout-unspecified+
  (gensym "TIMEOUT-UNSPECIFIED-"))

(defstruct
    (http-request
     (:constructor %make-http-request (&key method url headers body stream-p)))
  "An opaque, transport-independent HTTP request."
  method
  (url "" :type string)
  headers
  body
  stream-p)

(defstruct
    (http-response
     (:constructor %make-http-response
                   (&key status headers body stream close-function)))
  "A response returned by a CL-BOUNDARY-KIT network boundary.

BODY is normally a string or an octet vector.  STREAM is used for a response
whose body must be consumed incrementally."
  status
  headers
  body
  stream
  close-function)

(defstruct
    (ollama-stream
     (:constructor %make-ollama-stream
                   (&key stream
                         response
                         close-function
                         wire-format
                         max-line-length)))
  stream
  response
  close-function
  (wire-format :ndjson)
  (closed-p nil)
  (max-line-length 16777216)
  (line-number 0))

(defparameter +max-sse-event-lines+
  65536
  "Maximum number of wire lines allowed in one pending SSE event.")
