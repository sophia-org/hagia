---
id: n6dx1wbt
date: 2026-10-02
kind: plan
status: proposed
tags: [plan, milestone]
---
# niri parity for the recent-windows switcher

## Scope and exit

niltempus asked for Hagia's recent-windows switcher (h008) to behave as
niri's does. The core gesture already matches: hold, tap to step, release to
switch, and a quick tap with no strip. A read-only comparison against niri
5f4469b6 (`src/ui/mru.rs`, `niri-config/src/recent_windows.rs`) found seven
gaps, tracked as h009-h015.

The exit for each task is a niri behaviour that niltempus observes on an
installed release. Policy and adapter tests reproduce it first. This plan
moves Hagia toward niri's behaviour; it does not claim full niri parity, and
no task is accepted before niltempus's live check.

niltempus decided two boundaries:

- **Hagia stays blind.** Sophia's WM contract withholds titles, classes and
  PIDs (`docs/sophia-wm-api.md` in Sophia). The application filter therefore
  uses opaque group tokens issued by Sophia, urgency arrives as a state bit,
  and titles are text that Sophia draws itself. Hagia positions it but never
  reads it.
- **A bounded WM deadline** is added to the contract so that Hagia can
  implement niri's focus debounce.

Five tasks depend on new Sophia capabilities, delivered in the same order as
the chording work: contract, then C SDK, then Rust doc import, then Sophia,
then Hagia repin and behaviour. Their Sophia peers are t279-t283 (Sophia
plan kgo1ugnz).

## Task details

**h009: keys while the held switcher is open.** niri's preset keys while the
switcher is open are:
- Escape: cancel;
- Return or space: confirm;
- Left and Right: step;
- Home and End: first and last;
- a, w and o: set the scope, s: cycle it (h011).

A chord-owned strip used to be an Overlay with no keyboard. Sophia's held
capture (t279) allows a keyboard capture on an Overlay. It passes every
modifier edge to applications and to the chord, and takes only non-modifier
presses. With it, the held strip publishes these keys under all 16 modifier
masks, and `validatePresentation` accepts a keyboard scope that is uniformly
Overlay or uniformly replacement.

New actions `recent-window-first` and `recent-window-last` are added. The
keys are fixed to niri's presets; there is no binds configuration section.
The modal fallback keeps its keys and also gains the scope keys. Peer:
sophia/t279.

**h010: close from the switcher.** No new action. While the switcher is
open, the operator's existing `session:close-window` operation closes the
selected candidate instead of the focused window, as niri's close does.
`operationFor` (`src/sophia/policy_session.nim`) takes the selection as a
close target, validated to be a surface of the snapshot, before any focus
lookup, so it works with nothing focused. The candidate then leaves through
`forgetRecentWindow`, and the selection moves to a neighbour.

Limitation: a presentation binding cannot carry a session operation, by
design. The close therefore comes from the profile's own close binding, for
example Super+q with a Super+Tab switcher. niri's close under the switcher's
own modifier (Alt+q with Alt+Tab) is not provided, and no global Alt+q
binding is added.

**h011: scope from the switcher.** Add the actions
`recent-window-scope-all|workspace|output|cycle`, bound to a, w, o and s.
Candidates are recomputed as niri's set_scope does: the selected window is
kept, or else the nearest one to its left in the unscoped order, or else the
first. Cycling goes all, workspace, output.

An empty scope is taken. The switcher stays open and empty with its backdrop
and keys; stepping does nothing; confirming or releasing the chord closes it
without moving focus; and a later scope repopulates it. The empty strip
returns before any layout arithmetic, so narrow outputs are safe. The scope
is visible only through the candidate set until h013 adds text.

**h012: same-application filter.** Add the actions
`recent-window-next|prev-same-app`. They filter candidates to the focused
window's opaque Sophia group token, which means equal WM_CLASS class, issued
per connection epoch. Triad/niri `--filter app-id` migration is accepted.
Peer: sophia/t281 (surface groups).

**h013: titles above the previews.** Each preview gets a `SurfaceLabel`
region, placed as niri places its title. Sophia fills in and draws the text
from its broker's descriptor, under the user's disclosure policy: class-only
by default. Peer: sophia/t282 (compositor-drawn labels).

**h014: focus debounce.** niri's `debounce-ms` defaults to 750 and is
configurable. A focus change records a pending entry and requests a Sophia
deadline. When the `Deadline` cause arrives and the window is still focused,
the entry is recorded. Opening the switcher commits it immediately. This
replaces today's immediate recording, which is documented in
`src/entities/recent_windows_ops.nim`. Peer: sophia/t283 (policy
deadlines).

**h015: urgency.** An urgent candidate's highlight uses Sophia's
`Attention` region role, which is niri's urgent-color. The source is
Sophia's surface attention state bit, from WM_HINTS UrgencyHint and
`_NET_WM_STATE_DEMANDS_ATTENTION`. Peer: sophia/t280 (surface attention).

**Order.**
1. h009, h010 and h011 ship with the first Sophia release that carries the
   held capture.
2. h012-h015 are planning candidates outside this release. They follow the
   second contract revision, which carries the other four capabilities.

Each release is assembled with the matching Sophia under the director's
integration, as with h008.

**Validation.**
- `tools/check_sophia_policy.sh`, `nph --check`, the layout and the
  foundation and profile models.
- New cases in `tests/trecent_windows.nim` and
  `tests/trecent_windows_adapter.nim` for each task, plus replay.
- `nimble exportProof` against the signed Sophia.
- niltempus's acceptance on the installed release, one listed behaviour per
  task.

## Connections

- Builds on h008 (`a00ow1xn-recent-windows-order-and-modal-switcher-fixes-after-the-h008-review.md`).
- Sophia peers: t279 held capture, t280 surface attention, t281 surface
  groups, t282 compositor-drawn labels and t283 policy deadlines (Sophia plan
  kgo1ugnz). t279 is admitted for this release; t280-t283 are candidates.
- niri reference: `~/src/niri` 5f4469b6.
