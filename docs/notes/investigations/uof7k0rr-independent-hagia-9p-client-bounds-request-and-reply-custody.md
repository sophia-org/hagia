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

## Connections

- [h006 plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
  owns the complete WM migration exit.
- [Data-oriented design](../../data-oriented-design.md) keeps passive values
  separate from private socket/tag mutation.
- Sophia `docs/sophia-wm-files.md` defines the file-semantics draft. The output
  role remains on its existing IPC transport in this milestone.
