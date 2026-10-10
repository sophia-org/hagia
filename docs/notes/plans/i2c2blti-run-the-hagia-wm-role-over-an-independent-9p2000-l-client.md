---
id: i2c2blti
date: 2026-09-25
kind: plan
tags: [plan, milestone]
---
# Run the Hagia WM role over an independent 9P2000.L client

## 2026-09-27 revised implementation boundary

The operator superseded the independent production-client design: one desktop
SDK per language owns every public role over standard 9P2000.L. Hagia uses thin
Nim bindings to the standalone C SDK, vendored with its signed commit and full
inventory. The old Nim codecs remain test oracles only. The product has no IPC
backend or fallback; old IPC endpoint selection refuses.

The migration retains pure policy tests and maps direct-client tests to SDK
controls in [the coverage map](../../sdk-test-migration.md). SDK `00897d8` fixes
receipt capability disclosure, `5b33b66` refuses impossible offers before
submission, and `93bdf3c` adds complete-held and partial-event timing controls.
The first two defects were found while preserving Hagia's adapter assertions.

The original scope below records the prior design, not a current instruction.
h006 stays open until the remaining paired acceptance is qualified. Local
SDK/policy tests and supplied-stream export tests do not establish authenticated
launch, native presentation, restart or installed desktop acceptance.

## Scope and exit

Hagia h006 is paired with Sophia t249 under niltempus's 2026-09-25 instruction
to implement the Hagia-first 9P plan. Implement an independent Nim 9P2000.L
client and the versioned binary WM records, using a direct Unix socket.
Preserve Hagia's standalone build and its existing policy, projection, actions,
overview and checkpoint behavior. The adapter stays thin and uses passive
types in `src/types`; no Sophia source or generated SDK becomes a dependency.

Only the WM role migrates initially. Separate output-control traffic remains
on the current protocol. The old WM transport remains an explicitly selected
fallback during development and remains the installed default. This task
authorizes no live reload, installation or hardware action.

## Task details

The shared contract is owned by Sophia t249. Hagia independently implements
its wire values and consumes its published corpus. Runtime records are compact
binary; derived text inspection does not create another mutation interface.
Snapshot reads remain pinned, proposals are explicitly submitted only after
complete bounded staging, and commits/checkpoints follow correlated semantic
outcomes rather than write acknowledgements. Lost replies cannot repeat an
effect; reconnect starts a fresh epoch and cannot restore stale input authority.

First prove startup/profile activation, one snapshot and proposal through real
Session commit, then expand to all current WM behavior: layouts/workspaces,
focus/sizing/fullscreen/floating, actions and session operations, launch origins,
multi-output/topology, reload/rollback, overview receipts and source updates,
timeout/restart and stale epoch refusal. Pin ordinary model/projection equality
between transports. Preserve red controls and exact paired binary identities.

Run Nim builds serially, format touched Nim files with nph, and run layout plus
the contributor/cross-repository gates in isolated worktrees. Claimed native
presentation must come from its actual owner; synthetic completions remain
development evidence. The director owns the paired gate and merge windows.

Hagia-specific cross-project assertions belong here, not in Sophia's mandatory
tests. `tools/sophia_pairing` is an optional gate over a pinned Sophia source
revision plus a hashed test-only overlay in an isolated checkout. It retains
private Session-owner access without a public production test API. Evidence
must name both the base and overlay, refuse missing/zero tests, and pin the
normal Hagia executable. `nimble test` and product builds do not depend on this
optional owner-level fixture. Generic protocol, reducer, admission and backend
controls remain Sophia-owned.

## Connections

- [Session drag accounting and measurement evidence](../investigations/tzz6apym-session-drag-measurements-retain-admission-and-settlement-accounting.md).
- [Optional external acceptance ownership and evidence](../investigations/aoivl2yn-hagia-specific-acceptance-lives-in-an-optional-source-pinned-pairing-overlay.md).
- [Independent client checkpoint](../investigations/uof7k0rr-independent-hagia-9p-client-bounds-request-and-reply-custody.md)
  records the transport-only controls and remaining role integration.
