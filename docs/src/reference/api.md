# API reference

All symbols below are exported from the `ollama-kit` package. Unless stated
otherwise, a request helper returns decoded JSON and accepts optional
`:timeout` and `:headers` keyword arguments. Streaming helpers return an
`ollama-kit:ollama-stream` owned by the caller.

Version 2 intentionally removes the legacy native `legacy-embeddings` helper
and `/api/embeddings`; use `embed` for the current JSON-only `/api/embed`.

## Client and transport

### `+default-base-url+`

The default native base URL: `http://localhost:11434/api`.

### `make-client`

Signature: `(make-client &rest options)`. Supply `:network-boundary`; supported
options are `:base-url`, `:headers`, `:api-key`, `:timeout`,
`:max-input-length`, `:max-request-length`, and `:allow-insecure-http`.

### `client-p`

Return true when a value is an `ollama-kit` client.

### `client-base-url`

Return the normalized base URL stored by a client.

### `client-network-boundary`

Return the application-owned network boundary.

### `client-headers`

Return the client's normalized default headers.

### `client-timeout`

Return the client's default request timeout.

When a request helper omits `:timeout`, it uses this client default. Supplying
`:timeout nil` explicitly bypasses the client default and passes `NIL` to the
network boundary. The boundary owns deadline enforcement, connection and read
timeouts, and any socket-level cancellation policy.

### `client-max-input-length`

Return the maximum response-input length.

### `client-max-request-length`

Return the maximum encoded request length.

### `client-api-key-p`

Return true when the client was configured with an API key.

### `client-allow-insecure-http`

Return the client's plain-HTTP opt-in value.

### `make-http-request`

Construct an HTTP request model from `:method`, `:url`, `:headers`, `:body`,
and `:stream-p`.

### `http-request-p`

Return true when a value is an HTTP request model.

### `http-request-method`

Return the request method.

### `http-request-url`

Return the request URL.

### `http-request-headers`

Return the request headers.

### `http-request-body`

Return the string or octet-vector request body, if present.

### `http-request-stream-p`

Return whether the request asks for a streaming response.

### `make-http-response`

Construct an HTTP response model from status, headers, body or stream, and an
optional close function.

### `http-response-p`

Return true when a value is an HTTP response model.

### `http-response-status`

Return the numeric response status.

### `http-response-headers`

Return the response headers.

### `http-response-body`

Return the materialized response body, if present.

### `http-response-stream`

Return the incremental response stream, if present.

### `http-response-close-function`

Return the response cleanup function, if one was supplied.

### `response-success-p`

Return true for a 2xx response.

### `close-http-response`

Close a response's underlying stream and close callback, if present. A
materialized body is already in memory and requires no separate release.
Closing is idempotent.

### `perform-request`

Signature: `(perform-request client method path &rest options)`. Send a raw
request through the boundary and return an `http-response`. Options include
`:body`, `:stream-p`, `:timeout`, `:headers`, `:content-type`, and `:accept`.

### `request-json`

Signature: `(request-json client method path &rest options)`. Encode an
optional JSON body, ensure success, and return parsed JSON as the first value
and the full response as the second value. The response is owned by the
caller.

### `request-raw`

Signature: `(request-raw client method path &rest options)`. Pass through a
string or octet-vector body and return an unconsumed successful response. The
caller must call `close-http-response`.

The high-level native, web, and OpenAI JSON endpoint helpers close successful
responses before returning their decoded value. Use `request-json` or
`with-json-response` when the response object itself is needed.

### `with-http-response`

Macro: `(with-http-response (response-form) &body body)`. Evaluate a response
form and close its HTTP response after the body, including when the body exits
non-locally.

### `with-json-response`

Macro: `(with-json-response (value-var response-var request-form) &body body)`.
Bind the two values returned by `request-json` and close the response after the
body. This is the scoped form for JSON requests whose parsed value is consumed
inside the body.

### `call-with-json`

Call a success continuation with decoded JSON and its response, or a failure
continuation with an `ollama-error`. The success continuation owns the
response.

### `call-with-stream`

Open a stream with an opener function, call the success continuation with it,
or call the failure continuation with an `ollama-error`. The success
continuation owns the stream.

## JSON and messages

### `+json-unspecified+`

Sentinel for an omitted optional JSON field. It is distinct from false, zero,
an empty array, and JSON null.

### `json-object`

Signature: `(json-object &rest pairs)`. Create a JSON object from alternating
string-or-symbol keys and values.

### `make-message`

Signature: `(make-message role content &key name tool-calls thinking images)`.
Create a native chat message and omit optional fields whose values are
`+json-unspecified+`.

## Streams

### `ollama-stream`

The stream model holding an incremental response, wire format, close function,
and line-length limit.

### `ollama-stream-p`

