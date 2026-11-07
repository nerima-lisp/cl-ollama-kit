# API reference

The symbols in this reference are exported from the `ollama-kit` package unless a different package is shown. JSON endpoint functions return decoded JSON. The stream functions consume events synchronously through a callback and return after the response finishes or the callback returns `:stop`.

## Client and transport

### Base URL constants

`+default-base-url+` is `http://localhost:11434/api`. `+anthropic-default-base-url+` is `http://localhost:11434/v1`. `make-openai-client` uses the same `/v1` default for its base URL.

### `make-client`

Signature: `(make-client &rest options)`.

Accepted options:

- `:base-url`
- `:http-client`
- `:headers`
- `:api-key`
- `:timeout`
- `:response-timeout`
- `:idle-timeout`
- `:max-input-length`
- `:max-request-length`
- `:allow-insecure-http`

The client uses `cl-http-kit` directly and HTTP message types from `cl-http-message-kit`. If `:http-client` is omitted, `make-client` creates and owns a default client that speaks plain HTTP. TLS support is not a default dependency. To enable it, load `cl-http-kit/tls`, create an HTTP client, and pass it to `make-client`. `close-client` clears connections on an owned client. When the caller supplies `:http-client`, the caller retains its lifetime and connection management.

HTTPS requires a caller-supplied TLS-enabled `http-kit/client:http-client`. Without it, a `https` base URL signals `ollama-argument-error`.

```lisp
(asdf:load-system "cl-http-kit/tls")
(defparameter *https-http-client*
  (http-kit/client:make-http-client))
(defparameter *ollama*
  (ollama-kit:make-client
   :base-url "https://localhost:11434/api"
   :http-client *https-http-client*))
```

The base URL must use HTTP or HTTPS, contain a valid host authority, and have no query or fragment. Plain HTTP is allowed for `localhost`, `127.0.0.1`, and IPv6 loopback `::1` (written as `[::1]` in a URL). Other plain HTTP base URLs require `:allow-insecure-http t`.

The `make-openai-client` and `make-anthropic-client` wrappers validate `:http-client`, `:response-timeout`, and `:idle-timeout` but do not pass them to `make-client`. Use `make-client` with an explicit `:base-url` when those options are needed. The wrappers pass `:base-url`, `:headers`, `:api-key`, `:timeout`, `:max-input-length`, `:max-request-length`, and `:allow-insecure-http` to `make-client`.

### Other client constructors

For `make-openai-client`, `:api-key` sets an Authorization header using the Bearer scheme. For `make-anthropic-client`, `:api-key` sets an `X-API-KEY` header; additional compatibility headers can be set with `:headers`.

### Client readers and cleanup

- `client-p` tests whether a value is an `ollama-kit` client.
- `client-base-url` returns its normalized base URL.
- `client-http-client` returns the underlying `http-kit/client:http-client`.
- `client-headers` returns normalized default headers.
- `client-timeout` returns the default HTTP request timeout. A per-call `:timeout` overrides it.
- `client-response-timeout` returns the default stream response-header timeout. Its default is 300 seconds.
- `client-idle-timeout` returns the default stream body idle timeout. Its default is 120 seconds.
- `client-max-input-length` returns the response input limit.
- `client-max-request-length` returns the encoded request limit.
- `client-api-key-p` reports whether the client was configured with an API key.
- `client-allow-insecure-http` returns the plain HTTP opt-in value.
- `close-client` clears connections if the client owns its HTTP client. It does not close a caller-supplied HTTP client.

### `perform-request`

Signature: `(perform-request client method path &rest options)`. It sends a request and returns an `http-message-kit:http-response`. Accepted options are `:body`, `:stream-p`, `:timeout`, `:headers`, `:content-type`, and `:accept`. The body must be a string or octet vector. This low-level function returns the response without requiring a success status.

`:stream-p` selects the default streaming Accept header. It does not return a stream object.

### `request-json`

Signature: `(request-json client method path &rest options)`. Accepted options are `:body`, `:stream-p`, `:timeout`, and `:headers`. It parses a successful JSON response and returns the parsed value as its first value and the complete `http-message-kit:http-response` as its second value. A non-success status signals `ollama-http-error` or `ollama-api-error`.

### `request-raw`

Signature: `(request-raw client method path &rest options)`. Accepted options are `:body`, `:stream-p`, `:timeout`, `:headers`, `:content-type`, and `:accept`. It passes a string or octet vector body through and returns a successful `http-message-kit:http-response`. A non-success status signals an HTTP or API condition.

The response reader functions belong to `http-message-kit`, not `ollama-kit`.

### Continuation helpers

`with-ollama-continuations` is a macro that evaluates a body and calls a success function with the body's values. If the body signals an `ollama-error`, it calls a failure function with that condition. Errors raised by either continuation propagate.

`call-with-json` runs a JSON request synchronously. Its success function receives the decoded JSON value and response as two arguments; its failure function receives an `ollama-error`.

## JSON and messages

### `+json-unspecified+`

