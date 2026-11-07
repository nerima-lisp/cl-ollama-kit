# Migrating from 2.x

Version 3.0.0 removes the network-boundary and pull-stream APIs. It does not provide compatibility aliases. The names below were exported by the 2.x package and are no longer exported by the current package.

## Client boundary

| Removed or renamed export | Current form |
| --- | --- |
| `client-network-boundary` | `client-http-client` |
| `call-with-stream` | Use the format-specific `call-with-ollama-stream`, `call-with-openai-stream`, or `call-with-anthropic-stream`. |

Construct clients with a `cl-http-kit` HTTP client. For HTTPS, build a TLS-enabled `http-kit/client:http-client` and pass it to `make-client` with `:http-client`. The default client speaks plain HTTP only. See the [API reference](../reference/api.md#client-and-transport).

## HTTP message model exports

The following request and response model names are no longer exported from `ollama-kit`:

- `make-http-request`
- `http-request-p`
- `http-request-method`
- `http-request-url`
- `http-request-headers`
- `http-request-body`
- `http-request-stream-p`
- `make-http-response`
- `http-response-p`
- `http-response-status`
- `http-response-headers`
- `http-response-body`
- `http-response-stream`
- `http-response-close-function`
- `response-success-p`
- `close-http-response`

HTTP request and response messages now use `cl-http-message-kit` types. The old `http-request-url` reader is replaced by `http-message-kit:http-request-uri`. `src/package.lisp` imports `make-http-request`, `http-request-p`, `make-http-response`, `http-response-p`, and the `http-response-status`, `http-response-headers`, and `http-response-body` readers from `http-message-kit`. These names are not re-exported by `ollama-kit`. The old stream and close-function fields are not part of the public `ollama-kit` API. Other low-level request and response helpers have no one-to-one replacement in the `ollama-kit` package; use the `http-message-kit` package's exported interface when a low-level message is needed.

## Response scope macros

- `with-http-response` is removed. Low-level response objects are message data and no longer expose the old close-function protocol.
- `with-json-response` is removed. Use `request-json` for its two returned values, or `call-with-json` when success and failure continuations fit the caller.

## Pull-stream API

The following stream object and reader functions are removed:

- `ollama-stream`
- `ollama-stream-p`
- `open-ollama-stream`
- `open-openai-stream`
- `open-anthropic-stream`
- `stream-next`
- `stream-events`
- `stream-close`
- `stream-closed-p`
- `stream-channel`

Use the synchronous format-specific callbacks `call-with-ollama-stream`, `call-with-openai-stream`, and `call-with-anthropic-stream`. Endpoint-specific `*-stream` functions take an event function and invoke it for each decoded event. Return `:stop` from the callback to cancel the request and finish normally. No stream object or channel bridge is returned.

`ollama-stream-error` and its readers remain exported. The condition reports server stream error events; it is separate from the removed stream object API.
