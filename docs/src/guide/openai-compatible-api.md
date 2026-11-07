# OpenAI-compatible API guide

Ollama exposes an OpenAI-compatible API below `/v1`. Create a client with
`ollama-kit:make-openai-client`; its default base URL is
`http://localhost:11434/v1`.

Replace `"model"` in the request examples with a model available through this
endpoint.

## JSON requests

`openai-chat-completions` accepts a JSON object body:

```lisp
(defparameter *openai*
  (ollama-kit:make-openai-client))

(ollama-kit:openai-chat-completions
 *openai*
 (ollama-kit:json-object
  "model" "model"
  "messages"
  (vector (ollama-kit:make-message "user" "Hello."))))
;; => a decoded JSON object
```

`openai-models` lists models, and `openai-model` takes a model name. The other
JSON request helpers take a JSON object body. The helpers map to these paths:

| Helper | Path | Purpose |
| --- | --- | --- |
| `ollama-kit:openai-models` | `/models` | List models. |
| `ollama-kit:openai-model` | `/models/{model}` | Return one model description. |
| `ollama-kit:openai-chat-completions` | `/chat/completions` | Create a chat completion. |
| `ollama-kit:openai-completions` | `/completions` | Create a text completion. |
| `ollama-kit:openai-embeddings` | `/embeddings` | Create embeddings. |
| `ollama-kit:openai-responses` | `/responses` | Create an experimental response. |
| `ollama-kit:openai-images` | `/images/generations` | Send a request to the experimental image endpoint. |

`openai-images` forwards its JSON body and returns a decoded JSON object. It
does not have a streaming helper.

## Server-Sent Events

The streaming helpers are `ollama-kit:openai-chat-completions-stream`,
`ollama-kit:openai-completions-stream`, and
`ollama-kit:openai-responses-stream`. Each takes a client, JSON request body,
and event callback. It forces the request's `stream` field to true and
consumes the response synchronously. The callback receives each decoded JSON
object. Return `:stop` from the callback to cancel the active request and
complete normally.

```lisp
(ollama-kit:openai-chat-completions-stream
 *openai*
 (ollama-kit:json-object
  "model" "model"
  "messages"
  (vector (ollama-kit:make-message "user" "Stream a greeting.")))
 (lambda (event)
   (format t "~S~%" event)))
```

OpenAI-compatible streams use Server-Sent Events parsed by `cl-sse-kit`.
An event must end with a blank line before EOF to be delivered. The final
`[DONE]` data marker ends the stream without invoking the callback for that
marker.

## Authentication and transport

Pass `:api-key` to `ollama-kit:make-openai-client` to add a Bearer
Authorization value. The constructor also accepts `:headers`, `:timeout`,
`:max-input-length`, `:max-request-length`, and `:allow-insecure-http`.
Streaming calls accept per-call `:timeout`, `:response-timeout`,
`:idle-timeout`, `:headers`, and `:cancel-token` options.

The default client speaks plain HTTP. To use HTTPS, create a generic
`ollama-kit:make-client` with an HTTPS `/v1` base URL and a TLS-enabled
`:http-client` as described in [Getting started](../getting-started.md).
OpenAI-compatible endpoint functions accept that client. The same
`:allow-insecure-http` rule applies to generic clients.

See the [API reference](../reference/api.md) for lower-level request and
response details and the [conditions reference](../reference/conditions.md)
for failures.
