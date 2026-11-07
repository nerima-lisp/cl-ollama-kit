# Conditions reference

Every client condition inherits from `<code>ollama-kit:ollama-error</code>`, except that `<code>ollama-idle-timeout</code>`, `<code>ollama-response-timeout</code>`, and `<code>ollama-cancelled</code>` inherit through `<code>ollama-transport-error</code>`. `<code>ollama-stream-error</code>` inherits from `<code>ollama-protocol-error</code>`. Conditions inherit their parent readers.

## Hierarchy and readers

| Condition | Parent | Readers |
| --- | --- | --- |
| `<code>ollama-error</code>` | `<code>error</code>` | `<code>ollama-error-message</code>` |
| `<code>ollama-argument-error</code>` | `<code>ollama-error</code>` | `<code>ollama-argument-error-detail</code>` |
| `<code>ollama-transport-error</code>` | `<code>ollama-error</code>` | `<code>ollama-transport-error-cause</code>` |
| `<code>ollama-response-timeout</code>` | `<code>ollama-transport-error</code>` | Inherits `<code>ollama-transport-error-cause</code>` |
| `<code>ollama-idle-timeout</code>` | `<code>ollama-transport-error</code>` | Inherits `<code>ollama-transport-error-cause</code>` |
| `<code>ollama-cancelled</code>` | `<code>ollama-transport-error</code>` | Inherits `<code>ollama-transport-error-cause</code>` |
| `<code>ollama-protocol-error</code>` | `<code>ollama-error</code>` | `<code>ollama-protocol-error-detail</code>` |
| `<code>ollama-stream-error</code>` | `<code>ollama-protocol-error</code>` | `<code>ollama-stream-error-event</code>`, `<code>ollama-stream-error-line</code>` |
| `<code>ollama-http-error</code>` | `<code>ollama-error</code>` | `<code>ollama-http-error-status</code>`, `<code>ollama-http-error-response</code>`, `<code>ollama-http-error-body</code>` |
| `<code>ollama-api-error</code>` | `<code>ollama-http-error</code>` | `<code>ollama-api-error-data</code>` |

## Condition details

- `<code>ollama-error</code>` is the root condition. `<code>ollama-error-message</code>` returns its human-readable message.
- `<code>ollama-argument-error</code>` signals an invalid client option, URL, request body, or endpoint argument. Its detail reader may hold the offending value or limit.
- `<code>ollama-transport-error</code>` signals a failure in the HTTP client. `<code>ollama-transport-error-cause</code>` returns the original transport condition.
- `<code>ollama-response-timeout</code>` signals that response headers did not arrive before the response timeout.
- `<code>ollama-idle-timeout</code>` signals that no body chunk arrived before the idle timeout.
- `<code>ollama-cancelled</code>` signals caller-requested cancellation. These three conditions inherit the transport cause reader.
- `<code>ollama-protocol-error</code>` signals invalid response data or stream framing. Its detail reader carries protocol-specific information when available.
- `<code>ollama-stream-error</code>` signals an error event received in a stream. Its event reader returns the decoded event. Its line reader is the one-based NDJSON input line; it is `<code>nil</code>` for SSE events.
- `<code>ollama-http-error</code>` signals a non-success HTTP response and preserves its status, response message, and decoded body when available.
- `<code>ollama-api-error</code>` is an HTTP error with a decoded Ollama API error value. `<code>ollama-api-error-data</code>` returns that value.

## Handling failures

Assume `<code>*client*</code>` is a configured `<code>ollama-kit</code>` client. This example handles an HTTP status without inspecting a transport-specific response:

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
