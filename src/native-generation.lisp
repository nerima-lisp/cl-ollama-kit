(define-native-stream-pair generate
                           generate-stream
                           (client model
                                   prompt
                                   &key
                                   (suffix +json-unspecified+)
                                   (images +json-unspecified+)
                                   (format +json-unspecified+)
                                   (options +json-unspecified+)
                                   (system +json-unspecified+)
                                   (template +json-unspecified+)
                                   (context +json-unspecified+)
                                   (raw +json-unspecified+)
                                   (think +json-unspecified+)
                                   (width +json-unspecified+)
                                   (height +json-unspecified+)
                                   (steps +json-unspecified+)
                                   (keep-alive +json-unspecified+)
                                   (logprobs +json-unspecified+)
                                   (top-logprobs +json-unspecified+)
                                   (timeout +timeout-unspecified+)
                                   headers)
                           :post
                           "/generate"
                           (lambda (stream-p)
                             (%native-body (cons "model" model)
                                           (cons "prompt" prompt)
                                           (%optional-json-pair "suffix" suffix)
                                           (%optional-json-pair "images"
                                                                images
                                                                #'%json-array)
                                           (%optional-json-pair "format"
                                                                format
                                                                #'%native-enum)
                                           (%optional-json-pair "options"
                                                                options)
                                           (%optional-json-pair "system" system)
                                           (%optional-json-pair "template"
                                                                template)
                                           (%optional-json-pair "context"
                                                                context
                                                                #'%json-array)
                                           (%optional-json-pair "raw"
                                                                raw
                                                                #'%native-bool)
                                           (%optional-json-pair "think"
                                                                think
                                                                #'%native-think)
                                           (%optional-json-pair "width" width)
                                           (%optional-json-pair "height" height)
                                           (%optional-json-pair "steps" steps)
                                           (%optional-json-pair "keep_alive"
                                                                keep-alive)
                                           (%optional-json-pair "logprobs"
                                                                logprobs
                                                                #'%native-bool)
                                           (%optional-json-pair "top_logprobs"
                                                                top-logprobs)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Generate a completion through Ollama's native `/api/generate` endpoint.

An omitted keyword is different from an explicitly supplied NIL value.  Use
JSON-KIT:+JSON-NULL+ when the JSON null value itself is required.  The
experimental image-generation controls WIDTH, HEIGHT, and STEPS are passed
through when supplied."
                           :stream-documentation
                           "Stream a completion through Ollama's native `/api/generate` endpoint.

WIDTH, HEIGHT, and STEPS are the experimental image-generation controls and
are passed through when supplied.")

(define-native-stream-pair chat
                           chat-stream
                           (client model
                                   messages
                                   &key
                                   (tools +json-unspecified+)
                                   (format +json-unspecified+)
                                   (options +json-unspecified+)
                                   (keep-alive +json-unspecified+)
                                   (think +json-unspecified+)
                                   (logprobs +json-unspecified+)
                                   (top-logprobs +json-unspecified+)
                                   (timeout +timeout-unspecified+)
                                   headers)
                           :post
                           "/chat"
                           (lambda (stream-p)
                             (%native-body (cons "model" model)
                                           (cons "messages"
                                                 (%json-array messages))
                                           (%optional-json-pair "tools"
                                                                tools
                                                                #'%json-array)
                                           (%optional-json-pair "format"
                                                                format
                                                                #'%native-enum)
                                           (%optional-json-pair "options"
                                                                options)
                                           (%optional-json-pair "keep_alive"
                                                                keep-alive)
                                           (%optional-json-pair "think"
                                                                think
                                                                #'%native-think)
                                           (%optional-json-pair "logprobs"
                                                                logprobs
                                                                #'%native-bool)
                                           (%optional-json-pair "top_logprobs"
                                                                top-logprobs)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Create a chat completion through Ollama's native `/api/chat` endpoint."
                           :stream-documentation
                           "Stream a chat completion through Ollama's native `/api/chat` endpoint.")

(defun %native-embed-input (input)
  (cond
    ((stringp input) input)
    ((and (or (listp input) (vectorp input)) (every #'stringp input))
     (%json-array input))
    (t
     (error 'ollama-argument-error
            :message
            "Embedding input must be a string or a sequence of strings."
            :detail
            (type-of input)))))

(defun %native-embed-dimensions (value)
  (unless (integerp value)
    (error 'ollama-argument-error
           :message
           "Embedding dimensions must be an integer."
           :detail
           value))
  value)

(defun %native-embed-keep-alive (value)
  (unless (stringp value)
    (error 'ollama-argument-error
           :message
           "Embedding keep-alive must be a duration string."
           :detail
           value))
  value)

(define-native-json-endpoint embed
                             (client model
                                     input
                                     &key
                                     (truncate +json-unspecified+)
                                     (dimensions +json-unspecified+)
                                     (options +json-unspecified+)
                                     (keep-alive +json-unspecified+)
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/embed"
                             :body-form
                             (%native-body (cons "model" model)
                                           (cons "input"
                                                 (%native-embed-input input))
                                           (%optional-json-pair "truncate"
                                                                truncate
                                                                #'%native-bool)
                                           (%optional-json-pair "dimensions"
                                                                dimensions
                                                                #'%native-embed-dimensions)
                                           (%optional-json-pair "options"
                                                                options)
                                           (%optional-json-pair "keep_alive"
                                                                keep-alive
                                                                #'%native-embed-keep-alive))
                             :documentation
                             "Create embeddings through Ollama's JSON-only native `/api/embed` endpoint.

INPUT is a string or a list/vector of strings.  DIMENSIONS must be an integer
and KEEP-ALIVE must be a duration string when supplied.")