Sentinel for an omitted optional JSON field. It differs from false, zero, an empty array, and JSON null.

### `json-object`

Signature: `(json-object &rest pairs)`. It creates a JSON object from alternating string-or-symbol keys and values.

### `make-message`

Signature: `(make-message role content &key name tool-calls thinking images)`. It creates a native chat message and omits optional fields whose values are `+json-unspecified+`.

## Synchronous streaming

`call-with-ollama-stream`, `call-with-openai-stream`, and `call-with-anthropic-stream` synchronously consume a response body and invoke an event function once for each decoded JSON event. Native streams use NDJSON. OpenAI-compatible and Anthropic-compatible streams use SSE parsed by `cl-sse-kit`. Each function has the signature `(client method path event-function &rest options)`.

The callback receives one decoded JSON object and runs as each complete event is parsed, in wire order. Return `:stop` to cancel the active request and finish normally; the function returns `nil` on this path and returns the HTTP response at EOF. A callback error or other non-local exit propagates to the caller. On a non-local exit, `cl-ollama-kit` stops and joins its timeout monitor, but does not explicitly cancel the request on that path.

Stream functions accept `:body`, `:timeout`, `:headers`, `:response-timeout`, `:idle-timeout`, and `:cancel-token`. `http-kit/client:make-http-cancellation-token` creates a token to pass as `:cancel-token`; if omitted, the library creates one. To request cancellation from another thread, call `http-kit/client:http-client-cancel-request` with the same token. Cancellation signals `ollama-cancelled`. The response-timeout measures time to response headers. The idle-timeout measures the time between body chunks. Both default to the client settings.

An SSE event must end with a blank line before EOF to be delivered. An event left unterminated at EOF is discarded. The native NDJSON parser delivers a final non-empty line at EOF. An SSE `[DONE]` event ends processing and is not passed to the callback.

### Generated endpoint stream functions

Native `generate-stream`, `chat-stream`, `create-model-stream`, `pull-model-stream`, and `push-model-stream` take an event function after their normal positional arguments. OpenAI-compatible `openai-chat-completions-stream`, `openai-completions-stream`, and `openai-responses-stream` take `(client body event-function &key ...)`. `anthropic-messages-stream` has the same shape. These functions add `:response-timeout`, `:idle-timeout`, and `:cancel-token` to their options.

## Conditions

All conditions below are exported from `ollama-kit`. See the [conditions reference](conditions.md) for the inheritance tree and condition readers.

- `ollama-error` and `ollama-error-message`
- `ollama-argument-error` and `ollama-argument-error-detail`
- `ollama-transport-error` and `ollama-transport-error-cause`
- `ollama-cancelled`, `ollama-response-timeout`, and `ollama-idle-timeout`
- `ollama-protocol-error` and `ollama-protocol-error-detail`
- `ollama-stream-error`, `ollama-stream-error-event`, and `ollama-stream-error-line`
- `ollama-http-error`, `ollama-http-error-status`, `ollama-http-error-response`, and `ollama-http-error-body`
- `ollama-api-error` and `ollama-api-error-data`

## Native API

- `generate` and `generate-stream` call `POST /api/generate`.
- `chat` and `chat-stream` call `POST /api/chat`.
- `embed` calls the JSON-only `POST /api/embed` endpoint. Its input is a string or sequence of strings. `:dimensions` must be an integer and `:keep-alive` must be a duration string when supplied.
- `list-models`, `list-running-models`, and `show-model` query local models.
- `create-model` and `create-model-stream` create a model.
- `copy-model` copies a model. `delete-model` deletes a model.
- `pull-model`, `pull-model-stream`, `push-model`, and `push-model-stream` transfer models. The request's optional `:insecure` flag is separate from the client URL option `:allow-insecure-http`.
- `blob-exists-p` checks `HEAD /api/blobs/{digest}`. `push-blob` uploads a string or octet vector.
- `web-search` and `web-fetch` call the web endpoints.

## OpenAI-compatible API

`make-openai-client` creates a client for the OpenAI-compatible `/v1` API.

- `openai-model` and `openai-models` query models.
- `openai-chat-completions` and `openai-chat-completions-stream` call `/v1/chat/completions`.
- `openai-completions` and `openai-completions-stream` call `/v1/completions`.
- `openai-embeddings` calls `/v1/embeddings`.
- `openai-responses` and `openai-responses-stream` call `/v1/responses`.
- `openai-images` calls the experimental `/v1/images/generations` endpoint.

Streaming endpoint functions take a JSON body and event function. Other endpoint functions accept the request-specific arguments or a JSON body as described in the [OpenAI-compatible guide](../guide/openai-compatible-api.md).

## Anthropic-compatible API

`make-anthropic-client` creates a client for the Anthropic-compatible Messages API. Its `:api-key` is sent in `X-API-KEY`; compatibility headers such as `anthropic-version` can be supplied with `:headers`.

`anthropic-messages` sends a Messages request to `/v1/messages`. `anthropic-messages-stream` sets the request's `stream` field to true and synchronously passes decoded SSE events to the event function.
