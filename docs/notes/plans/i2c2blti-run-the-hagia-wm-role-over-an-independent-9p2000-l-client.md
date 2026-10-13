---
id: i2c2blti
date: 2026-09-25
kind: plan
tags: [plan, milestone]
---
# Run the Hagia WM role over an independent 9P2000.L client

## 2026-10-12 requested restart at the presentation-service boundary

The twenty-second external case reuses the mirror-target prefix, then requests
replacement through Session's authenticated control-restart admission. Before
any replacement poll, the actual presentation-service owner revokes the exact
identity and removes runtime policy while the old peer is alive and its epoch
unchanged. Availability remains true. Both simulated mirror heads retire the
replacement before the fixture polls restart; the stopping service must still
settle Withdrawn once. These queued receipts do not claim old-peer delivery.

The successor authenticates, preserves the committed scene/checkpoint, returns
chord credit and answers both recovery cycles without reopening the switcher.
The final peer health check is not a round trip. Initial installation and
Presented observation retain the supplied-head and abbreviated-helper limits;
CPU sources, head completion and the interleaving remain fixture-driven.

The initial run `t249-stop-dev01` passes twenty-two cases. The tightened version
adds the final health check and removes a redundant borrow; `t249-stop-dev02`
also passes twenty-two. Their manifest SHA-256 values are respectively
`d91a33818efadb361ec015bcb4a249c683c05df86e20370e0c0220e5829136b6` and
`0d8051f3068c15d6811321a78d079a217ff65cad2c28f3c54245fc77e2d0b736`.

Both archived single-site controls compile, exit 101 and fail their own named
assertion with one failed test. `t249-stop-revoke-control01` omits stopping
from the revoke condition; manifest
`07ef43b33f0db5eb8eec65d650fafbb5c808bcc637df4090df6f07290facf88e`.
`t249-stop-settle-control01` blocks settlement while stopping; manifest
`1cf1079b9f16c3c38cd876a6b9fd3ac6632b61b899c6aff0eea7fa7a55810ea4`.
Both hold source and Cargo leases and verify pinned source, restoration,
unchanged mounted inputs and the ordinary Hagia binary.

`t249-stop-checks01` passes restored-overlay strict Clippy, fixture/runner
formatting, fourteen runner tests (one child fixture ignored) and `nimble layout`;
manifest `b16e0739562af850fb3e4e2208070ea85141fc88309578d5d10bf9d31ca27b39`.

The clean signed pair (Hagia `cee1534`, niltempus `b92bc80`, Sophia `1b476dbdc`)
passes all twenty-two in `t249-stop-01`; manifest
`3c87489510d20ea3b3a3b932cf01a31e654a0f77ef9e8cd561f58bf8c223938c`.
`t249-stop-audit01` checks 3,257 pinned crate/Cargo/vendor inputs, the mount and
fifteen external modules, unchanged fixture bytes from development 02 and both
controls, twenty-two passing results, signatures and six package manifests;
manifest `f5d6bec8a28be815040f92d2a1ed7f59bab82b52ee22f3b5093b1c07ffed7b01`.
Leased cleanup removes the disposable build root; evidence retains executable
paths and hashes only. This is scoped qualification, not a full product gate.

Backend-notification handling remains open: headless availability/install
fallbacks could mask a missing handler. This case instead isolates stopping by
keeping it true at the install gate while mutating only its revocation use.
No production source, new API or installed-session change. h006/t249 retain
their remaining capability, native-owner and measurement exits.

## 2026-10-12 production presentation-service join

The twenty-first external case calls Session's actual presentation-service
owner after both simulated mirror heads produce a backend-derived Presented.
Supplied availability loss revokes the exact identity and removes the runtime
publication. The first correlated real-Hagia answer closes the switcher without
changing focus. Completed replacement frames cannot settle Withdrawn while
unavailable; restoring availability settles it once. The existing revocation
case's request-correlation helper is shared without changing its behavior.

