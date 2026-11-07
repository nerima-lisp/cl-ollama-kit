# Development

The repository is an ASDF system with a Nix development environment. The client uses `cl-http-kit` directly; tests provide HTTP clients and responses without requiring a running Ollama service.

## Source layout

```text
src/
  package.lisp          exported package surface
  conditions.lisp       typed conditions and readers
  data-model.lisp       client settings and defaults
  model.lisp            client construction and cleanup
  input-limits.lisp     request and response bounds
  url-components.lisp   URL components and loopback detection
  url-validation.lisp   URL and request-path rules
  http-validation.lisp  HTTP message validation
  json.lisp             JSON objects and messages
  http-encoding.lisp    bounded request encoding
  http-decoding.lisp    response decoding and HTTP errors
  transport.lisp        cl-http-kit requests
  transport-timeouts.lisp timeout monitoring
  transport-response.lisp JSON and raw response helpers
  cps.lisp              continuation-passing entry points
  stream-core.lisp      synchronous stream requests and callbacks
  stream-framing.lisp   NDJSON line framing
  stream-parser.lisp    NDJSON and SSE event parsing
  native-*.lisp         native Ollama endpoint functions
  openai-api.lisp       OpenAI-compatible endpoint functions
  anthropic-api.lisp    Anthropic-compatible endpoint functions
t/
  *.lisp                unit, contract, edge-case, and coverage tests
```

The system definition in `cl-ollama-kit.asd` defines load order and test components. Native endpoint declarations use internal macros in `src/native-macros.lisp`; those macros are not exported API. Their generated functions call the shared validation, transport, and stream layers.

## Test commands

Run the test system with:

```sh
sbcl --script run-tests.lisp
```

Run coverage with:

```sh
sbcl --script run-coverage.lisp
```

The coverage script writes its report to a temporary directory by default. Set `CL_OLLAMA_KIT_COVERAGE_DIRECTORY` to choose another directory.

## Nix checks

Use the flake for the development shell and repository checks:

```sh
nix develop
nix flake check
```

The structural Lisp inspection command is:

```sh
paredit inspect lint src t --dialect common-lisp --output json --stats
```

## Documentation checks

Build the site from the repository root with strict link checking. The explicit output directory keeps generated files outside the checkout:

```sh
nix run nixpkgs#mkdocs -- build -f docs/mkdocs.yml -d /tmp/cl-ollama-kit-docs-site --strict
```

Keep the root README as a concise entry point, API details under `docs/src/reference/`, usage instructions under `docs/src/guide/`, and project process under `docs/src/project/`. Use package-qualified names in examples and relative Markdown links within the docs tree.
