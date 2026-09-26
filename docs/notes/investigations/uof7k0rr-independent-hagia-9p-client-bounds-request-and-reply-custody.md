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

## Connections

- [h006 plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
  owns the complete WM migration exit.
- [Data-oriented design](../../data-oriented-design.md) keeps passive values
  separate from private socket/tag mutation.
- Sophia `docs/sophia-wm-files.md` defines the file-semantics draft. The output
  role remains on its existing IPC transport in this milestone.
