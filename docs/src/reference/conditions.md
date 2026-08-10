# Conditions reference

The package signals conditions that preserve the boundary, protocol, HTTP, and
API information needed by an application. All conditions inherit from
`ollama-kit:ollama-error`, whose message is available through
`ollama-kit:ollama-error-message`.

## Hierarchy

| Condition | Additional readers |
| --- | --- |
| `ollama-argument-error` | `ollama-argument-error-detail` |
| `ollama-transport-error` | `ollama-transport-error-cause` |
| `ollama-protocol-error` | `ollama-protocol-error-detail` |
| `ollama-http-error` | `ollama-http-error-status`, `ollama-http-error-response`, `ollama-http-error-body` |
| `ollama-api-error` | `ollama-api-error-data` |
| `ollama-stream-error` | `ollama-stream-error-event`, `ollama-stream-error-line` |

## Conditions

### `ollama-error`

The base condition for failures raised by the client. Read its human-readable
message with `ollama-kit:ollama-error-message`.

### `ollama-error-message`

Return the message stored on an `ollama-kit:ollama-error`.

### `ollama-argument-error`

Signals when a client, option, URL, body, digest, or other argument violates a
public contract. `ollama-kit:ollama-argument-error-detail` may contain the
offending value's type or limit. An HTTP response also signals this condition
when it contains both a materialized body and a stream.

### `ollama-argument-error-detail`

Return detail associated with an argument error.

### `ollama-transport-error`

Signals when the supplied network boundary fails before a valid response is
available. `ollama-kit:ollama-transport-error-cause` returns the original
condition.

### `ollama-transport-error-cause`

Return the underlying boundary failure.

### `ollama-protocol-error`

Signals when a response or stream cannot satisfy the expected protocol, such
as invalid UTF-8, invalid JSON, or an incompatible response shape.

### `ollama-protocol-error-detail`

Return protocol-specific detail, when available.

### `ollama-http-error`

Signals for a non-success HTTP status. The condition preserves the status,
response model, and materialized body when available.

### `ollama-http-error-status`

Return the numeric HTTP status.

### `ollama-http-error-response`

Return the associated response model.

### `ollama-http-error-body`

Return the response body associated with the error.

### `ollama-api-error`

Signals when a non-success response contains a decoded Ollama API error value.

### `ollama-api-error-data`

Return the decoded API error data.

### `ollama-stream-error`

Signals when a stream event cannot be decoded or validated. The stream is
closed before the condition is propagated.

### `ollama-stream-error-event`

Return the event value associated with the stream failure.

### `ollama-stream-error-line`

Return the one-based line number associated with the stream failure.

## Handling failures

Use a handler that branches on the typed condition and retains the readers
needed for logging or retry decisions. Retry policy belongs to the application
boundary: the client does not assume that a request is safe to repeat.

```lisp
(handler-case
    (ollama-kit:request-json *ollama* :get "/version")
  (ollama-kit:ollama-http-error (condition)
    (format *error-output* "HTTP status: ~A~%"
            (ollama-kit:ollama-http-error-status condition)))
  (ollama-kit:ollama-transport-error (condition)
    (format *error-output* "Transport failure: ~A~%"
            (ollama-kit:ollama-error-message condition))))
```
