# Native API guide

The native helpers target Ollama's `/api` endpoints. A client created by
`ollama-kit:make-client` defaults to `http://localhost:11434/api` and joins
relative endpoint paths to that base URL.

## Version 2 contract

Version 2 intentionally removes the legacy native `legacy-embeddings` helper
and `/api/embeddings` endpoint. Use `embed` for the current JSON-only
`/api/embed` endpoint. The OpenAI-compatible embeddings helper is unchanged.

## Generation, chat, and embeddings

The main request pairs are:

- `ollama-kit:generate` and `ollama-kit:generate-stream` call `/generate`.
- `ollama-kit:chat` and `ollama-kit:chat-stream` call `/chat`.
- `ollama-kit:embed` calls `/embed`.

Generation accepts prompt-oriented options such as `:suffix`, `:images`,
`:format`, `:options`, `:system`, `:template`, `:context`, `:raw`, and
`:think`, as well as `:keep-alive`, `:logprobs`, and `:top-logprobs`. The
experimental image-generation controls `:width`, `:height`, and `:steps` are
passed through when supplied.

Chat takes a list or vector of message values and also accepts `:tools`,
`:format`, `:options`, `:keep-alive`, `:think`, `:logprobs`, and
`:top-logprobs`. Create messages explicitly so optional fields remain distinct
from an omitted value:

```lisp
(ollama-kit:chat
 *ollama*
 "model"
 (list (ollama-kit:make-message
        "user"
        "Return a short answer."
        :thinking nil)))
```

Embedding input may be one string or a list/vector of strings. `:truncate`,
`:dimensions`, `:options`, and `:keep-alive` are available on `embed`. The
current official `/api/embed` contract is JSON-only; see the
[Ollama Embed API](https://docs.ollama.com/api/embed) documentation.

## JSON values and structured output

`ollama-kit:json-object` creates a JSON object from alternating keys and
values. `ollama-kit:+json-unspecified+` means that an optional field is
omitted. Use `json-kit:+json-null+` when the request must contain JSON `null`.

For structured generation, pass the schema-shaped JSON value through
`:format`:

```lisp
(ollama-kit:generate
 *ollama*
 "model"
 "Return a person object."
 :format (ollama-kit:json-object
          "type" "object"
          "properties"
          (ollama-kit:json-object
           "name" (ollama-kit:json-object "type" "string"))))
```

## Model lifecycle

The model helpers map directly to the native endpoints:

| Helper | Endpoint | Purpose |
| --- | --- | --- |
| `list-models` | `/tags` | List locally available models. |
| `list-running-models` | `/ps` | List models currently loaded in memory. |
| `show-model` | `/show` | Return model details. |
| `create-model` | `/create` | Create a model. |
| `copy-model` | `/copy` | Copy a model. |
| `delete-model` | `/delete` | Delete a model. |
| `pull-model` | `/pull` | Pull a model from a registry. |
| `push-model` | `/push` | Push a model to a registry. |
| `version` | `/version` | Return the server version. |

The `create-model`, `pull-model`, and `push-model` families also have streaming
variants for progress events. `create-model` exposes native options including
`:from`, `:files`, `:adapters`, `:template`, `:license`, `:system`,
`:parameters`, `:messages`, `:quantize`, `:renderer`, and `:parser`.

## Blobs

`ollama-kit:blob-exists-p` checks a digest with `HEAD /blobs/{digest}` and
closes the response before returning. `ollama-kit:push-blob` uploads a string
or octet vector to the same path with an octet-stream content type. Its
successful response is returned to the caller, who must close it with
`ollama-kit:close-http-response`.

## Web search and fetch

Ollama Cloud provides `ollama-kit:web-search` for `POST /web_search` and
`ollama-kit:web-fetch` for `POST /web_fetch`. Configure a native client with
the Cloud base URL and an API key:

```lisp
(defparameter *ollama-cloud*
  (ollama-kit:make-client
   :base-url "https://ollama.com/api"
   :api-key ollama-api-key
   :network-boundary application-network-boundary))

(ollama-kit:web-search *ollama-cloud* "Common Lisp" :max-results 5)
(ollama-kit:web-fetch *ollama-cloud* "https://example.com/docs")
```

`:max-results` is optional and must be between 1 and 10. These operations
return decoded JSON objects. See Ollama's [web search and fetch
documentation](https://docs.ollama.com/capabilities/web-search) for Cloud
availability and response fields.

## Stream ownership

Native streams decode independent NDJSON events. Always close a stream from an
`unwind-protect` or use `ollama-kit:stream-events`, which closes it on normal
completion, when its optional limit is reached, and when consumption signals
an error. A stream error includes the decoded event and its one-based input
line; see the [conditions reference](../reference/conditions.md).

For the lower-level transport entry points and response ownership rules, see
the [API reference](../reference/api.md).
