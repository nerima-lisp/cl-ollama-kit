# Anthropic-compatible API guide

Ollama exposes an Anthropic-compatible Messages API below `/v1/messages`.
Create a client with `ollama-kit:make-anthropic-client`; its default base URL
is `http://localhost:11434/v1`.

## Messages requests

The helper accepts a JSON object body. This keeps the compatibility surface
open to model, messages, system prompts, tools, vision content, thinking, and
new fields added by the server.

```lisp
(defparameter *anthropic*
  (ollama-kit:make-anthropic-client
   :api-key "local-development-key"
   :headers '(("anthropic-version" . "2023-06-01"))
   :network-boundary application-network-boundary))

(ollama-kit:anthropic-messages
 *anthropic*
 (ollama-kit:json-object
  "model" "model"
  "max_tokens" 128
  "messages"
  (vector (ollama-kit:make-message "user" "Hello."))))
;; => a decoded JSON object
```

`anthropic-messages` sends a `POST` request to `/messages`. The optional
`:timeout` and `:headers` arguments apply to the individual request.

## Server-Sent Events

Use `ollama-kit:anthropic-messages-stream` for the streaming form. It forces
the request's `stream` field to true and decodes the response as
`text/event-stream`.

```lisp
(let ((stream
        (ollama-kit:anthropic-messages-stream
         *anthropic*
         (ollama-kit:json-object
          "model" "model"
          "max_tokens" 128
          "messages"
          (vector
           (ollama-kit:make-message "user" "Stream a greeting."))))))
  (unwind-protect
       (ollama-kit:stream-events stream)
    (ollama-kit:stream-close stream)))
```

`ollama-kit:stream-next` returns each decoded SSE event and returns `nil, nil`
at end of input or after `[DONE]`. The caller owns the returned stream;
`stream-close` is idempotent and is the client-level cancellation operation.

## Authentication and boundaries

Pass `:api-key` to `ollama-kit:make-anthropic-client` to add an `X-API-KEY`
header. Supply `anthropic-version` or other compatibility headers through
`:headers`. The network boundary remains application-owned, and the client
does not select a socket or TLS implementation. Request limits, timeout
behavior, plain-HTTP policy, and retry policy follow the same transport
contract as the native and OpenAI-compatible clients.

See the [API reference](../reference/api.md) for request and response
ownership and the [conditions reference](../reference/conditions.md) for
failures.