- [Architecture](../../architecture.md), unchanged WM-only boundary.
- [Work tracking](../../work-tracking.md), h006 owns this client work.
- Sophia plan `docs/notes/plans/80blhke8-migrate-the-hagia-wm-role-to-admitted-9p2000-l-files.md`
  owns t247 foundation, t248 Session adapter and t249 paired role acceptance.


### 2026-09-27 local qualification

The signed C SDK pin is `93bdf3c3b47c837af79023bec482760e1f1ceb80`.
The final local gate passed 449 Nim tests, strict vendored SDK checks and CLI
checks. The actual SDK PolicyWire peer passed startup and cycle against
Sophia `3d8c4ac3`'s production file export (2/2). Admission and policy outcomes
are supplied by that fixture; authenticated Session launch remains open.
Evidence is in `hagia-c-sdk/full-local-run1.log` and
`hagia-c-sdk/sdk-export-final-run1.log` under the development evidence directory.
The SDK timing run's first failure was a test expectation of FAILED instead of
CLOSED; the corrected run passed. The previous receipt/bootstrap guard-removal
controls failed as required. All failed logs remain available.

No formal-model rerun, reviewed release build, installation or live reload is
claimed. Keep h006 open for the remaining paired acceptance and release work.

### 2026-10-10 current SDK lifecycle slice

Hagia `870bfc68b3d2d8c1239f9f853f63ddb6557bd04a` adds the external
[`tests/external/lifecycle.rs`](../../../tests/external/lifecycle.rs) assertions.
niltempus runner `dbda3009b389ab4bd9aec6dce81fd4d5b10ce1c9` mounts them in an
explicit archived Sophia `0f2ad2386baa063ab92d9567a145148f5232bccb` test overlay.
The production sources and frozen `tools/sophia_pairing` runner are unchanged.
The built ordinary Hagia uses vendored SDK `b2a254dcb792e5f9d66f78bdd73f645153504507`.

All three named cases pass: protected startup/profile/catalog; accepted profile
replacement followed by real view-count rejection and rollback; and automatic
recovery after terminating the fixture child followed by requested restart.
Each successor answers the Session-queued scene and then sends its own
checkpoint reconciliation Dirty. Epochs, peer changes, profile/catalog and
unchanged checkpoint custody are asserted. This is an **empty headless scene**,
not occupied-window, focus, native receipt or physical input qualification.
Requested restart calls its production owner directly, not the control socket.
Protection is supervisor evidence, not independent namespace inventory or Tauth.

Under `~/.local/state/sophia/development-evidence/`:

- `t249-sdk-lifecycle-01`: `PASS lifecycle=3 native=false`; self-excluding
  manifest SHA256 `b5ac4542073194c5ba27200a292862eb77489624236549f2b40add43c9df23c6`.
  The ordinary binary SHA256 is
  `20581c96e823240460fa09e863f779de53a4851080cefabaa4e46b22172ff5f4`.
- `t249-sdk-lifecycle-controls-02`: disabled checkpoint restore in a separate
  Hagia copy causes exactly the restart case to fail on its missing fresh
  projection; binary/test/fixture inputs are hashed before and after. Manifest
  SHA256 `6bbfd791ec39a0f752b2bc63682bd3cd29b4f92df296378838294bdab9557aa5`.
  `controls-01` retains the mutation/build and initial development control.
- `t249-sdk-lifecycle-checks-01`: overlay Session clippy with warnings denied
  and the external runner controls. The runner refuses absent, zero or duplicate
  test listings, records nonzero steps, and detects changed closed records.

Development run 01 omitted the native-session feature and correctly stopped on
zero tests. Runs 02/03 exercised the evolving fixture; only the final clean,
committed fixture run above is the qualification record. This tests-only slice
did not rerun the full Nim/product/formal gates, build a release, install or
reload anything. h006/t249 remain open for capability-to-evidence mapping,
occupied-state and remaining lifecycle joins, and the reviewed measurement
method. Keep the old refused measurement campaign and historical runner intact.
