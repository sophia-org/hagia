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


### Pairing follow-up prepared (code only)

The separate `tests/sdk-9p-pairing` branch targets Sophia `3d8c4ac3` and keeps
Hagia product input `b3d84966`. All twelve owner cases keep their internal file
assertions; IPC parity is retired. The two pregraphics cases explicitly select
9P. Historical runtime/native IPC cases and comparative measurements no longer
qualify this candidate; `tools/sophia_pairing/SDK-MIGRATION.md` names the remaining
behavior gaps. A deliberately invalid executable digest prevents any run until
a fresh isolated build is bound. This follow-up has not compiled or run yet.


### 2026-09-27 protected SDK pairing qualification

The code-only follow-up above was subsequently bound and run. Hagia `69f427ab`
with C SDK `8decca1d` passed all 24 phases against Sophia `3d8c4ac3` plus the
Hagia-owned test overlay: twelve protected owner cases, two pregraphics cases,
and protocol/isolation/list/strict/layout/format checks. The fresh normal
development executable is pinned in pairing binding `6add5738`;
`hagia-sdk-pairing/run2/report.json` records matching initial and final identities.
Startup, automatic/control restart, checkpoint restore and profile rollback
now have SDK-backed owner-level evidence. Physical/native acceptance is not
claimed; the fixture supplies historical admission, CPU pixels and frontend
acknowledgements.

The first pairing run found a local-work wakeup defect: SDK submit, snapshot
and consume could leave a poll-first caller sleeping until a deadline or
forever. Deterministic idle-socket controls fail before `8decca1d` and pass
afterward, including return to idle without spinning. The corrected SDK is
vendored, and the refreshed Hagia dependency manifest is reviewed.

Keep h006 open for the behavior gaps named in
`tools/sophia_pairing/SDK-MIGRATION.md`, the reviewed-manifest release build
and installed acceptance. The 449-test local suite remains evidence for the
previous vendor; the new vendor has the strict C suite and protected pairing.
Formal models were not rerun. No live reload or installation occurred.


### Reviewed-closure artifact qualification

The immutable pair build at Hagia `69f427ab` / Narthex `50b9014d` succeeded
with the reviewed dependency manifests, staged toolchain and nested isolated
build. The exact resulting Hagia binary (SHA-256 `8c2fc4c4…728ddeae`) then
passed all 24 protected pairing phases against Sophia `3d8c4ac3` plus the
recorded overlay, with identical initial and final identities. See binding
`3653f12f`, `hagia-sdk-pairing/run3-reviewed/report.json` and the full digest
in `tools/sophia_pairing/compatibility.json`.

This closes the reviewed-artifact build and named protected owner exchange
checks. h006 stays open for the documented behavior gaps and installed/physical
acceptance; formal models were not rerun. Full desktop packaging still needs
the final Sophia/SDK/artifact pin alignment. No installation or live action
was performed.
