# Getting started

Load the system through ASDF, create a client, and send requests to the local
Ollama service. This guide uses exported, package-qualified symbols.

## Load the system

Load `cl-ollama-kit` through ASDF. Its runtime dependencies include
`cl-http-kit/client`, `cl-http-message-kit`, `cl-sse-kit`, `cl-codec-kit`,
`cl-concurrent-kit`, and `cl-json-kit`. TLS support is optional and is not a
runtime dependency of `cl-ollama-kit`.

```lisp
(asdf:load-system "cl-ollama-kit")
```

The repository's Nix development shell provides the pinned development
environment:

```sh
nix develop
```

When loading the system from another REPL, make the checkout and its ASDF
dependencies discoverable through ASDF first.

## Create a client

`ollama-kit:make-client` creates an HTTP client when `:http-client` is omitted.
Its default base URL is `http://localhost:11434/api`.

```lisp
(defparameter *ollama*
  (ollama-kit:make-client
   :base-url "http://localhost:11434/api"))
```

Pass `:http-client` to use a caller-created `http-kit/client:http-client`.
Client options also include `:headers`, `:api-key`, `:timeout`,
`:response-timeout`, `:idle-timeout`, `:max-input-length`,
`:max-request-length`, and `:allow-insecure-http`. The defaults for response
and idle timeouts apply to streams. Stream endpoints accept per-call
`:response-timeout` and `:idle-timeout` overrides.

The client sends an API key as a Bearer authorization value. Do not combine
`:api-key` with an explicit Authorization header. The input and request size
limits default to 16 MiB each.

## Make a native request

Create chat messages with `ollama-kit:make-message`:

```lisp
(ollama-kit:chat
 *ollama*
 "model"
 (list (ollama-kit:make-message "user" "Hello.")))
;; => a decoded JSON object
```

Use `ollama-kit:json-object` for request values that are not covered by a
dedicated helper. Its arguments are alternating key and value pairs.

## Consume a stream

Streaming calls read events synchronously and invoke a callback once for each
decoded JSON object. The native API uses NDJSON. Return `:stop` from the
callback to cancel the active request and complete normally.

```lisp
(ollama-kit:chat-stream
 *ollama*
 "model"
 (list (ollama-kit:make-message "user" "Write a haiku."))
 (lambda (event)
   (format t "~S~%" event)))
```

The streaming call consumes the response before it returns.
The lower-level `ollama-kit:call-with-ollama-stream` entry point accepts an
HTTP method, relative path, callback, and request options. See the [conditions
reference](reference/conditions.md) for stream and timeout errors.

## HTTPS and plain HTTP

The default client speaks plain HTTP only. `make-client` signals
`ollama-kit:ollama-argument-error` for an HTTPS base URL without `:http-client`.
Load the optional `cl-http-kit/tls` system, create an HTTP client with TLS
support, and pass it to `make-client`:

```lisp
(asdf:load-system "cl-http-kit/tls")
(defparameter *https-http-client*
  (http-kit/client:make-http-client :default-timeout nil))

(defparameter *secure-ollama*
  (ollama-kit:make-client
   :base-url "https://localhost:11434/api"
   :http-client *https-http-client*))
```

The TLS client must trust the certificate presented by the service.
`cl-http-kit/tls` and its dependencies must be available through ASDF.

Base URLs must use HTTP or HTTPS and cannot contain a query or fragment.
Plain HTTP is allowed without `:allow-insecure-http` only for `localhost`,
`127.0.0.1`, and IPv6 loopback `[::1]`. Set `:allow-insecure-http t` to use
plain HTTP with any other host, including a private network address.

## Run the tests

The test suite does not require a live model service.

```sh
sbcl --script run-tests.lisp
```

For coverage, run `sbcl --script run-coverage.lisp` and inspect the generated
HTML report.

See [Migrating from 2.x](project/migrating-from-2.x.md) for the 3.0.0 public API
changes.
