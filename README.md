# cl-ollama-kit

`cl-ollama-kit` is a Common Lisp client for Ollama's native API and its
OpenAI-compatible and Anthropic-compatible APIs. It uses `cl-http-kit` for
HTTP requests and `cl-http-message-kit` for HTTP message values.

See the [full documentation](docs/src/index.md) for guides and the API
reference.

## Quick start

Load the ASDF system, create a client, and send a chat request to the default
local endpoint:

Start the local Ollama service and replace `"model"` with the name of an
installed model before running the request.

```lisp
(asdf:load-system "cl-ollama-kit")
(defparameter *ollama* (ollama-kit:make-client))

(ollama-kit:chat
 *ollama*
 "model"
 (list (ollama-kit:make-message "user" "Hello.")))
;; => a decoded JSON object
```

The default client speaks plain HTTP and uses `http://localhost:11434/api`.
See [Getting started](docs/src/getting-started.md) for transport configuration,
HTTPS, and streaming.

## Version 3.0

Version 3.0 uses `cl-http-kit` directly. The 2.x network-boundary option and
stream objects are removed. Streaming uses synchronous callbacks, and there is
no backward-compatibility layer. See [Migrating from 2.x](docs/src/project/migrating-from-2.x.md).

## Install

Make the checkout and its ASDF dependencies available to the Common Lisp
implementation. `nix develop` provides the pinned development environment.

## Documentation

- [Getting started](docs/src/getting-started.md)
- [Native API guide](docs/src/guide/native-api.md)
- [OpenAI-compatible API guide](docs/src/guide/openai-compatible-api.md)
- [Anthropic-compatible API guide](docs/src/guide/anthropic-compatible-api.md)
- [API reference](docs/src/reference/api.md)
- [Conditions](docs/src/reference/conditions.md)
- [Architecture](docs/src/reference/architecture.md)
- [Migrating from 2.x](docs/src/project/migrating-from-2.x.md)

## Development

```sh
nix develop
sbcl --script run-tests.lisp
sbcl --script run-coverage.lisp
paredit inspect lint src t --dialect common-lisp --output json --stats
nix flake check
```

The test suite does not require a running model service. Coverage writes an
HTML report to a temporary directory unless
`CL_OLLAMA_KIT_COVERAGE_DIRECTORY` is set.

## Contributing

## Support

Open an issue with a minimal reproduction, the request shape, and the HTTP
behavior involved. Do not include credentials or private request data.

## License

MIT. See [LICENSE](LICENSE).
