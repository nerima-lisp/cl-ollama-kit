# cl-ollama-kit documentation

`cl-ollama-kit` is a transport-independent Common Lisp client for Ollama's
native API, OpenAI-compatible API, and Anthropic-compatible Messages API. It
keeps the network boundary in the application, while providing request
models, JSON encoding, typed conditions, and NDJSON or Server-Sent Events
stream handling.

## Start here

- [Getting started](getting-started.md) explains system loading, client
  construction, limits, and stream ownership.
- [Native API guide](guide/native-api.md) covers generation, chat, embeddings,
  model lifecycle operations, blobs, and Ollama Cloud web search/fetch.
- [OpenAI-compatible API guide](guide/openai-compatible-api.md) covers the
  `/v1` request and streaming helpers.
- [Anthropic-compatible API guide](guide/anthropic-compatible-api.md) covers
  the `/v1/messages` request and streaming helpers.

## Reference

- [API reference](reference/api.md) lists the exported functions, structures,
  accessors, and conditions.
- [Conditions](reference/conditions.md) describes the error hierarchy and the
  information preserved by each condition.
- [Architecture](reference/architecture.md) describes the boundary, codec,
  transport, and stream layers.

## Design boundary

The core does not select a socket, DNS, proxy, TLS, or connection-pooling
implementation. The caller supplies a `cl-boundary-kit` network boundary to
`ollama-kit:make-client`, `ollama-kit:make-openai-client`, or
`ollama-kit:make-anthropic-client`. This keeps production policy and test
doubles visible where the application composes them.
