# Development

The repository is an ASDF system with a Nix development environment. The client uses `<code>cl-http-kit</code>` directly; tests provide HTTP clients and responses without requiring a running Ollama service.

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
  transport.lisp        cl-http-kit requests and timeout monitoring
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

The system definition in `<code>cl-ollama-kit.asd</code>` defines load order and test components. Native endpoint declarations use internal macros in `<code>src/native-macros.lisp</code>`; those macros are not exported API. Their generated functions call the shared validation, transport, and stream layers.

## Test commands

Run the test system with:

```sh
sbcl --script run-tests.lisp
```

Run coverage with:

```sh
sbcl --script run-coverage.lisp
```

The coverage script writes its report to a temporary directory by default. Set `<code>CL_OLLAMA_KIT_COVERAGE_DIRECTORY</code>` to choose another directory.

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

Keep the root README as a concise entry point, API details under `<code>docs/src/reference/</code>`, usage instructions under `<code>docs/src/guide/</code>`, and project process under `<code>docs/src/project/</code>`. Use package-qualified names in examples and relative Markdown links within the docs tree.
