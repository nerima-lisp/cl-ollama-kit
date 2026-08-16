#.(progn (in-package :ollama-kit) nil)

(define-native-json-endpoint list-models
                             (client &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :get
                             "/tags"
                             :documentation
                             "List locally available models.")

(define-native-json-endpoint list-running-models
                             (client &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :get
                             "/ps"
                             :documentation
                             "List models currently loaded in memory.")

(define-native-json-endpoint show-model
                             (client model
                                     &key
                                     (verbose +json-unspecified+)
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/show"
                             :body-form
                             (%native-body (cons "model" model)
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
                             (%native-body (cons "model" model)
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
                                                                #'%native-enum)
                                           (%optional-json-pair "renderer"
                                                                renderer)
                                           (%optional-json-pair "parser" parser)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Create a model through Ollama's native `/api/create` endpoint."
                           :stream-documentation
                           "Stream model creation status events.")

(define-native-json-endpoint copy-model
                             (client source
                                     destination
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :post
                             "/copy"
                             :body-form
                             (%native-body (cons "source" source)
                                           (cons "destination" destination))
                             :documentation
                             "Copy SOURCE to DESTINATION.")

(define-native-json-endpoint delete-model
                             (client model
                                     &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :delete
                             "/delete"
                             :body-form
                             (%native-body (cons "model" model))
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
                             (%native-body (cons "model" model)
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
                             (%native-body (cons "model" model)
                                           (%optional-json-pair "insecure"
                                                                insecure
                                                                #'%native-bool)
                                           (%stream-option-pair stream-p)))
                           :documentation
                           "Push MODEL to a registry."
                           :stream-documentation
                           "Stream push progress events for MODEL.")

(define-native-json-endpoint version
                             (client &key
                                     (timeout +timeout-unspecified+)
                                     headers)
                             :get
                             "/version"
                             :documentation
                             "Return the Ollama server version.")
