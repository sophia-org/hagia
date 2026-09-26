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
additional flush slot. Tags remain owned until a reply or an ordered `Rflush`
settles them. An original reply may precede `Rflush`; a reply after its tag was
cancelled is a protocol error. Disconnect, malformed peer traffic and partial
I/O failure close the socket and clear all local tag custody.

I/O uses a nonblocking owned descriptor plus poll with one monotonic deadline
for an entire frame. A peer cannot extend that deadline by trickling fragments,
and unread-socket backpressure cannot leave a partial write waiting forever.
The caller chooses the finite I/O timeout; the eventual WM event-loop adapter
must separately handle idle waiting and its existing signal/restart lifecycle.
This low-level owner does not select an endpoint, supervise a process, assign
an epoch, authenticate attach names or interpret WM file contents.

## Validation and remaining work

The focused controls cover literal version/attach and operation layouts;
truncation, count/length overflow and malformed replies; qid and 64-bit
attribute sizes; out-of-order replies; both flush orderings; late cancelled
replies; cancellation at a full request window; mismatched kind/tag/count;
typed remote refusal; partial-read and blocked-write deadlines; and invalid
version/msize negotiation. Formatting, layout and whitespace checks pass.

Next run the independent executable against the exact signed t247 server and
its relevant mutation controls, retaining both binary hashes. The full WM file
payloads, adapter, profile/snapshot/proposal roundtrip, existing-IPC comparison
and paired lifecycle gate are still pending under h006/Sophia t249. The
socket tests do not establish those exits or physical presentation.

## Connections

- [h006 plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
  owns the complete WM migration exit.
- [Data-oriented design](../../data-oriented-design.md) keeps passive values
  separate from private socket/tag mutation.
- Sophia `docs/sophia-wm-files.md` defines the file-semantics draft. The output
  role remains on its existing IPC transport in this milestone.
