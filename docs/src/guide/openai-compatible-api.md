# OpenAI-compatible API guide

Ollama exposes an OpenAI-compatible API below `/v1`. Create a separate client
with `ollama-kit:make-openai-client`; its default base URL is
`http://localhost:11434/v1`.

## JSON requests

The endpoint helpers use the JSON transport directly and accept a JSON object
body:

```lisp
(defparameter *openai*
  (ollama-kit:make-openai-client
   :network-boundary application-network-boundary))

(ollama-kit:openai-chat-completions
 *openai*
 (ollama-kit:json-object
  "model" "model"
  "messages"
  (vector (ollama-kit:make-message "user" "Hello."))))
;; => a decoded JSON object
```

The available JSON helpers map to these paths:

| Helper | Path | Purpose |
| --- | --- | --- |
| `openai-models` | `/models` | List models. |
| `openai-model` | `/models/{model}` | Return one model description. |
| `openai-chat-completions` | `/chat/completions` | Create a chat completion. |
| `openai-completions` | `/completions` | Create a text completion. |
| `openai-embeddings` | `/embeddings` | Create embeddings. |
| `openai-responses` | `/responses` | Create an experimental response. |
| `openai-images` | `/images/generations` | Generate images through the experimental endpoint. |

`openai-images` forwards the JSON body to Ollama's experimental image
generation endpoint. The documented fields are `model`, `prompt`, `size`,
`response_format` (currently `b64_json`), `n`, `quality`, `style`, and `user`.
The endpoint returns decoded JSON and does not have a streaming helper.

## Server-Sent Events

The streaming pairs are `ollama-kit:openai-chat-completions-stream`,
`ollama-kit:openai-completions-stream`, and
`ollama-kit:openai-responses-stream`.

They force the request's `stream` field to true and decode
`text/event-stream`. `ollama-kit:stream-next` returns each decoded event and
returns `nil, nil` after the `[DONE]` marker or end of input.

```lisp
(let ((stream
        (ollama-kit:openai-chat-completions-stream
         *openai*
         (ollama-kit:json-object
          "model" "model"
          "messages"
          (vector (ollama-kit:make-message "user" "Stream a greeting."))))))
  (unwind-protect
       (ollama-kit:stream-events stream)
    (ollama-kit:stream-close stream)))
```

## Authentication and boundaries

Pass `:api-key` to `ollama-kit:make-openai-client` to add a Bearer
Authorization value. The same request limits, timeout, headers, and
plain-HTTP policy as the native client apply. The network boundary remains
application-owned; this client does not select a socket or TLS implementation.
Omitting `:timeout` uses the client default, while an explicit `:timeout nil`
passes `NIL` through to the boundary. Stream cancellation is performed with
`ollama-kit:stream-close`; deadline enforcement, read-idle timeouts, pooling,
and retries remain boundary or application policy.

See the [API reference](../reference/api.md) for lower-level request and
response ownership and the [conditions reference](../reference/conditions.md)
for failures.
