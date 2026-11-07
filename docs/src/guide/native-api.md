# Native API guide

The native helpers target Ollama's `/api` endpoints. A client created by
`ollama-kit:make-client` defaults to `http://localhost:11434/api` and joins
relative endpoint paths to that base URL.
Custom base URLs and URLs passed to `web-fetch` must use HTTP or HTTPS and have
a valid authority. Both reject user information.
The examples assume `*ollama*` is the client created in [Getting
started](../getting-started.md).

Replace `"model"` in these examples with a model installed on the configured
Ollama service.

## Generation, chat, and embeddings

The main request pairs are:

- `ollama-kit:generate` and `ollama-kit:generate-stream` call `/generate`.
- `ollama-kit:chat` and `ollama-kit:chat-stream` call `/chat`.
- `ollama-kit:embed` calls `/embed`.

Generation accepts `:suffix`, `:images`, `:format`, `:options`, `:system`,
`:template`, `:context`, `:raw`, `:think`, `:keep-alive`, `:logprobs`,
`:top-logprobs`, and the experimental image controls `:width`, `:height`, and
`:steps`. Chat accepts `:tools`, `:format`, `:options`, `:keep-alive`,
`:think`, `:logprobs`, and `:top-logprobs`.

For `:think`, `t` and `nil` are sent as JSON booleans. Other symbols and strings
are sent as enum strings.

Send a chat request:

```lisp
(ollama-kit:chat
 *ollama*
 "model"
 (list (ollama-kit:make-message
        "user"
        "Return a short answer.")))
```

Embedding input may be one string or a list or vector of strings. `:truncate`,
`:dimensions`, `:options`, and `:keep-alive` are available on `embed`. This
helper sends a JSON request to `/embed`.

## JSON values and structured output

`ollama-kit:json-object` creates a JSON object from alternating keys and
values. `ollama-kit:+json-unspecified+` means that an optional field is
omitted. Use `json-kit:+json-null+` when a request must contain JSON `null`.

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

The model helpers map to native endpoints:

| Helper | Endpoint | Purpose |
| --- | --- | --- |
| `ollama-kit:list-models` | `/tags` | List locally available models. |
| `ollama-kit:list-running-models` | `/ps` | List models currently loaded in memory. |
| `ollama-kit:show-model` | `/show` | Return model details. |
| `ollama-kit:create-model` | `/create` | Create a model. |
| `ollama-kit:copy-model` | `/copy` | Copy a model. |
| `ollama-kit:delete-model` | `/delete` | Delete a model. |
| `ollama-kit:pull-model` | `/pull` | Pull a model from a registry. |
| `ollama-kit:push-model` | `/push` | Push a model to a registry. |
| `ollama-kit:version` | `/version` | Return the server version. |

`create-model`, `pull-model`, and `push-model` also have streaming variants.
`create-model` accepts `:from`, `:files`, `:adapters`, `:template`, `:license`,
`:system`, `:parameters`, `:messages`, `:quantize`, `:renderer`, and `:parser`.

## Blobs

`ollama-kit:blob-exists-p` checks a digest with `HEAD /blobs/{digest}` and
returns true when the server reports it exists. `ollama-kit:push-blob`
uploads a string or octet vector with an octet-stream content type. It returns
the successful HTTP response object.

## Web search and fetch

`ollama-kit:web-search` sends a request to `/web_search` and
`ollama-kit:web-fetch` sends a request to `/web_fetch`. Both return decoded
JSON objects. `:max-results` is optional on `web-search` and must be between 1
and 10. Configure the client with `:api-key` when the service requires
authentication. A URL passed to `web-fetch` must use HTTP or HTTPS, contain a
valid authority, and omit user information.

## Streaming

Native streams use NDJSON. `generate-stream`, `chat-stream`,
`create-model-stream`, `pull-model-stream`, and `push-model-stream` consume the
response synchronously. Each callback receives a decoded JSON object. Return
`:stop` from the callback to cancel the active request and complete normally.
The final non-empty NDJSON line is delivered at EOF even if it has no trailing
newline.

Callbacks run in the thread consuming the HTTP response. Stream endpoint functions accept
per-call `:response-timeout`, `:idle-timeout`, and `:cancel-token` options in
addition to `:timeout` and `:headers`. See the [API reference](../reference/api.md)
for client option defaults and the [conditions reference](../reference/conditions.md)
for timeout, cancellation, and protocol errors.

Create a cancellation token with
`http-kit/client:make-http-cancellation-token` and pass it as `:cancel-token`.
Another thread can cancel it with
`http-kit/client:http-client-cancel-request`; the request signals
`ollama-cancelled`. If a callback exits non-locally, the request is cancelled
and the connection is released.

`ollama-kit:call-with-ollama-stream` consumes an arbitrary native path using a
caller-supplied method and event callback. See the [API
reference](../reference/api.md) for its request options and response behavior.
