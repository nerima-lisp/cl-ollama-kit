# Architecture reference

`cl-ollama-kit` separates request construction, network execution, decoding,
and stream ownership. The application supplies the network boundary; the
library provides the protocol-facing layers around it.

## Boundary ownership

`ollama-kit:make-client` and `ollama-kit:make-openai-client` require a
`cl-boundary-kit` network boundary. The boundary decides how sockets, DNS,
proxies, TLS, pooling, timeouts, and test doubles are implemented. The client
passes an `ollama-kit:http-request` to that boundary and expects an
`ollama-kit:http-response` back.

For request helpers, an omitted `:timeout` resolves to the client's configured
default; an explicit `:timeout nil` is passed through as `NIL`. The client does
not add a second deadline or read-idle timer above the boundary. Closing a
returned stream is the client-level cancellation and release operation, while
the boundary decides how promptly that close interrupts the underlying I/O.

The client also does not retry requests automatically. Retry, idempotency, and
backoff policy belong to the application or its boundary because several
Ollama operations mutate server state or submit non-repeatable work.

This arrangement keeps deployment policy visible and allows the same client
logic to run against production transport or an injected test boundary.

The boundary is the `cl-boundary-kit` protocol itself, not an additional
client-side adapter.  Request and response models remain data-only; transport,
decoding, and lifecycle functions consume those models directly.

Native endpoint declarations are data contracts expanded by
`define-native-json-endpoint` and `define-native-stream-pair`.  The latter
requires a literal one-argument body lambda and inlines its `NIL`/`T` branch at
macro expansion time.  This keeps request shape in the declaration while the
request and stream functions retain ownership of validation and I/O.

## Request and response models

`ollama-kit:make-http-request` and `ollama-kit:make-http-response` construct
small public models. A request records method, URL, headers, body, and whether a
streaming response is requested. A response contains a status and headers plus
either a materialized body or an incremental stream. A response close function
is retained so ownership can be released exactly once.

`ollama-kit:perform-request` exposes this transport layer directly.
`ollama-kit:request-json` consumes successful response bodies and returns
decoded JSON plus the response. High-level JSON endpoint helpers close that
response before returning their decoded value. `ollama-kit:request-raw` leaves
a successful response unconsumed for callers that need raw bytes or a custom
decoder.

## Codec layer

JSON request bodies are written through `cl-json-kit:write-json` with a
configured output bound, encoded as UTF-8, and checked again in octets against
the client's maximum request length. Response input is checked against the
maximum input length before JSON decoding. Invalid UTF-8 and invalid JSON
become typed `ollama-kit:ollama-protocol-error` conditions.

`ollama-kit:json-object` and `ollama-kit:make-message` keep JSON object and
message construction explicit. `ollama-kit:+json-unspecified+` distinguishes
an omitted field from an explicit false, zero, empty array, or JSON null.

## Streaming layer

Native helpers open NDJSON streams through
`ollama-kit:open-ollama-stream`. OpenAI-compatible helpers open SSE streams
through `ollama-kit:open-openai-stream`. `ollama-kit:stream-next` normalizes
both formats to an event plus a presence flag; EOF and `[DONE]` become
`nil, nil`.

The caller owns every returned stream. `ollama-kit:stream-close` is idempotent,
and `ollama-kit:stream-channel` provides a channel and completion promise for
applications that consume events concurrently.

All stream exit paths use the same safe-close policy.  A cleanup failure is
reported as a warning and never replaces the parser, transport, or producer
condition that caused the exit.

## Validation and security

Base URLs accept HTTP or HTTPS without query or fragment components. Non-
loopback plain HTTP requires an explicit `:allow-insecure-http t` opt-in.
Authorization values supplied through `:api-key` are added as Bearer headers;
an explicit Authorization header cannot be combined with that option.

Request and response-input limits default to 16 MiB. These limits protect the
codec boundary and can be configured independently on each client.

## Failure flow

Transport failures become `ollama-kit:ollama-transport-error`; malformed or
incompatible data becomes `ollama-kit:ollama-protocol-error`; non-success
statuses become HTTP or API conditions; and stream decoding failures preserve
the event and line number. See the [conditions reference](conditions.md).

The public `call-with-json` and `call-with-stream` functions are the CPS
boundary for callers that want explicit success and failure continuations.
Endpoint body construction stays data-oriented; transport and stream failures
are routed through those continuations without adding an adapter layer.