`t249-service-dev01` passes all twenty-one cases on Sophia `1b476dbdc`;
self-excluding manifest SHA-256:
`a1daa9c0ffa871a8e6c469dc02590e1e258622166041c450523ef532d463a65c`.
Three single-site archived-source controls compile and fail with exit 101 at
their own named assertion, one failed test each:

| Package | Removed behavior | Manifest SHA-256 |
| --- | --- | --- |
| `t249-service-revoke-control01` | Availability-based revocation | `bcb88630e1a781051a9aa0f7d6360146f7e1e1f326f70320e92c4cd6c990284c` |
| `t249-service-remove-control01` | Runtime publication removal | `6a9869175db99c7cea08529a780e01619410c6902173dc3d754f7cb14926f168` |
| `t249-service-settle-control01` | Availability gate on withdrawal settlement | `c14478587818244cf74448794e5f03e82ca59c91ce978ea3d8d1e5a88be6e6ab` |

Each control holds the source and Cargo leases, verifies the pinned production
file, and checks restored source, all fifteen mounted modules and the unchanged
Hagia binary. The initial install still uses a supplied head, and its Presented
observation uses the abbreviated helper. The new direct calls qualify only
availability loss and withdrawal. Stopping/authentication conditions,
backend-initiated revocation, native install and repaint scheduling remain open.
The availability trigger and device submit/flip are supplied; there is no
physical-display claim. Availability alone leaves the chord open. No production
or installed code changes, and h006/t249 remain open.

Restored-overlay strict Clippy, fixture/runner formatting, fourteen runner tests
(one internal child fixture ignored), and `nimble layout` pass in
`t249-service-checks01`; manifest
`f3bf51ae41a3a1a384df626e8073daa1299a0d4399e034bdfa9e03d0dd1e5603`.

The clean signed pair (Hagia `351da95`, niltempus `cd22bed`, Sophia `1b476dbdc`)
passes all twenty-one in `t249-service-01`; manifest
`8b2041d439cd7c420a96fdd2c308fbee035b9488269e39f986c8ddd6ef7d49c0`.
`t249-service-audit01` verifies 2,937 pinned crate/Cargo inputs, the mount and
fifteen external modules, unchanged fixture bytes from development/controls,
twenty-one exact passing results, both signatures and six package manifests.
Audit manifest: `442f61af02ddb23cd1e888523250a293a84352371040c5464d640de120b2f1a7`.
Leased cleanup removes the disposable source/build root. No binaries are copied
into the evidence packages. These are scoped checks, not full product gates.

## 2026-10-12 authenticated baseline refresh

The nineteen external cases now use Session's authenticated startup and
replacement owners against Sophia `1b476dbdcc30215fe7ee5841e5a872f136ebb3a0`.
The generic Factotum fixture supplies trusted Session channel admission;
Hagia performs its ordinary launch-relay conversation. Restart waits drive
authentication and observations require an active launch registration.
AbortSettlement still fences replacement until settlement, then waits for
authentication before asserting the successor epoch.

Development run `t249-authenticated-dev01` passes all nineteen cases. Its
self-excluding manifest verifies and has SHA-256
`e775ad10b50defd338b72f88771195eba86eca9134e4b855b9398a0e8e5df6ed`.
The external runner's thirteen unit tests pass (one child fixture is ignored
for direct invocation), formatting and `nimble layout` pass. The clean signed
pair (Hagia `8e36eab`, niltempus `347d115`, the same Sophia pin) passes all
nineteen cases in `t249-authenticated-01`, verified manifest
`0370ecddf6e24cdd4d8a91553e546c19695e65c09c55e190d0bc6b83ae47c0c2`.
Historical controls retain their original pins;
they have not been re-executed for this refresh. No production Hagia change or
installed-session change. The remaining backend joins and measurement exits
keep h006/t249 open.

## 2026-10-12 software-Present admission join

The twentieth external case shares the CPU admission fixture with the backing
snapshot case. Its extra software-Present submission makes admission wait in
AwaitingRetirement after the Manage answer. The ordinary headless CPU backend
generates the retirement record. The fixture checks its exact candidate and
extent, then invokes Session's production software-retirement owner. A second
frame must reach production at generation 2 before checking Managed state,
released recovery extent and committed focus. Frontend control answers remain
supplied. The fixture drives record drainage and the owner call, so the native
service's selection, scheduling and native page-flip path remain open.