Return true when a value is an Ollama stream.

### `open-ollama-stream`

Open a native NDJSON stream. The accepted options are `:body`, `:timeout`, and
`:headers`; the caller must eventually call `stream-close`.

### `ollama-stream-error`

Condition signaled when decoding a stream event fails. It preserves the event
and one-based input line; see the [conditions reference](conditions.md).

### `ollama-stream-error-event`

Return the decoded event associated with a stream error.

### `ollama-stream-error-line`

Return the one-based input line associated with a stream error.

### `open-openai-stream`

Open an OpenAI-compatible Server-Sent Events stream. The accepted options are
`:body`, `:timeout`, and `:headers`.

### `stream-next`

Return two values: the next decoded event and a true presence flag. Return
`nil, nil` at EOF or after `[DONE]`.

### `stream-events`

Consume a stream into a list. The stream is closed on normal completion, when
`:limit` stops consumption, and when event handling exits with an error.

### `stream-close`

Close a stream and release its response. Closing is idempotent and is the
client-level cancellation operation available for an in-flight stream. The
network boundary remains responsible for whether closing the response aborts
the underlying socket immediately.

### `stream-closed-p`

Return true after a stream has been closed.

### `stream-channel`

Bridge a stream to a `cl-concurrent-kit` channel. Return the channel and a
completion promise; the producer closes the stream at EOF or on error.

## Native API

### `generate`

Create a completion through `/generate`. The main arguments are `client`,
`model`, and `prompt`; native options include `:suffix`, `:images`, `:format`,
`:options`, `:system`, `:template`, `:context`, `:raw`, `:think`,
`:keep-alive`, `:logprobs`, and `:top-logprobs`, plus image-generation
dimensions.

### `generate-stream`

Stream a completion through `/generate` as NDJSON.

### `chat`

Create a chat completion through `/chat` from a model and message sequence.

### `chat-stream`

Stream a chat completion through `/chat` as NDJSON.

### `embed`

Create embeddings through the JSON-only `/embed` endpoint from a model and
string or string sequence. `:dimensions` must be an integer and `:keep-alive`
must be a duration string when supplied.

### `list-models`

List locally available models through `/tags`.

### `list-running-models`

List models currently loaded in memory through `/ps`.

### `show-model`

Return model details through `/show`; `:verbose` is optional.

### `create-model`

Create a model through `/create`.

### `create-model-stream`

Stream model creation status events through `/create`.

### `copy-model`

Copy a source model to a destination through `/copy`.

### `delete-model`

Delete a model through `/delete`.

### `pull-model`

Pull a model from a registry through `/pull`; `:insecure` is an optional
native request flag.

### `pull-model-stream`

Stream pull progress events through `/pull`.

### `push-model`

Push a model to a registry through `/push`; `:insecure` is an optional native
request flag.

### `push-model-stream`

Stream push progress events through `/push`.

### `blob-exists-p`

Check a digest with `HEAD /blobs/{digest}` and close the response before
returning.

### `push-blob`

Upload a string or octet vector to `/blobs/{digest}`. The caller owns and must
close the successful response.

### `web-search`

Search through Ollama Cloud's `/web_search` endpoint. The arguments are a
client, a non-empty query, and optional `:max-results` from 1 through 10.

### `web-fetch`

Fetch a URL through Ollama Cloud's `/web_fetch` endpoint. The result is a
decoded JSON object.

### `version`

Return the server version through `/version`.

## OpenAI-compatible API

### `make-openai-client`

Create a client whose default base URL is `http://localhost:11434/v1`. It
accepts the same boundary, authentication, limit, timeout, header, and
plain-HTTP options as `make-client`.

JSON endpoint helpers close successful responses before returning decoded
values, while stream helpers return caller-owned streams. For a custom path,
use the exported low-level transport function that matches the response shape;
there is no runtime mode-switching request adapter.

### `openai-model`

Return one model description through `/models/{model}`.

### `openai-models`

List models through `/models`.

### `openai-chat-completions`

Create a chat completion through `/chat/completions` from a JSON object body.

### `openai-chat-completions-stream`

Stream a chat completion through `/chat/completions` as SSE.

### `openai-completions`

Create a text completion through `/completions` from a JSON object body.

### `openai-completions-stream`

Stream a text completion through `/completions` as SSE.

### `openai-embeddings`

Create embeddings through `/embeddings` from a JSON object body.

### `openai-responses`

Create an experimental response through `/responses`.

### `openai-responses-stream`

Stream an experimental response through `/responses` as SSE.

### `openai-images`

Generate images through the experimental `/images/generations` endpoint from
a JSON object body. The body may contain `model`, `prompt`, `size`,
`response_format`, `n`, `quality`, `style`, and `user`. The endpoint returns
decoded JSON and has no streaming variant.
