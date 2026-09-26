---
id: uof7k0rr
date: 2026-09-25
kind: investigation
status: investigating
tags: [investigation]
---
# Independent Hagia 9P client bounds request and reply custody

## Question

Can Hagia independently speak bounded base 9P2000.L without depending on
Sophia's Rust codec or changing its existing WM policy path?

## Evidence

The first h006 checkpoint is based on signed Hagia `97ed593`. It adds passive
wire types in `src/types/ninep.nim`, a pure codec in `src/ninep/codec.nim`, and
an encapsulated direct-socket owner in `src/ninep/client.nim`. No current Hagia
CLI or policy client selects it yet. It uses only Nim's standard library.

The field layouts are independently implemented from the
[diod .L protocol tables](https://github.com/chaos/diod/blob/master/protocol.md).
The test literals are written from those tables, not from Sophia's encoder.
`tests/ninep_static_peer.nim` is a separate executable for t247's static export;
it is not a second server or an imitation WM.

Device-hidden focused execution used Nim 2.2.12, nice 19, and a private disk
cache under `hagia-overview-fix/.artifacts/h006`. `focused.log` records 14 passing
controls. `static-compile.log` records compilation of the independent peer;
compilation alone is not interoperability evidence. `compile-1.log` retains
the initial Nim discriminant-layout error (a variant enum needs a zero value).
The invalid zero kind now refuses at the codec boundary. No hardware, live
socket, install or reload was involved.

## Finding and resolution

The client sends exactly `9P2000.L`, accepts a negotiated 4–64 KiB bound,
and checks reply tag, kind and request-specific counts before exposing data.
It refuses unknown/classic reply types and malformed lengths without trusting
the peer's allocation counts. Numeric `.L` errors remain typed refusals.

The socket owner keeps at most 32 ordinary pending requests and reserves one
additional flush slot. An ordinary tag remains reserved while any outstanding flush names it, even
when its original reply arrives first. Only the ordered `Rflush` releases that
reservation; flush requests cannot themselves be flushed. An original reply may precede `Rflush`; a reply after its tag was
cancelled is a protocol error. Disconnect, malformed peer traffic and partial
I/O failure close the socket and clear all local tag custody.

I/O uses a nonblocking owned descriptor. `tryReceiveReply` polls for the caller's
bounded idle interval and returns `None` only if it consumed no bytes. EOF is a
disconnect, including before the first byte. Receipt of the first byte starts
one monotonic assembly deadline for the remaining header and body: a prefix
must complete or close, never return as idle. Synchronous `receiveReply` also
bounds the initial wait separately, so a call can take up to twice the configured
timeout. `tryReceiveReply` requires a pending request; an adapter normally keeps
an event read pending rather than using this API as a general disconnect probe. A peer cannot extend assembly by trickling
fragments. Writes have their own whole-frame deadline and fail closed on partial
I/O failure. The eventual pipelined WM adapter must continue draining replies
while writes are blocked; these low-level bounded operations alone do not
establish that event-loop scheduling contract.
This low-level owner does not select an endpoint, supervise a process, assign
an epoch, authenticate attach names or interpret WM file contents.

## Validation and remaining work

The focused controls cover literal version/attach and operation layouts;
truncation, count/length overflow and malformed replies; qid and 64-bit
attribute sizes; out-of-order replies; both flush orderings; late cancelled
replies; cancellation at a full request window; mismatched kind/tag/count;
typed remote refusal; partial-read and blocked-write deadlines; and invalid
version/msize negotiation. Formatting, layout and whitespace checks pass.

The full WM file payloads, adapter, profile/snapshot/proposal roundtrip,
existing-IPC comparison and paired lifecycle gate remain pending under
h006/Sophia t249. Socket tests do not establish those exits or physical
presentation.

## Independent review and corrected client

The t247 owner's read-only review found a real tag reuse bug: if the original
reply arrived before `Rflush`, its tag could be reused after allocator wrap,
and the later `Rflush` could delete the new request. The regression traverses
the actual tag namespace while retaining the flush, then checks the new request
survives. No allocator test hook or artificial private state is used.

Other corrections are: version requests use `NOTAG`; starting renegotiation
immediately invalidates the previous session even if the new version is
refused; an empty `Rwalk` for a nonempty walk is malformed; and flush-of-flush
and renegotiation during a pending flush refuse without discarding custody.
The role adapter owns fids, and only a full walk or zero-name clone establishes
`newfid`. A partial walk reports the prefix without creating that fid.

`review-final-24.log` records 24/0 after all mutations were restored. New
controls include idle waits beyond the assembly timeout, readable EOF, a
three-byte prefix that times out cleanly, and a delayed suffix that completes
exactly one reply. Six compiled source mutations fail their intended guards:
flush tag reservation, EOF treated as idle, consumed-prefix return as idle,
version reset, the empty-walk rule, and an error reply to flush. The latter is
a protocol violation because flush cannot fail; it closes all local custody. The initial broad partial-custody
mutation failed at the earlier successful-reply assertion; its separately
filtered rerun pins the partial-header refusal itself. All logs are retained.

The independent Nim executable then ran against t247's copied debug server
from signed `ee2b7601`, SHA256
`ef220dde8d8125310b7c6d4526b2b539056878cc60acb1a5c6bba1d132748b94`.
The client SHA256 is
`6baf06ed051985da5fa2ec96d931c80d6aa18b626fe6fbb4a34692edabffddbe`.
`final-pair/pair-report.json` and per-run logs retain both identities. The
clean run negotiates 4096 bytes, reads all 70000 patterned bytes through
fragmented reads, and checks walk/open/getattr/write/flush/clunk. Each server
mutation is refused: permissive authorization, corrupted read bytes, pending
read reported as EOF, version suffix, and dropped flush (bounded timeout).
These are interoperability and negative controls, not performance measurements.
The old focused and paired logs remain separate. No live endpoint was opened.

## File envelope and snapshot preparation

The independent file envelope `efcfb60` and raw-u32 portability follow-up
`7095aeb` are joined as signed `d5c2e48` and `3e89a14`; their whole trees match.
The peer reports fifteen focused tests, formatting and layout passing, and
fifteen of sixteen mutations killed. The survivor is an equivalent addition
on the tested 64-bit target. No 32-bit execution is claimed. Its preserved
bundle is `hagia-wm-files/.artifacts/h006-envelope-bundle`; the runtime client
still does not select the file transport.

Before array conversion, three direct snapshot-validator characterizations
pass against `3e89a14`: a surface with index zero is accepted but focusing it
is refused; the all-ones surface index is not refused; and a nonzero transient
index is ignored when its generation is zero. These are direct legacy codec
behaviors, not proof of live Session admission. The file path must use strict
surface identities without silently changing legacy behavior during extraction.
The shared snapshot validator remains unchanged at this checkpoint.

The device-hidden baseline uses its own disk Nim cache. Logs are in
`.artifacts/h006-arrays`: the first invocation omitted `--path:src` and failed
to locate the imports; `snapshot-identity-baseline-2.log` contains the three
passing controls. No current policy execution, live endpoint or hardware was
used. Scalar and array body codecs, and the complete role join, remain work
under h006.

## Complete file snapshot checkpoint

The signed scalar/admission series `809c500`, `a1f5564`, and `cb9abda`
is joined as `0c5fdb7`, `e5e77ed`, and `69643df`. Capability bits have one
passive owner; scalar file bodies use shared typed predicates and the file
payload helpers. The peer's final-tree results and 21 killed mutations are
reported evidence, not director reruns of those suites. The peer subsequently
pinned the three initially legacy-only kills in its file corpus too.

`policy_snapshot.nim` now owns complete snapshot validation and output-policy
key application. The legacy entry preserves the three characterized identity
behaviors and its error order. The file entry permits a valid index-zero
surface to hold focus, refuses the all-ones index and partial optional surface
identities, and rejects unknown surface-capability and operation-target bits.
The existing policy client delegates only the extracted key application;
its framing and sequencing are unchanged.

`wm_file_arrays.nim` decodes the complete Snapshot body. It checks the exact
kind, admitted epoch, prefix, sorted section inventory, row widths, raw-u32
counts and per-kind maxima before row conversion. Every extension requires its
selected capability. A mandatory output section, active-output membership,
live launch origins, and exact output-generation keys are checked before a
snapshot is returned. Fixed row codecs are shared with the old wire; no old
Begin/Chunk/End frame is constructed.

Focused device-hidden checks after the join pass: six snapshot identity
controls, seven file snapshot controls, and four legacy wire corpus controls.
The file fixtures construct rows from the published layout and use the local
envelope encoder. They are not a cross-language exchange or a mounted-client
test. Logs are `.artifacts/h006-arrays/snapshot-identity-joined.log`,
`arrays-initial.log`, and `legacy-codec-joined.log`; formatting, layout and
diff checks pass. No compiled mutation or broad contributor gate ran for this
snapshot checkpoint. Configuration/projection array encoders, the complete WM
role join, and performance acceptance remain outstanding. Default transport,
output-role IPC, live sessions and hardware are unchanged.

## Configuration candidate checkpoint

The h006 bodies evidence bundle is verified at
`hagia-wm-files/.artifacts/h006-bodies-bundle`: nineteen files, with manifest
SHA256 `c04abf01fcc7133a2135e388dccfb6bf2782cd9d6d38cef85502afc11e315076`.
It retains the peer's six final binaries, focused logs, source bundle and
mutation evidence. Intermediate commits were not built alone, and no broad
contributor gate is implied.

The outgoing Configuration array body now has a passive value and encoder.
It checks the candidate header and exact epoch, nonzero transaction and
generation, configuration/chrome/action capabilities, the 64-pixel chrome
bound, style consistency, `00RRGGBB`, and bounded unique action IDs/names.
Its action rows use `encodeSnapshotAction`; the legacy decoder and new row
encoder share the same character predicate without changing legacy error
order. No legacy frame is embedded in a file.

Snapshot diagnostics now retain the underlying rule, and count versus width
refusals use the same value/length error categories as the scalar helpers.
Fourteen snapshot/configuration controls and the four legacy wire corpus
controls pass device-hidden, with formatting, layout and diff checks. Logs
are `.artifacts/h006-arrays/configuration-{initial,legacy,layout,format}.log`.
The configuration control compares independently assembled expected fields
and action rows; a Rust-decoder exchange remains outstanding. Projection
array encoding, the file client loop and complete role acceptance remain
open. No broad gate, physical run or default transport change is claimed.

## Complete Projection encoder and supplied-stream peer

The file candidate encoder now emits one bounded section per populated kind,
with shared legacy fixed-row encoders and no chunk envelope. Row counts and
output partitions are checked before row construction. Translation and launch
hints retain their capability-dependent omission rules; tab groups, indicators
and action-bearing presentations refuse without their required capabilities.
A passive presentation uses the file contract's `SURFACE_INSTANCES` minimum.
Placement handle/state validity is checked on the candidate side, earlier than
Sophia's row codec; final membership and authority remain Engine-owned.
The legacy client now reads the same named tab/translation kind, width and
count constants, with identical values and conditions.

Sophia's shared selected-tab fix was characterized at `71fde5fb`, made red at
`afbba8f2` and fixed at `d8c20a89`: index zero with a nonzero generation is
present, `(0,0)` is absent, and all-ones indices or other zero-generation
pairs refuse. Its None encoder previously produced `(u32::MAX,0)`, which its
own decoder refused. The compatibility change is recorded in Sophia's t249
note, and both frozen byte fixtures passed unchanged. Hagia now explicitly
pins present index zero, absent selection with no members, and invalid
selection pairs. The Sophia bundle's thirteen files were independently
checksum-verified; manifest SHA256 is
`d53adc5e9db0f0ab6ac2f731036e048db8ca59352090438d7fabde2e688010d9`.

Device-hidden checks: ten Projection controls, fourteen Snapshot/Configuration
controls and four legacy corpus controls pass. The normal Hagia executable
compiles after the constant reuse. Three compiled mutations (row bounds,
action-bearing presentation capabilities, and the output-launch dependency)
fail their named controls; source was restored and Projection rerun green.
Formatting, layout and diff checks pass. Evidence is
`.artifacts/h006-projection/`. The tests include one 81920-byte instance section
that crosses the old chunk boundary without splitting.

`tests/wm_file_session_peer.nim` is a separate prebuilt peer for Session's
opt-in supplied-stream startup/cycle fixture. It uses the independent .L client,
shared typed file codecs and Hagia's existing profile reducer against a fixed
fixture candidate (epoch 9, generation 3, digest 07 repeated 32 times). Its
Configuration, placement, session operation and accepted outcomes are scripted;
it is not the production Hagia loop or an Engine acceptance test. Candidate
writes are 17 bytes, events are read in 23-byte pieces, and immutable objects
in 37-byte pieces, forcing header/body fragmentation. Submitted, ACK and
semantic transaction identities are checked separately. Object metadata stays
pinned, and Snapshot/Cycle transaction and generation must match. Deadline
failure closes the one-shot peer and retires its outstanding read.

The peer compiles after correcting a test-helper sequence-deletion API mistake;
the failed compile log is retained. At this checkpoint the independent socket
pair has not run. It requires the exact prebuilt executable and SHA256, with
fresh retained evidence. No full contributor gate, authenticated launch,
LivePublicPolicyState settlement, native retirement, performance measurement,
production endpoint/default selection, or output-role migration is claimed.
The startup/complete adapter remains on Sophia's topic branch; WM migration and
h006 are still open.

## Independent pair and contributor gate at 586b9a4

The frozen peer built from signed Hagia
`586b9a4dce3d766127b575720718339cb6ac6071` subsequently passed both required
startup and cycle fixtures against signed Sophia `99601a30`. Its SHA256 is
`aa6922d1f65157fedb1c304906afefe7a396a11cd7880ba0e1b0359aaea6ce66`.
Both child processes exited zero, with pass records and empty stderr. The
17/23/37-byte fragments exercise the actual independent client and Sophia
reactor; decoded proposal assertions check epoch, transaction, request and
scene identities, output coverage, focus, placement, and state generation.
The shared profile reducer uses the independently fixed generation and digest.
Semantic outcomes and the presentation receipt remain scripted: this is not
Engine settlement or native presentation evidence.

Sophia's test-only follow-up `334b5d55`, joined as `c4a8ee921`, additionally
checks the accepted socket's SO_PEERCRED PID against the spawned child. Both
cases pass again; the observed namespace PIDs are 301 and 298, with UID 1000.
The evidence explicitly describes path hashing before and after execution,
`descriptor_pinned_exec=false`, and `hash_then_exec_window=true`. It does not
claim protection-domain launch admission.

The independently verified Sophia bundles are under
`~/.local/state/sophia/development-evidence/`:

- `t249-peer-99601a30-586b9a4`, manifest SHA256
  `34967dea1e5f5a212227bf9b9e715ead25ec67b7f611454c36249289ba8331e9`;
- `t249-peer-credentials-334b5d55`, manifest SHA256
  `155b45d58a5adffdcf7349070f1b0fbfa39c98ed8fd63922bf4be6001c78f7b0`.

The full `nimble verify` contributor gate then passed on clean, unchanged,
signed Hagia `586b9a4` and Sophia
`c4a8ee921449047aaded196bca1593e328e20e6f`. The device-hidden run used two
build jobs, nice 19, and two TLC workers. It includes 415 Nim test successes,
the eleven-scenario revision-3 policy behavior corpus, the existing Alloy and
Z3 checks, and all four existing TLC configurations: startup-trace, lifecycle,
partial-prepare, and stale-completion. These model results concern their
existing lifecycle specifications; they do not formally verify the new file
transport. No live or physical gate ran.

The verified 32-file bundle
`~/.local/state/hagia/development-evidence/h006-verify-586b9a4-c4a8ee92`
retains the complete log, invocation and isolation wrapper, start/end source
identities, toolchain, and all 21 Nim executable artifacts copied before the
gate's temporary directory was removed. Its manifest SHA256 is
`1310e77616f322c836971334e0881e5faa6817cab6b9bc0039c289686b8937ce`.
The ongoing PolicyWire extraction and protected-endpoint constructor are on
separate worktrees and are not covered by this run. The production Hagia file
loop, launch selection, real Session settlement, and full WM acceptance remain
outstanding; h006 stays open.

## Caller deadlines and the shared Hagia loop

Signed `13822eb77b65008c820782ee942296c287712077` adds an optional absolute
`expires` to the independent client's adoption, send, receive, readiness and
synchronous-call APIs. The default remains unchanged. A supplied cap is the
earlier of the caller deadline and the existing frame or readiness deadline;
the caller reuses it across all RPCs in a bounded file operation. An idle
Cycle wait can still omit it. Expiry closes the stream and all tags even when
a reply is already buffered, so an earlier write's effect can be unknown.
Timeout never means rollback. Millisecond polling can return idle just before
the cap; a repeated call retains that same cap. Error strings do not identify
which deadline expired.

The device-hidden focused client suite passes 34 controls, including all 24
previous controls. New cases cover pre-expired requests, first-byte and partial
assembly waits, idle expiry, version adoption, already buffered replies,
non-extension of the frame timeout, one deadline across RPCs, blocked writes
followed by peer EOF, and a successful reply after an idle poll. Three compiled
mutations dropping the assembly, synchronous-reply or write cap fail their
named controls. Source was restored before the final pass. Formatting, layout
and diff checks pass. The verified seventeen-file bundle is
`~/.local/state/hagia/development-evidence/h006-deadlines-13822eb`, manifest
`6d4f48b8c8257717458801b0dc56257fab709c582bfd86cbf85323048ead8c6a`.

Signed pF checkpoint `9685af844078d8f1e863b2209f373e89d2bd0e99`, joined as
`f05bb50`, extracts the existing loop behind the typed `PolicyWire` closure
table. `PolicySession` and the profile reducer retain their existing ownership;
the legacy adapter retains frame parsing, encoding and timeouts. Snapshot and
request remain separate callbacks to preserve the fault-injection boundary.
Neutral configuration and Dirty values have file compatibility aliases.
Legacy projection completions report no operation-expectation flag; a file
completion's flag must agree with the intent before settlement.

The author's eight focused targets passed, including nine new real-loop
fake-wire controls. Two compiled mutations were rejected: applying a nonempty
receipt list after preparation, and checking the expectation after settlement.
The latter is pinned through refusal precedence against an invalid outcome
identity, alongside absence of checkpoint and operation side effects.
The normal and proof executables compile. Formatting and layout pass.

The baseline capture independently compiles `586b9a4` source: all 92 extracted
source/example blobs match, and generated C embeds 54 baseline local-module
paths with none from the changed source. The candidate embeds 56 current
local-module paths, including the new wire and loop. Both produce the same
fifteen client frames, including configuration transaction 1, projection 2,
Dirty 3 and projection 4. Their SHA256 is
`144aa6b845c8f756d85b1bbf726b90a3707e362dfd243b43b8d4a394a75a3640`.
The director verified the frame equality and source git bundle and preserved
the focused logs, binaries and capture under
`~/.local/state/hagia/development-evidence/h006-policy-wire-9685af8`. Its
28-file manifest SHA256 is
`ca686ba13a64542f36bad8762dbdb1a06956ccadd99a946af5fa99715898a163`.
These focused checkpoints do not extend the earlier full contributor result
to the new source. The production file wire and its paired acceptance remain
the next work; output traffic and the installed default are unchanged.

## Supplied-socket file wire

Signed `17f402eaec3f5639a964006676399842642674b0`, joined as `c4554f8`,
implements the file role behind `PolicyWire`. One event read may coexist with
one control RPC. Candidate custody consumes its matching Submitted while
preserving one earlier event for its eventual consumer; receipts continue to
drain and acknowledge behind that held event. A second unrelated event refuses.
The selected capability set must fit both the offer and the published ceiling.
Profile and policy phases remain with the shared reducers and Session driver.

One absolute candidate deadline includes encoding, staging, submit retries,
Submitted and clunk. A started file-event assembly has a bounded lifetime,
while idle waiting before its first observed payload fragment is uncapped in
normal policy traffic. Completion stops that assembly timer even when the
record waits for its consumer. A snapshot/object read has one deadline across
all RPCs; fragment progress cannot renew it. Discovery retains its shorter
bound. Expiry closes custody and does not imply semantic rollback.

The author's device-hidden focused suite passes all fifteen file-wire controls
and the nine retained targets. The latter include the legacy corpus, client,
profile, model, file bodies and arrays. The first retained-corpus invocation
omitted `SOPHIA_ROOT` and failed; the corrected invocation passed and both logs
are retained. Normal and proof binaries build, and config check, formatting and
layout pass. The peer is a scripted transcript: it proves flow and refusal,
not independent server conformance or real Session settlement.

Six compiled mutants fail named assertions: dropping receipt drain,
overwriting the held event, renewing candidate time, retaining an assembly cap
after completion, removing the whole-object cap and renewing the event cap per
fragment. A seventh mutant that repeatedly pops and replaces the held event
spun without reaching I/O. The director terminated its exact owned test process,
PID 5301; this is timeout evidence, not a named assertion failure. The mutation
runner now includes isolated-process timeout and final source restoration, but
that revised runner was not rerun. The accepted source was restored and its
hash verified before the final focused checks.

The verified 35-file bundle is
`~/.local/state/hagia/development-evidence/h006-file-wire-17f402e`, manifest
`e159a044c66a88eb009246a196f5ee081d43e6fc515ca7e596cb52421756c221`.
It retains the source/bundle, binaries, initial failures, restored checks and
mutation records. Explicit executable endpoint selection and the independent
production-loop/Session pairing are subsequent checkpoints; no installed
session or output transport changed here.

## Explicit executable endpoint selection

Signed `7455c3edd713770ed43630d0989073d2f14ba623` on
`protocol/h006-runtime-selection` adds an explicit resolver and
a thin path wrapper around the supplied-socket file wire. Current IPC remains
the default. `SOPHIA_WM_9P_SOCKET` or `--9p-socket` selects only the file WM;
dual selection refuses even when an explicit override is empty. The legacy
missing-path and unknown-option refusals retain their order. Offline commands
ignore endpoint variables. There is no byte sniffing or fallback.

The wrapper uses the existing candidate settings parser before connecting and
passes its focus and workspace requirements into negotiation. It uses the
existing connect retry and shared activated/configured loops; only the file
wire closes its socket. Its two focused controls pass, covering all four
focus/workspace combinations through a real path connection and an invalid
candidate that never connects. The prescribed peer refuses the first submit;
these are wrapper/offer controls, not Session admission evidence. The first
compile failed on missing parentheses in a test bit-mask assertion; the fixed
run passes, with both logs retained.

Six pure resolver controls pass. The normal executable compiles, and eleven
disposable CLI probes pass: ambiguous/mixed selection, empty override, legacy
missing path, offline config/help and all four environment/option dispatches.
The latter check actual current-IPC and exact 9P2000.L initial messages before
closing the test peer. This is entrypoint evidence, not a completed role
exchange. Logs, probe source and binaries are retained under
`.artifacts/h006-endpoint`. Formatting, layout and diff checks pass.

The verified 17-file bundle is
`~/.local/state/hagia/development-evidence/h006-endpoint-7455c3e`, manifest
`09ed732136b5db42898114d878857d34df681b84df3df8c03a50d07cde84bc05`.
It includes the frozen normal executable, SHA256
`0419e09e224676c4d925438f80b22df9532c1653ec339507637edbe01ea52f5f`,
for the next protected Session pair. This executable runs the production loop;
it is distinct from the earlier scripted peer.

The file path intentionally rejects invalid settings earlier than current
IPC. A read-only trace of Sophia's paired production selection found that,
after protected launch succeeds, initial activation waits only for worker
events for five seconds. A child that exits before accept normally produces
the profile-admission timeout, not a ProfileRejected completion. The existing
startup rejection rolls back the candidate and drops the worker, endpoint and
supervisor without promotion or fallback. Worker cancellation interrupts the
longer pending accept; the supervisor's existing reap loop is not a hard total
cleanup deadline. An exit before protection evidence is acquired instead
fails launch/evidence acquisition. These are source-traced classifications,
not newly reproduced Session timing controls.

The output role remains current IPC. No installed session, default selection,
Engine settlement or physical acceptance is changed or claimed here. The
independent production-loop/Session pair and full WM milestone remain open.

## Contributor gate on the executable-selection checkpoint

`nimble verify` passes on exact clean, signed Hagia `7455c3e` and Sophia
`b43e4ef071bf919ed5fec6cd9d1034ce7f7a6644`. Start/end identities match. The
device-hidden run used serial Nim targets, two Cargo jobs, nice 19 and two TLC
workers. It reports 457 Nim checks, the existing eleven-scenario revision-3
behavior corpus and paired profile, pointer-focus, presentation and launch
controls. Eight Alloy checks are unsatisfiable, Z3 matches its expected
results, and all four existing TLC checks pass. These remain the existing
models and legacy paired contracts; this is not new 9P formal verification or
full WM file-role acceptance. Logs and source identities are preserved in
`~/.local/state/hagia/development-evidence/h006-verify-7455c3e-b43e4ef0`.

The independent review also found a file-only cross-side mismatch still open
at that exact Sophia commit: a failed session-action projection can carry a
true operation-expectation flag although its driver will not wait for an
operation. Hagia correctly refuses that contradiction before settlement. The
separate Session fix will qualify the emitted flag by a committed outcome;
the file contract and Hagia's check stay unchanged. The next paired fixture
must prove continuation after a failed action, not merely pass a happy path.

## Protected normal-Hagia startup pair

Sophia's test-only `9bf5c52beb858840d3d838b4efcc92e787ee8e2f`, joined as
`a43dd5f886bba267dd4f84e7dd09a478a806a681`, runs the frozen normal `7455c3e`
executable through Session's production protected file endpoint, staged profile
and configuration owners. Hagia's actual profile reducer completes the handoff;
its actual file loop supplies the catalog. The pair passes in 0.46 seconds:
configured and ReadyForCycle, epoch 1, exact staged profile identity, 175 actions
and immutable selected capabilities 253951 within ceiling 262143. Native
presentation bits and overview actions are absent, and no layout checkpoint
is written. There is no scripted profile response or replacement client.

The fixture pins the executable path and SHA256 before and after, records the
supervisor's protected peer evidence, and requires fresh evidence inputs.
Missing inputs fail an explicitly selected test instead of silently skipping.
The process/peer IDs in the isolated run are 299/300. Cleanup reaps the child
in 5 ms on this run; Hagia reports connection reset when the fixture stops its
worker. Neither a clean Hagia exit nor a hard stuck-kernel cleanup bound is
claimed. Strict Session checks, layout and formatting pass.

The verified 17-file bundle is
`~/.local/state/sophia/development-evidence/t249-hagia-startup-9bf5c52b`,
manifest `83417ff60abc663833470befbe406295307d0d060a203c215d08c71bc33ed802`.
This proves protected startup/profile/configuration/catalog admission. The
fixture deliberately issues no layout cycle, has no output bootstrap and
claims no Engine transaction, presentation or retirement. Actual Session layout
settlement and failed-action continuation are the next paired checkpoint.

## Failed-action operation-expectation repair

Sophia's signed red `6eeacfc9ac769577ea95ab973d777191abb9a07d` reproduces
the mismatch separately for TimedOut and RejectedStale: both emitted true,
while the committed-action positive correctly emitted true. Signed
`2a8271b027e3be1bc58566750750076994ff122d`, joined as `7b5223530`, qualifies
the flag at the existing settlement-command owner with `outcome == Committed`.
The file adapter still encodes the actual command, the existing driver is
unchanged, and Hagia's strict expectation rule is unchanged.

All three focused controls and 38 neighboring reload controls pass, with two
fixture entries ignored. Strict Session checks and isolated layout pass.
These are owner-command controls: the request path supplies the settlement
identity, but the refusal layout outcome is a fixture value. They do not prove
actual resize expiry or retained-layout preservation; the real-layout pair
must cover those. The initial featureless invocation matched zero tests and
was not counted. Workspace formatting passes; a direct check of the included
commit file retains the same eleven pre-existing formatting blocks at base
and fix. One author layout invocation ran outside isolation; the accepted
layout evidence is its isolated rerun.

The verified eleven-file bundle is
`~/.local/state/sophia/development-evidence/t249-expectation-2a8271b0`.
The signed source bundle, exact reds/greens, invocation scripts and evidence
qualifications are retained there.

## Connections

- [h006 plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
  owns the complete WM migration exit.
- [Data-oriented design](../../data-oriented-design.md) keeps passive values
  separate from private socket/tag mutation.
- Sophia `docs/sophia-wm-files.md` defines the file-semantics draft. The output
  role remains on its existing IPC transport in this milestone.
