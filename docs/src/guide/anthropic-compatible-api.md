# Anthropic-compatible API guide

Ollama exposes an Anthropic-compatible Messages API below `/v1/messages`.
Create a client with `ollama-kit:make-anthropic-client`; its default base URL
is `http://localhost:11434/v1`.
Custom base URLs must use HTTP or HTTPS, have a valid authority, and omit user
information.
See [Getting started](../getting-started.md) for ASDF loading and client setup.

Replace `"model"` in the request examples with a model available through this
endpoint.

## Messages requests

The helper accepts a JSON object body. This allows fields for models, messages,
system prompts, tools, and other values accepted by the service.

```lisp
(defparameter *anthropic*
  (ollama-kit:make-anthropic-client
   :headers '(("anthropic-version" . "2023-06-01"))))

(ollama-kit:anthropic-messages
 *anthropic*
 (ollama-kit:json-object
  "model" "model"
  "max_tokens" 128
  "messages"
  (vector (ollama-kit:make-message "user" "Hello."))))
;; => a decoded JSON object
```

`anthropic-messages` sends a `POST` request to `/messages`. The per-call
`:timeout` and `:headers` arguments apply to an individual request.
`make-anthropic-client` maps `:api-key` to an `X-API-KEY` header.

## Server-Sent Events

Use `ollama-kit:anthropic-messages-stream` for a streaming request. It forces
the request's `stream` field to true and consumes the response synchronously.
The event callback receives each decoded JSON object. Return `:stop` from the
callback to cancel the active request and complete normally.

```lisp
(ollama-kit:anthropic-messages-stream
 *anthropic*
 (ollama-kit:json-object
  "model" "model"
  "max_tokens" 128
  "messages"
  (vector
   (ollama-kit:make-message "user" "Stream a greeting.")))
 (lambda (event)
   (format t "~S~%" event)))
```

Anthropic-compatible streams use Server-Sent Events parsed by `cl-sse-kit`.
An event must end with a blank line before EOF to be delivered. Stream calls accept
per-call `:timeout`, `:response-timeout`, `:idle-timeout`, `:headers`, and
`:cancel-token` options.

## Authentication and transport

Pass `:api-key` to `ollama-kit:make-anthropic-client` to add an `X-API-KEY`
header. Supply `anthropic-version` or other compatibility headers through
`:headers`.

The default client speaks plain HTTP. To use HTTPS, create a generic
`ollama-kit:make-client` with an HTTPS `/v1` base URL and a TLS-enabled
`:http-client` as described in [Getting started](../getting-started.md).
The generic constructor sends `:api-key` as a Bearer value, so set
`X-API-KEY` explicitly through `:headers` when using it for this API.
Anthropic-compatible endpoint functions accept that client.

Create a cancellation token with
`http-kit/client:make-http-cancellation-token` and pass it as `:cancel-token`
to a streaming call. Another thread can cancel it with
`http-kit/client:http-client-cancel-request`; the request signals
`ollama-cancelled`. If an event callback exits non-locally, the request is
cancelled and the connection is released.

See the [API reference](../reference/api.md) for client option defaults and
request and response details. See the [conditions reference](../reference/conditions.md)
for failures.
