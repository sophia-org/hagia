---
id: y8w28fvd
date: 2026-09-27
kind: investigation
status: implemented
tags: [investigation, lifecycle]
---
# Supervised stop preserves the last committed policy

## Question

How should Hagia stop when the supervisor sends SIGTERM to a component running
as PID 1 in a private namespace? Without a handler that process ignores the
signal, so a component replacement waits without observing an exit.

## Evidence

Hagia `bc99d1d` implements graceful stop; `b0594db` checks pipe creation,
uses volatile signal flags, and excludes Nim tracing/check machinery from
the handlers. Both are based on `69f427ab`, with C SDK `8decca1d` unchanged.
Logs and the sandbox launcher are retained under
`~/.local/state/sophia/development-evidence/component-sigterm/`:
`hagia-red-green.log`, `hagia-verify.log`, and `hagia-claude-report.md`.

## Finding and resolution

The handler records the signal and writes to a nonblocking, close-on-exec
pipe. The ordinary event loop polls it beside the SDK socket. Stop unwinds
the SDK connection, refuses new submissions, and returns success. An unsettled
projection is discarded without replay; only a committed outcome may update
the checkpoint. This is process cleanup, not a new protocol operation.

`pipe2` sets both required descriptor flags atomically. A setup failure
restores earlier signal dispositions and closes the new pipe. The handler's
generated C uses volatile integer flags and only a store and `write(2)`;
logging, allocation and exceptions stay outside it.

## Validation and remaining work

The full contributor gate at `b0594db` passed 458 Nim checks, the vendored SDK
checks, formatting/layout, Alloy and Z3 checks, and all four retained TLA+
models. The six binary-level tests cover bootstrap, idle SIGTERM/SIGINT,
unsettled custody, preservation of an existing checkpoint, and namespace PID 1.
All six fail against the old binary and pass at the new head; ten repeated
runs pass. Three additional tests inspect both pipe descriptors, idempotent
installation, and a real signal waking the pipe.

These tests use the SDK's scripted endpoint and developer Nim dependencies.
They establish h007's shutdown behavior, not a reviewed release build or a
restart in a live Sophia session. Failure rollback for `sigaction` is source
reviewed, without syscall fault injection. The tests do not independently
isolate the pipe from EINTR. Component preparation must refresh the reviewed
dependency manifest's source identity; no live restart was run by this work.

## Connections

The [environment contract](../../environment.md) documents the signal surface;
the [architecture](../../architecture.md) keeps checkpoint promotion with the
policy owner. The [test migration map](../../sdk-test-migration.md) distinguishes
the SDK fixture from a production-export or authenticated-launch proof.