`t249-present-admission-dev01` passes all twenty cases; verified manifest
`6f9e72c71b6a0b18808a1924ad4eb53b487ae3179786d087006165ea7082c657`.
Two one-site mutations of archived Sophia compile and fail at their predicted
assertions, each with one failed test and exit 101:

- `t249-present-admission-session-control01` omits software admission completion:
  the next frame remains quarantined, generation 1 instead of 2. Manifest
  `8033e19f5da5cef572067e6ba49e1d52a3a508ae9790ba86f11fcba183fc83af`.
- `t249-present-admission-backend-control01` increments the headless retired
  candidate's transaction: exact-record correlation fails before the Session
  owner call. Manifest
  `87ab2034b206c76f0df05b212fa82b88bfc15144cbafd6dd08176b5676f3e937`.

Both controls hold the runner source lease, compare both relevant production
files to the pin, bind every mounted fixture, and verify restoration and the
unchanged Hagia binary. They retain binary paths and hashes, not binaries.
No production source change, installed change, native timing or physical
display claim. Restored-overlay strict clippy, formatting, thirteen runner
tests and Hagia layout pass in `t249-present-admission-checks01`, manifest
`6d0aca05b4bbdcbe916ee543aa07c9b56826dd6f99cc321882cf10e5fbc4d06d`.
The clean signed pair (Hagia `afcc1d1`, niltempus `0e82492`, Sophia `1b476dbdc`)
passes all twenty cases in `t249-present-admission-02`, verified manifest
`c846231e5b0f8a888124e4dc59b5f9fc8288df8ab32b835178e8fc3fe0bfe9bb`.
The preceding `t249-present-admission-01` remains STOP: restored archive
timestamps let Cargo reuse the compiled backend mutant. The final runner
refreshes extraction timestamps; its regression test fails when that refresh
is removed. Fourteen runner tests pass (one internal child fixture ignored),
and the archive control manifest is
`23e2435d8024ea925389664d9ec575a999e267583e442d192c26d7060e12f066`.

`t249-present-admission-audit01` verifies all retained package manifests, 3,257
archive inputs against the Sophia pin, every mounted input and all twenty exact
passing results. The final log explicitly rebuilds backend and Session.
Audit manifest: `6fcab87de72eb6dc37ecffb67ef47423d46d1c11c69d06798a48fda0bf62a0b4`.
Leased cleanup removes the temporary build root. h006/t249 remain open.

## 2026-10-10 presented chord owner join

Signed fixture `3960c83752743805cfbe3a17843296c6fef4947e` and niltempus runner
`beb125b744f0d18467c16b9bb5dc233ac45409e6` qualify a tenth current-SDK case
against Sophia `f77244abe`. Three owned CPU sources pass through the ordinary
production cycle. Real Hagia's preview publication passes unchanged preflight,
a supplied completion enables the captured action, stale identities are refused,
and chord release commits the expected third window with credit and debt settled.
The earlier nine cases retain their non-native capability selection.

`t249-presented-01` passes ten cases with clean signed fixture source; manifest
`32e64d8b45db223c74f0a1a0d3f902070c666a8341177810d479bf1d6b11b623`.
`t249-presented-controls-01` manifest
`836e6638d74f264bb0b4ad91f169a5529821e6e2d48208939f312f1e02e4ff79`
records two compiled named failures: missing completion prevents the captured
Right action; ignored Ended leaves focus W1 instead of W3. F1 does not proceed
to prove its predicted W2 final focus. Inputs were restored. The final fixture,
overlay and runner match the development source used by the controls; production
Hagia source is identical, but separate Nim builds have different binary hashes.

