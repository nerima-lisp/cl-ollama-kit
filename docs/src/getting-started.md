# Getting started

Load the system through ASDF, create a client, and send requests to the local
Ollama service. This guide uses exported, package-qualified symbols.

## Load the system

Load `cl-ollama-kit` through ASDF. Its runtime dependencies include
`cl-http-kit/client`, `cl-http-message-kit`, `cl-sse-kit`, `cl-codec-kit`,
`cl-concurrent-kit`, and `cl-json-kit`.

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
The [API reference](reference/api.md#make-client) lists every client option,
its default, and its validation rule.

`:timeout` defaults to `nil`, so it sets no deadline for the whole HTTP
exchange. The default `:response-timeout` is 300 seconds and measures time to
response headers. The default `:idle-timeout` is 120 seconds and measures the
gap between response body chunks. These guards apply to streaming and
non-streaming requests. `cl-http-kit` has no connect-only timeout, so DNS
lookup and TCP connection setup are limited by the operating system.

Pass a finite `:timeout` to set one deadline for the entire exchange. For
example, `:timeout 3600` sets a one-hour limit. Choose a limit longer than the
generation you expect. A finite default could cancel a valid long generation
when the deadline expires. Streaming calls also accept per-call
`:response-timeout` and `:idle-timeout` overrides.

The client sends an API key as a Bearer authorization value. Do not combine
`:api-key` with an explicit Authorization header. `:max-input-length` limits
response data and `:max-request-length` limits encoded request bodies. Both
size limits default to 16 MiB.

## Make a native request

Create chat messages with `ollama-kit:make-message`:

Start the service at the configured URL and replace `"model"` with an
installed model name.

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
HTTPS requires a caller-supplied TLS-capable `:http-client`. With the dependency
versions pinned by this release, loading `cl-http-kit/tls` fails with
`CRYPTO-PROVIDER-UNAVAILABLE`, so this release has no tested HTTPS
configuration.

Base URLs must use HTTP or HTTPS and cannot contain a query or fragment.
They must have a valid authority and cannot contain userinfo. URLs passed to
`ollama-kit:web-fetch` must also use HTTP or HTTPS, have a valid authority, and
contain no userinfo or dot path segments.
Plain HTTP is allowed without `:allow-insecure-http` only for `localhost`,
`127.0.0.1`, and IPv6 loopback `::1` (written as `[::1]` in a URL). Set
`:allow-insecure-http t` to use plain HTTP with any other host, including a
private network address.

See [Migrating from 2.x](project/migrating-from-2.x.md) for the 3.0.0 public API
changes.
