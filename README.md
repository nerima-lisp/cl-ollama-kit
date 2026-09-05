# cl-ollama-kit

`cl-ollama-kit` is a transport-independent Common Lisp client for Ollama's
native API, OpenAI-compatible API, and Anthropic-compatible Messages API.
Applications provide the concrete network boundary, so HTTP, TLS, pooling,
and test doubles remain explicit at the application edge.

See the [full documentation](docs/src/index.md) for guides and the complete
API reference.

## Quick start

`application-network-boundary` below is an application-created
`cl-boundary-kit` network boundary.

```lisp
(asdf:load-system "cl-ollama-kit")
(defparameter *ollama*
  (ollama-kit:make-client
   :network-boundary application-network-boundary))
(ollama-kit:chat
 *ollama* "model"
 (list (ollama-kit:make-message "user" "Hello.")))
;; => a decoded JSON object
```

## Version 2.0 contract

Version 2.0 intentionally removes the legacy native `legacy-embeddings`
helper and `/api/embeddings` endpoint. Use `embed`, which targets the current
JSON-only `/api/embed` endpoint. The OpenAI-compatible `openai-embeddings`
helper and `/v1/embeddings` endpoint remain available. The experimental
`openai-images` helper targets `/v1/images/generations`.

## Install

Make the checkout and its ASDF dependencies available to the Common Lisp
implementation. `nix develop` provides the pinned development environment and
the runtime dependencies used by the system.

## Documentation

- [Getting started](docs/src/getting-started.md)
- [Native API guide](docs/src/guide/native-api.md)
- [OpenAI-compatible API guide](docs/src/guide/openai-compatible-api.md)
- [Anthropic-compatible API guide](docs/src/guide/anthropic-compatible-api.md)
- [API reference](docs/src/reference/api.md)
- [Conditions](docs/src/reference/conditions.md)
- [Architecture](docs/src/reference/architecture.md)

## Development

```sh
nix develop
sbcl --script run-tests.lisp
sbcl --script run-coverage.lisp
paredit inspect lint src t --dialect common-lisp --output json --stats
nix flake check
```

The tests use injected network boundaries and do not require a running model
service. Coverage writes an HTML report to a temporary directory unless
`CL_OLLAMA_KIT_COVERAGE_DIRECTORY` is set.

## Contributing

Keep public documentation concise and put detailed API material under
`docs/src/`. Follow the repository's contribution and documentation standards
when proposing changes.

## Support

Open an issue with a minimal reproduction, the request shape, and the boundary
behavior involved. Do not include credentials or private request data.

## License

MIT. See [LICENSE](LICENSE).