`t249-presented-checks-01`, manifest
`a2ef23105d82f86fbb0ff03621b73655b1a0801bba485f0b9bd5593fca85fcfa`,
passes restored-source comparison, overlay/runner clippy, three runner controls,
formatting and layout. The initial dev01 STOP (Ready before the last receipt
flush) is preserved. The fixture now polls a bounded drain with new cycles
disabled. All manifests independently verify; no tests were rerun at integration.

Heads, completion stamps, time and content are supplied; Session pixel admission
and visual readiness are bypassed. Receipt drainage proves transport progress,
not a particular ACK. Hagia ignores Presented in its model. Copied owner glue
is disclosed and reviewed against hash-pinned production spans. Native retirement,
pixels, physical input, latency, revocation-to-model, disconnect/release debt,
cancel and AbortSettlement remain open. No full product gate or installed change;
h006/t249 remain open. Future Rust runs use cargo-slot and do not archive build
products in evidence under the updated global resource rules.

## 2026-10-10 stalled live peer slice

Signed `651763e2dff1102a0b7380b3347ce7fc19c44fea` adds external
`tests/external/slow_peer.rs`; niltempus runner
`e441c7fb6b8cd4738ebc3d34fbc51df48d664b85` binds the fourth module and ninth
case on Sophia `65440ff5d`. The Sophia pin differs from the preceding pin only
in documentation. No production code or installed release changes.

`t249-slow-peer-01` under Sophia's development evidence reports
`PASS lifecycle=3 occupied=2 operations=3 slow_peer=1 native=false`, with clean
signed fixture source. Manifest:
`537e570a65ce84623dbd00684f10ef304752a4bc1b25955a5cd7aabac961a390`.
The test verifies the fixture's protected parent/child identity and start time,
pauses only that Hagia peer, and observes it stopped. Session's unmodified
twelve-second response deadline requests restart while that peer remains alive.
Committed state and checkpoint stay unchanged. Replacement clears pending
authority, reaps the old peer (a zombie still counts as present), restores the
occupied scene through its own scene/Dirty exchange and commits a fresh action.
The pause guard resumes the same surviving process on failure; outer PID
isolation and timeout bound cleanup. Observed detection/replacement times were
12051/29 ms, not latency qualification. Session log capture ends at detection.

`t249-slow-peer-controls-01` compiles two archived server mutants. Ignoring
transport failure hits the named forty-second bound; preserving the stalled
request fails the immediate post-epoch authority assertion. Each exits 101
with one named failure. Inputs match at start/end and source is restored.
Manifest `9172a63d50bb671fb8d3250e45898d7550122d261bc4e6c2eecf9935058ba4a3`.
`t249-slow-peer-checks-01` passes strict overlay and runner clippy, two runner
controls, formatting, Hagia layout and restoration of both mutated source files
to their pinned blobs; manifest
`f35280c03cd458794dce6b5124dd4cd4513419bed6d27faa145d66774a2db098`.
All manifests independently verify. The unsigned development run remains
separate; no full Nim/formal/product gate was repeated for these external tests.

Occupied facts and layout completion are supplied. AbortSettlement, paused-peer
ESTALE consumption, receipt ACK exhaustion, native presentation and actual
application execution remain outside the case. Generic reactor/SDK credit tests
were inspected, not rerun. Real-peer receipt credit belongs with the next
presentation/chord/capture join; the headless cadence does not naturally fill
the journal. h006/t249 and the measurement-method requirement remain open.

## 2026-10-10 SDK operation and disconnect slice

Signed `67da6edfb2c5932b59f828b452ab9bf4e17236fe` adds the external
`tests/external/operations.rs`; niltempus runner
`7eff07b728a41a7813bd29fb850999f222eb5d09` mounts it with the earlier fixtures
under Sophia `ea64b1f027ace8b9064935d966697acfac37d004`. The Sophia pin changes
only documentation from the occupied slice; production Hagia and SDK are
unchanged. No release or installed process changes.

