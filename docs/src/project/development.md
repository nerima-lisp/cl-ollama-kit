# Development

The repository is an ASDF system with a Nix development environment. Source
and tests are intentionally transport-independent: the test suite supplies
network boundaries and request functions instead of requiring a live model
service.

## Source layout

```text
src/
  package.lisp          exported package surface
  conditions.lisp       typed conditions
  data-model.lisp       client, request, response, and stream models
  model.lisp            client construction and defaults
  input-limits.lisp     shared request, response, and stream limits
  url-components.lisp   URL parsing and authority/path components
  url-validation.lisp   base URL and request-path policy
  http-validation.lisp  response and header validation
  json.lisp              JSON objects and chat messages
  http-encoding.lisp     URL joining and bounded JSON request encoding
  http-decoding.lisp     UTF-8, JSON response decoding, and HTTP errors
  transport.lisp         boundary requests and response ownership
  cps.lisp               continuation-passing transport helpers
  stream-core.lisp       NDJSON and SSE stream opening
  stream-parser.lisp     event decoding
  stream.lisp            stream iteration and channel integration
  native-*.lisp          native Ollama endpoint helpers
  openai-api.lisp        OpenAI-compatible endpoint helpers
t/
  *.lisp                 unit, edge, contract, property, and coverage tests
```

The system definition in `cl-ollama-kit.asd` is the source of truth for the
load order and test component list.

Endpoint macros are the preferred extension point.  Add a declarative body
contract to the existing native or OpenAI macro family instead of introducing
a wrapper around `request-json`, `open-ollama-stream`, or the network boundary.
Keep structures and JSON objects in the data-model/codec layers, and keep
validation, transport, and stream ownership in their existing logic layers.

The test suite uses cl-weave directly: example tests cover concrete contracts,
`it-each` covers shared cases, property/fuzz tests exercise generated inputs,
continuation helpers verify CPS boundaries, and the runner enforces expression
and branch thresholds.  The coverage script also checks that the generated
coverage data and report directory are non-empty after the runner succeeds.

## Test commands

Run the complete test system with:

```sh
sbcl --script run-tests.lisp
```

The test boundary checks request construction, limits, URL policy, JSON
contracts, response ownership, native endpoints, OpenAI-compatible endpoints,
and both stream wire formats.

Run coverage with:

```sh
sbcl --script run-coverage.lisp
```

The coverage script writes an HTML report to a unique temporary directory by
default. Set `CL_OLLAMA_KIT_COVERAGE_DIRECTORY` to choose another report
directory. Every executable implementation file under `src/` is included in
the report and is subject to the 100% expression and branch thresholds passed
by `run-coverage.lisp`. The
load-time-only declarations in `package.lisp`, `conditions.lisp`, and
`data-model.lisp` are explicitly excluded because the public cl-weave runner
starts coverage after ASDF has loaded them; `native-macros.lisp` and its
runtime helpers remain covered. The report uses SB-COVER's expression and
branch metrics; it is not a separate line-coverage claim.

## Nix checks

Use the flake for a reproducible development shell and repository checks:

```sh
nix develop
nix flake check
```

The flake checks the package tests, 100% executable coverage threshold,
documentation build, formatting, and paredit structure on supported systems.
The shell also provides the structural Lisp tooling used by the project. Run
the local structural inspection explicitly with:

```sh
paredit inspect lint src t --dialect common-lisp --output json --stats
```

## Documentation checks

Documentation is built from `docs/mkdocs.yml` with the Material theme and
strict link checking:

```sh
mkdocs build --strict --config-file docs/mkdocs.yml
```

Keep the root README as a concise entry point. Put API details in
`docs/src/reference/`, conceptual material in `guide/`, and project process in
`project/`. Work notes belong under `docs/src/notes/`, which is intentionally
excluded from navigation.

## Contribution hygiene

Keep examples package-qualified, use relative `.md` links inside the docs tree,
and keep navigation focused on guides, reference, and project process. Run the
narrowest relevant Lisp and documentation checks before handing off a change.
