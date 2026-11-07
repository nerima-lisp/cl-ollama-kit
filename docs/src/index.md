# cl-ollama-kit documentation

`<code>cl-ollama-kit</code>` is a Common Lisp client for Ollama's native API and its OpenAI-compatible and Anthropic-compatible endpoints. It uses `<code>cl-http-kit</code>` to send requests and `<code>cl-http-message-kit</code>` for HTTP request and response messages.

## Start here

- [Getting started](getting-started.md) covers client construction and common options.
- [Native API guide](guide/native-api.md) covers generation, chat, embeddings, model operations, blobs, and web search and fetch.
- [OpenAI-compatible API guide](guide/openai-compatible-api.md) covers the `<code>/v1</code>` endpoints.
- [Anthropic-compatible API guide](guide/anthropic-compatible-api.md) covers the `<code>/v1/messages</code>` endpoint.

## Reference

- [API reference](reference/api.md) lists the exported functions, client accessors, and streaming callbacks.
- [Conditions](reference/conditions.md) describes the condition hierarchy and its readers.
- [Architecture](reference/architecture.md) describes HTTP transport, request and response handling, and stream parsing.

## Project

- [Development](project/development.md) describes the source layout and local checks.
- [Migrating from 2.x](project/migrating-from-2.x.md) lists the removed and renamed exports.

## HTTP and TLS

The default HTTP client speaks plain HTTP. For HTTPS, create an `<code>http-kit/client:http-client</code>` with TLS support and pass it to `<code>make-client</code>` using `<code>:http-client</code>`. Non-loopback plain HTTP requires `<code>:allow-insecure-http t</code>`. See the [API reference](reference/api.md#client-and-transport) for the URL rules and the HTTPS call shape.