The clean signed-fixture run `t249-operations-01` under Sophia's development
evidence reports `PASS lifecycle=3 occupied=2 operations=3 native=false`.
Manifest SHA256:
`84e927141e8887cd9eb0ca66b7f317f9edf47aee0663110d5c139fca7dc83189`.
Real catalog actions produce projections, then SDK operations naming their
activation serial rather than their projection request ID. The checkpoint is
saved before the operation arrives. Accepted and refused operation outcomes
both allow the same peer to answer another cycle; the accepted typed intent
stays local and is never executed. A refused action produces recovery
SceneChanged instead of an operation. Killing only the fixture child with a
projection or operation unsettled clears its obligations; each successor
restores committed occupied state through its scene/Dirty continuation.

`t249-operations-controls-01` deliberately accepts a refused operation, then
separately keeps the disconnected owner's pending operation. Each compiled
server mutant fails its named authority assertion (one failure, exit 101).
Manifest `b597e4e71aa96e00019713d12af0e50f6a92d6c3fb09ab5b1df409f49be6a78f`.
Controls use the development overlay, whose three fixture files and overlay
hash are byte-equal to the final run; Hagia production Git objects are equal.
`t249-operations-checks-01` records passing strict overlay clippy, then stops
because Nimble attempts a metadata write in the read-only sandbox after its
layout check passes. `checks-02` invokes the layout script directly and passes
layout, two runner controls, runner clippy and formatting; manifest
`d822a3c6639d8e92d32d479c1e5b25727fa7a36d1164b492ef9144680889abd3`.
All manifests verify; covered records are read-only. No production fix was needed.

Occupied facts and layout completion remain supplied. This proves neither
application execution nor exactly-once external effects, native presentation,
physical input, public control-socket restart, or every peer wire message.
The full Nim/formal/product gate was not repeated for external tests only.
h006/t249 remain open: slow-peer/credit coverage, presentation/chord/capture
joins and the reviewed measurement method still remain.

## 2026-10-10 occupied SDK recovery slice

Signed `0bbfe3cee3d1efa0b191098c70e64062ab8073b0` adds the external
`tests/external/occupied.rs` fixture and checkpoint-completion handling to
`lifecycle.rs`. niltempus runner `83023216817500f7595d5550f76d6b28016c99ba`
mounts both under Sophia `9f52403be19346a49ad275481886de9a5d4015a3`.
There is no Hagia production change or new release. Repository ownership and
the external test-source overlay remain as described in the lifecycle section.

`t249-occupied-01` under Sophia's development evidence reports
`PASS lifecycle=3 occupied=2 native=false`. Manifest SHA256:
`7a340bac1e5b4dfc9cf4458162b6c5ab1fe4077afd8f1d31d5067dc0ce2946b7`.
Two mapped surfaces with different generational identities exercise an actual
catalog focus action, refusal with unchanged checkpoint/layout, a fresh recovery
scene that does not replay the action, and another explicit successful action.
Automatic and requested restart preserve non-default column sizing, committed
placements, policy focus and occupied checkpoint relationships. Each replacement
sends its own restore Dirty. The helper waits for the checkpoint rename separately
from transport Ready and reads bytes/inode through one open file.

`t249-occupied-controls-01` binds the final fixtures and executable. Disabling
checkpoint restore fails on occupied placements/focus; promoting and saving a
refused candidate fails on checkpoint preservation. Both give one named runtime
assertion, not a build or deadline failure. Manifest:
`6dcd65ec09d3bfffd2ef3c7cd9106eb0d7832bbfc8d2a13d0705180cc55eea60`.
`t249-occupied-checks-02` records strict overlay and runner clippy, formatting and
two runner controls; manifest
`2855f118dd35575247f03425285c8fe1dfc1bca1395b79c973ac9a685beec5cb`.
Failed development fixtures are preserved separately; they exposed checkpoint
completion, cached scene facts and recovery-cycle ordering assumptions, not
production defects.

Authority facts, source-less layers and layout completion are supplied. No
application admission, pixels, configure ACK, physical focus or native receipt
is claimed; timeout is injected at the settlement owner. The full Nim/formal
gate was not repeated for this external test-only slice. h006/Sophia t249 remain
open for operation/terminal joins, presentation/input joins and the declared
measurement method. The installed desktop and physical acceptance are unchanged.

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
