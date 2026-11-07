# Conditions reference

## Hierarchy and readers

| Condition | Parent | Readers |
| --- | --- | --- |
| `ollama-error` | `error` | `ollama-error-message` |
| `ollama-argument-error` | `ollama-error` | `ollama-argument-error-detail` |
| `ollama-transport-error` | `ollama-error` | `ollama-transport-error-cause` |
| `ollama-response-timeout` | `ollama-transport-error` | Inherits `ollama-transport-error-cause` |
| `ollama-idle-timeout` | `ollama-transport-error` | Inherits `ollama-transport-error-cause` |
| `ollama-cancelled` | `ollama-transport-error` | Inherits `ollama-transport-error-cause` |
| `ollama-protocol-error` | `ollama-error` | `ollama-protocol-error-detail` |
| `ollama-stream-error` | `ollama-protocol-error` | `ollama-stream-error-event`, `ollama-stream-error-line` |
| `ollama-http-error` | `ollama-error` | `ollama-http-error-status`, `ollama-http-error-response`, `ollama-http-error-body` |
| `ollama-api-error` | `ollama-http-error` | `ollama-api-error-data` |

## Condition details

- `ollama-error` is the root condition. `ollama-error-message` returns its human-readable message.
- `ollama-argument-error` signals an invalid client option, URL, request body, or endpoint argument. Its detail reader may hold the offending value or limit.
- `ollama-transport-error` signals a failure in the HTTP client. `ollama-transport-error-cause` returns the original transport condition.
- `ollama-response-timeout` signals that response headers did not arrive before the response timeout.
- `ollama-idle-timeout` signals that no body chunk arrived before the idle timeout.
- `ollama-cancelled` signals caller-requested cancellation.
- `ollama-protocol-error` signals invalid response data or stream framing. Its detail reader carries protocol-specific information when available.
- `ollama-stream-error` signals an error event received in a stream. Its event reader returns the decoded event. Its line reader is the one-based NDJSON input line; it is `nil` for SSE events.
- `ollama-http-error` signals a non-success HTTP response and preserves its status, response message, and decoded body when available.
- `ollama-api-error` is an HTTP error with a decoded Ollama API error value. `ollama-api-error-data` returns that value.

## Handling failures

Assume `*client*` is a configured `ollama-kit` client. This example handles an HTTP error by reading its status:

```lisp
(handler-case
    (ollama-kit:request-json *client* :get "/version")
  (ollama-kit:ollama-http-error (condition)
    (format *error-output* "HTTP status: ~A~%"
            (ollama-kit:ollama-http-error-status condition)))
  (ollama-kit:ollama-transport-error (condition)
    (format *error-output* "Transport failure: ~A~%"
            (ollama-kit:ollama-error-message condition))))
```

The client does not retry requests automatically. Put retry decisions in the application that knows whether the request can be repeated safely.
