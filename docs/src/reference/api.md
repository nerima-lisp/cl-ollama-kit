# API reference

The symbols in this reference are exported from the `<code>ollama-kit</code>` package unless a different package is shown. JSON endpoint functions return decoded JSON. The stream functions consume events synchronously through a callback and return after the response finishes or the callback returns `<code>:stop</code>`.

## Client and transport

### Base URL constants

`<code>+default-base-url+</code>` is `<code>http://localhost:11434/api</code>`. `<code>+anthropic-default-base-url+</code>` is `<code>http://localhost:11434/v1</code>`. `<code>make-openai-client</code>` uses the same `<code>/v1</code>` default for its base URL.

### `<code>make-client</code>`

Signature: `<code>(make-client &rest options)</code>`.

Accepted options:

- `<code>:base-url</code>`
- `<code>:http-client</code>`
- `<code>:headers</code>`
- `<code>:api-key</code>`
- `<code>:timeout</code>`
- `<code>:response-timeout</code>`
- `<code>:idle-timeout</code>`
- `<code>:max-input-length</code>`
- `<code>:max-request-length</code>`
- `<code>:allow-insecure-http</code>`

The client uses `<code>cl-http-kit</code>` directly and HTTP message types from `<code>cl-http-message-kit</code>`. If `<code>:http-client</code>` is omitted, `<code>make-client</code>` creates and owns a default client that speaks plain HTTP. TLS support is not a default dependency. To enable it, load `<code>cl-http-kit/tls</code>`, create an HTTP client, and pass it to `<code>make-client</code>`. `<code>close-client</code>` clears connections on an owned client. When the caller supplies `<code>:http-client</code>`, the caller retains its lifetime and connection management.

HTTPS requires a caller-supplied TLS-enabled `<code>http-kit/client:http-client</code>`. Without it, a `<code>https</code>` base URL signals `<code>ollama-argument-error</code>`.

```lisp
(asdf:load-system "cl-http-kit/tls")
(defparameter *https-http-client*
  (http-kit/client:make-http-client))
(defparameter *ollama*
  (ollama-kit:make-client
   :base-url "https://localhost:11434/api"
   :http-client *https-http-client*))
```

The base URL must use HTTP or HTTPS, contain a valid host authority, and have no query or fragment. Plain HTTP is allowed for `<code>localhost</code>`, `<code>127.0.0.1</code>`, and `<code>::1</code>`. Other plain HTTP base URLs require `<code>:allow-insecure-http t</code>`.

The `<code>make-openai-client</code>` and `<code>make-anthropic-client</code>` wrappers currently accept `<code>:http-client</code>`, `<code>:response-timeout</code>`, and `<code>:idle-timeout</code>` during option validation but do not forward them. Use `<code>make-client</code>` with an explicit `<code>:base-url</code>` when those options are needed. The wrappers forward `<code>:base-url</code>`, `<code>:headers</code>`, `<code>:api-key</code>`, `<code>:timeout</code>`, `<code>:max-input-length</code>`, `<code>:max-request-length</code>`, and `<code>:allow-insecure-http</code>`.

### Other client constructors

`<code>make-openai-client</code>` creates a client based at `<code>http://localhost:11434/v1</code>`. `<code>make-anthropic-client</code>` creates a client based at `<code>http://localhost:11434/v1</code>`. Both accept the forwarded options described above. For `<code>make-openai-client</code>`, `<code>:api-key</code>` becomes a Bearer Authorization header. For `<code>make-anthropic-client</code>`, `<code>:api-key</code>` becomes an `<code>X-API-KEY</code>` header; additional compatibility headers can be set with `<code>:headers</code>`.

### Client readers and cleanup

- `<code>client-p</code>` tests whether a value is an `<code>ollama-kit</code>` client.
- `<code>client-base-url</code>` returns its normalized base URL.
- `<code>client-http-client</code>` returns the underlying `<code>http-kit/client:http-client</code>`.
- `<code>client-headers</code>` returns normalized default headers.
- `<code>client-timeout</code>` returns the default HTTP request timeout. A per-call `<code>:timeout</code>` overrides it.
- `<code>client-response-timeout</code>` returns the default stream response-header timeout. Its default is 300 seconds.
- `<code>client-idle-timeout</code>` returns the default stream body idle timeout. Its default is 120 seconds.
- `<code>client-max-input-length</code>` returns the response input limit.
- `<code>client-max-request-length</code>` returns the encoded request limit.
- `<code>client-api-key-p</code>` reports whether the client was configured with an API key.
- `<code>client-allow-insecure-http</code>` returns the plain HTTP opt-in value.
- `<code>close-client</code>` clears connections if the client owns its HTTP client. It does not close a caller-supplied HTTP client.

