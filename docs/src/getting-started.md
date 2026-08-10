# Getting started

This page takes a checkout from system loading to a first request. The examples
use package-qualified exported symbols and assume that
`application-network-boundary` is a boundary supplied by the application.

## Load the system

Load `cl-ollama-kit` version 2.0.0 through ASDF. Its four runtime dependencies
are declared by `cl-ollama-kit.asd`: `cl-boundary-kit`, `cl-codec-kit`,
`cl-concurrent-kit`, and `cl-json-kit`.

The test system additionally depends on `cl-weave` 1.3.0 for executable tests
and coverage instrumentation; it is not part of the runtime dependency set.

```lisp
(asdf:load-system "cl-ollama-kit")
```

The repository's Nix development shell provides the pinned development
environment:

```sh
nix develop
```

The standalone test and coverage runners initialize a local ASDF source
registry for this checkout and sibling `nerima-lisp` dependencies. When
loading the system from another REPL, make those systems discoverable through
ASDF first; the Nix shell provides the pinned development environment.

## Create a client

`ollama-kit:make-client` requires a network boundary. The default native base
URL is `http://localhost:11434/api`; pass `:base-url` when the service is
located elsewhere.

```lisp
(defparameter *ollama*
  (ollama-kit:make-client
   :base-url "http://localhost:11434/api"
   :network-boundary application-network-boundary))
```

The client accepts `:headers`, `:timeout`, `:api-key`,
`:max-input-length`, and `:max-request-length`. An API key is sent as a Bearer
authorization value. Do not combine `:api-key` with an explicit Authorization
header.

If a request omits `:timeout`, the client default is passed to the network
boundary. An explicit `:timeout nil` disables that client default for the
request. The boundary owns actual deadline enforcement and socket behavior;
close a returned stream with `stream-close` when the application cancels it.

## Make a native request

Chat messages are JSON objects created with `ollama-kit:make-message`.

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

Native streams use NDJSON. `ollama-kit:stream-next` returns an event and a
presence flag; at end of input it returns `nil, nil`. The caller owns the
stream and should close it even when processing signals an error.

```lisp
(let ((stream (ollama-kit:chat-stream
               *ollama* "model"
               (list (ollama-kit:make-message "user" "Write a haiku.")))))
  (unwind-protect
       (loop
         (multiple-value-bind (event present-p)
             (ollama-kit:stream-next stream)
           (unless present-p (return event))
           (format t "~A~%" event)))
    (ollama-kit:stream-close stream)))
```

`ollama-kit:stream-events` collects events into a list, and
`ollama-kit:stream-channel` bridges a stream to a `cl-concurrent-kit` channel
and completion promise.

The client does not impose a separate read-idle timer or automatic retry
policy. Configure those policies in the application-owned network boundary,
where the concrete HTTP implementation can safely enforce them.

## Limits and transport security

The default maximum request length and response-input length are both 16 MiB.
Set `:max-request-length` and `:max-input-length` to different positive
limits when the application needs another policy.

Base URLs use HTTP or HTTPS and cannot contain a query or fragment. Plain HTTP
to a non-loopback address requires `:allow-insecure-http t`; use HTTPS for
remote services whenever possible.

## Run the tests

The test suite uses injected boundaries and does not need a live model service.

```sh
sbcl --script run-tests.lisp
```

For coverage, run `sbcl --script run-coverage.lisp` and inspect the generated
HTML report.
