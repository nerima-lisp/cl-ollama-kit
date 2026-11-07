#.(progn (in-package :ollama-kit) nil)

(define-json-endpoint %request-json-value
                      list-models
                      (client &key (timeout +timeout-unspecified+) headers)
                      :get
                      "/tags"
                      :documentation
                      "List locally available models.")

(define-json-endpoint %request-json-value
                      list-running-models
                      (client &key (timeout +timeout-unspecified+) headers)
                      :get
                      "/ps"
                      :documentation
                      "List models currently loaded in memory.")

(define-json-endpoint %request-json-value
                      show-model
                      (client model
                              &key
                              (verbose +json-unspecified+)
                              (timeout +timeout-unspecified+)
                              headers)
                      :post
                      "/show"
                      :body-form
                      (%json-object (cons "model" model)
                                    (%optional-json-pair "verbose"
                                                         verbose
                                                         #'%native-bool))
                      :documentation
                      "Return details for MODEL.")

(define-native-stream-pair create-model
                           create-model-stream
                           (client model
                                   &key
                                   (from +json-unspecified+)
                                   (files +json-unspecified+)
                                   (adapters +json-unspecified+)
                                   (template +json-unspecified+)
                                   (license +json-unspecified+)
                                   (system +json-unspecified+)
                                   (parameters +json-unspecified+)
                                   (messages +json-unspecified+)
                                   (quantize +json-unspecified+)
                                   (renderer +json-unspecified+)
                                   (parser +json-unspecified+)
                                   (timeout +timeout-unspecified+)
                                   headers)
                           :post
                           "/create"
                           (lambda (stream-p)
                             (%json-object (cons "model" model)
                                           (%optional-json-pair "from" from)
                                           (%optional-json-pair "files" files)
                                           (%optional-json-pair "adapters"
                                                                adapters)
                                           (%optional-json-pair "template"
                                                                template)
                                           (%optional-json-pair "license"
                                                                license
                                                                #'%json-array)
                                           (%optional-json-pair "system" system)
                                           (%optional-json-pair "parameters"
                                                                parameters)
                                           (%optional-json-pair "messages"
                                                                messages
                                                                #'%json-array)
                                           (%optional-json-pair "quantize"
                                                                quantize
                                                                #'%json-enum)
                                           (%optional-json-pair "renderer"
                                                                renderer)
                                           (%optional-json-pair "parser" parser)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Create a model through Ollama's native `/api/create` endpoint."
                           :stream-documentation
                           "Stream model creation status events.")

(define-json-endpoint %request-json-value
                      copy-model
                      (client source
                              destination
                              &key
                              (timeout +timeout-unspecified+)
                              headers)
                      :post
                      "/copy"
                      :body-form
                      (%json-object (cons "source" source)
                                    (cons "destination" destination))
                      :documentation
                      "Copy SOURCE to DESTINATION.")

(define-json-endpoint %request-json-value
                      delete-model
                      (client model
                              &key
                              (timeout +timeout-unspecified+)
                              headers)
                      :delete
                      "/delete"
                      :body-form
                      (%json-object (cons "model" model))
                      :documentation
                      "Delete MODEL.")

(define-native-stream-pair pull-model
                           pull-model-stream
                           (client model
                                   &key
                                   (insecure +json-unspecified+)
                                   (timeout +timeout-unspecified+)
                                   headers)
                           :post
                           "/pull"
                           (lambda (stream-p)
                             (%json-object (cons "model" model)
                                           (%optional-json-pair "insecure"
                                                                insecure
                                                                #'%native-bool)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Pull MODEL from a registry."
                           :stream-documentation
                           "Stream pull progress events for MODEL.")

(define-native-stream-pair push-model
                           push-model-stream
                           (client model
                                   &key
                                   (insecure +json-unspecified+)
                                   (timeout +timeout-unspecified+)
                                   headers)
                           :post
                           "/push"
                           (lambda (stream-p)
                             (%json-object (cons "model" model)
                                           (%optional-json-pair "insecure"
                                                                insecure
                                                                #'%native-bool)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Push MODEL to a registry."
                           :stream-documentation
                           "Stream push progress events for MODEL.")

(define-json-endpoint %request-json-value
                      version
                      (client &key (timeout +timeout-unspecified+) headers)
                      :get
                      "/version"
                      :documentation
                      "Return the Ollama server version.")