### `<code>perform-request</code>`

Signature: `<code>(perform-request client method path &rest options)</code>`. It sends a request and returns an `<code>http-message-kit:http-response</code>`. Accepted options are `<code>:body</code>`, `<code>:stream-p</code>`, `<code>:timeout</code>`, `<code>:headers</code>`, `<code>:content-type</code>`, and `<code>:accept</code>`. The body must be a string or octet vector. This low-level function returns the response without requiring a success status.

`<code>:stream-p</code>` selects the default streaming Accept header. It does not return a stream object.

### `<code>request-json</code>`

Signature: `<code>(request-json client method path &rest options)</code>`. Accepted options are `<code>:body</code>`, `<code>:stream-p</code>`, `<code>:timeout</code>`, and `<code>:headers</code>`. It parses a successful JSON response and returns the parsed value as its first value and the complete `<code>http-message-kit:http-response</code>` as its second value. A non-success status signals `<code>ollama-http-error</code>` or `<code>ollama-api-error</code>`.

### `<code>request-raw</code>`

Signature: `<code>(request-raw client method path &rest options)</code>`. Accepted options are `<code>:body</code>`, `<code>:stream-p</code>`, `<code>:timeout</code>`, `<code>:headers</code>`, `<code>:content-type</code>`, and `<code>:accept</code>`. It passes a string or octet vector body through and returns a successful `<code>http-message-kit:http-response</code>`. A non-success status signals an HTTP or API condition.

The response reader functions belong to `<code>http-message-kit</code>`, not `<code>ollama-kit</code>`.

### Continuation helpers

`<code>with-ollama-continuations</code>` is a macro that evaluates a body and calls a success function with the body's values. If the body signals an `<code>ollama-error</code>`, it calls a failure function with that condition. Errors raised by either continuation propagate.

`<code>call-with-json</code>` runs a JSON request synchronously. Its success function receives the decoded JSON value and response as two arguments; its failure function receives an `<code>ollama-error</code>`.

## JSON and messages

### `<code>+json-unspecified+</code>`

Sentinel for an omitted optional JSON field. It differs from false, zero, an empty array, and JSON null.

### `<code>json-object</code>`

Signature: `<code>(json-object &rest pairs)</code>`. It creates a JSON object from alternating string-or-symbol keys and values.

### `<code>make-message</code>`

Signature: `<code>(make-message role content &key name tool-calls thinking images)</code>`. It creates a native chat message and omits optional fields whose values are `<code>+json-unspecified+</code>`.

## Synchronous streaming

`<code>call-with-ollama-stream</code>`, `<code>call-with-openai-stream</code>`, and `<code>call-with-anthropic-stream</code>` synchronously consume a response body and invoke an event function once for each decoded JSON event. Native streams use NDJSON. OpenAI-compatible and Anthropic-compatible streams use SSE parsed by `<code>cl-sse-kit</code>`. Each function has the signature `<code>(client method path event-function &rest options)</code>`.

The callback receives one decoded JSON object and runs as each complete event is parsed, in wire order. Return `<code>:stop</code>` to cancel the active request and finish normally; the function returns `<code>nil</code>` on this path and returns the HTTP response at EOF. A callback error or other non-local exit propagates to the caller. On a non-local exit, `<code>cl-ollama-kit</code>` stops and joins its timeout monitor, but does not explicitly cancel the request on that path.

Stream functions accept `<code>:body</code>`, `<code>:timeout</code>`, `<code>:headers</code>`, `<code>:response-timeout</code>`, `<code>:idle-timeout</code>`, and `<code>:cancel-token</code>`. A supplied `<code>http-kit/client:make-http-cancellation-token</code>` token is passed to `<code>cl-http-kit</code>`; if omitted, the library creates one. To request cancellation from another thread, call `<code>http-kit/client:http-client-cancel-request</code>` with that token. Cancellation signals `<code>ollama-cancelled</code>`. The response-timeout measures time to response headers. The idle-timeout measures the time between body chunks. Both default to the client settings.

An SSE event must end with a blank line before EOF to be delivered. An event left unterminated at EOF is discarded. The native NDJSON parser delivers a final non-empty line at EOF. An SSE `<code>[DONE]</code>` event ends processing and is not passed to the callback.

### Generated endpoint stream functions

