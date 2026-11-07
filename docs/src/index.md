# cl-ollama-kit documentation

`cl-ollama-kit` is a Common Lisp client for Ollama's native API and its OpenAI-compatible and Anthropic-compatible endpoints. It uses `cl-http-kit` to send requests and `cl-http-message-kit` for HTTP request and response messages.

## Start here

- [Getting started](getting-started.md) covers client construction and common options.
- [Native API guide](guide/native-api.md) covers generation, chat, embeddings, model operations, blobs, and web search and fetch.
- [OpenAI-compatible API guide](guide/openai-compatible-api.md) covers the `/v1` endpoints.
- [Anthropic-compatible API guide](guide/anthropic-compatible-api.md) covers the `/v1/messages` endpoint.

## Reference

- [API reference](reference/api.md) lists the exported functions, client accessors, and streaming callbacks.
- [Conditions](reference/conditions.md) describes the condition hierarchy and its readers.
- [Architecture](reference/architecture.md) describes HTTP transport, request and response handling, and stream parsing.

## Project

- [Development](project/development.md) describes the source layout and local checks.
- [Migrating from 2.x](project/migrating-from-2.x.md) lists the removed and renamed exports.

## HTTP and TLS

The default HTTP client speaks plain HTTP. For HTTPS, create an `http-kit/client:http-client` with TLS support and pass it to `make-client` using `:http-client`. Non-loopback plain HTTP requires `:allow-insecure-http t`. See the [API reference](reference/api.md#client-and-transport) for the URL rules and the HTTPS call shape.