Native `<code>generate-stream</code>`, `<code>chat-stream</code>`, `<code>create-model-stream</code>`, `<code>pull-model-stream</code>`, and `<code>push-model-stream</code>` take an event function after their normal positional arguments. OpenAI-compatible `<code>openai-chat-completions-stream</code>`, `<code>openai-completions-stream</code>`, and `<code>openai-responses-stream</code>` take `<code>(client body event-function &key ...)</code>`. `<code>anthropic-messages-stream</code>` has the same shape. These functions add `<code>:response-timeout</code>`, `<code>:idle-timeout</code>`, and `<code>:cancel-token</code>` to their options.

## Conditions

All conditions below are exported from `<code>ollama-kit</code>`. See the [conditions reference](conditions.md) for the inheritance tree and condition readers.

- `<code>ollama-error</code>` and `<code>ollama-error-message</code>`
- `<code>ollama-argument-error</code>` and `<code>ollama-argument-error-detail</code>`
- `<code>ollama-transport-error</code>` and `<code>ollama-transport-error-cause</code>`
- `<code>ollama-cancelled</code>`, `<code>ollama-response-timeout</code>`, and `<code>ollama-idle-timeout</code>`
- `<code>ollama-protocol-error</code>` and `<code>ollama-protocol-error-detail</code>`
- `<code>ollama-stream-error</code>`, `<code>ollama-stream-error-event</code>`, and `<code>ollama-stream-error-line</code>`
- `<code>ollama-http-error</code>`, `<code>ollama-http-error-status</code>`, `<code>ollama-http-error-response</code>`, and `<code>ollama-http-error-body</code>`
- `<code>ollama-api-error</code>` and `<code>ollama-api-error-data</code>`

## Native API

- `<code>generate</code>` and `<code>generate-stream</code>` call `<code>POST /api/generate</code>`.
- `<code>chat</code>` and `<code>chat-stream</code>` call `<code>POST /api/chat</code>`.
- `<code>embed</code>` calls the JSON-only `<code>POST /api/embed</code>` endpoint. Its input is a string or sequence of strings. `<code>:dimensions</code>` must be an integer and `<code>:keep-alive</code>` must be a duration string when supplied.
- `<code>list-models</code>`, `<code>list-running-models</code>`, and `<code>show-model</code>` query local models.
- `<code>create-model</code>` and `<code>create-model-stream</code>` create a model.
- `<code>copy-model</code>` copies a model. `<code>delete-model</code>` deletes a model.
- `<code>pull-model</code>`, `<code>pull-model-stream</code>`, `<code>push-model</code>`, and `<code>push-model-stream</code>` transfer models. The request's optional `<code>:insecure</code>` flag is separate from the client URL option `<code>:allow-insecure-http</code>`.
- `<code>blob-exists-p</code>` checks `<code>HEAD /api/blobs/{digest}</code>`. `<code>push-blob</code>` uploads a string or octet vector.
- `<code>web-search</code>` and `<code>web-fetch</code>` call the web endpoints.

## OpenAI-compatible API

`<code>make-openai-client</code>` creates a client for the OpenAI-compatible `<code>/v1</code>` API.

- `<code>openai-model</code>` and `<code>openai-models</code>` query models.
- `<code>openai-chat-completions</code>` and `<code>openai-chat-completions-stream</code>` call `<code>/v1/chat/completions</code>`.
- `<code>openai-completions</code>` and `<code>openai-completions-stream</code>` call `<code>/v1/completions</code>`.
- `<code>openai-embeddings</code>` calls `<code>/v1/embeddings</code>`.
- `<code>openai-responses</code>` and `<code>openai-responses-stream</code>` call `<code>/v1/responses</code>`.
- `<code>openai-images</code>` calls the experimental `<code>/v1/images/generations</code>` endpoint.

Streaming endpoint functions take a JSON body and event function. Other endpoint functions accept the request-specific arguments or a JSON body as described in the [OpenAI-compatible guide](../guide/openai-compatible-api.md).

## Anthropic-compatible API

`<code>make-anthropic-client</code>` creates a client for the Anthropic-compatible Messages API. Its `<code>:api-key</code>` is sent in `<code>X-API-KEY</code>`; compatibility headers such as `<code>anthropic-version</code>` can be supplied with `<code>:headers</code>`.

`<code>anthropic-messages</code>` sends a Messages request to `<code>/v1/messages</code>`. `<code>anthropic-messages-stream</code>` sets the request's `<code>stream</code>` field to true and synchronously passes decoded SSE events to the event function.
