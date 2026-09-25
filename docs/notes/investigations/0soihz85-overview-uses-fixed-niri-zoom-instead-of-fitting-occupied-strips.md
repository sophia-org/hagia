---
id: 0soihz85
date: 2026-09-25
kind: investigation
status: investigating
tags: [investigation]
---
# Overview uses fixed niri zoom instead of fitting occupied strips

## Question

Why did overview windows remain too small after h003 made strip sizing uniform,
and what does the local Niri reference do instead? Hagia task h004 owns this
policy correction. niltempus requested the Niri reference after trying the
overview in a live session.

## Evidence

Signed source candidate `e3fe2b4e70def3573d2c6af64ec48966048d2435` is on
`fix/overview-niri-zoom` in `~/dev/hagia-overview-fix`. Paired verification
uses Sophia `c0f54161`, whose tree equals accepted master `8bd8c41c`.

Hagia master `9bce6ff344ed0ef9fdad9c8b5883f11c2e54b091` includes h003's
content-derived fit. It computes the widest and tallest occupied workspace,
then fits that extent into a 60% viewport. Every additional column can therefore
make every thumbnail smaller, even though navigation preserves their scale.

Niri `5f4469b6a992492cf7221b269e9379f42e737649`, inspected read-only in
`~/src/niri`, instead defaults to zoom 0.5 in `niri-config/src/misc.rs`.
`compute_overview_zoom` in `src/layout/mod.rs` does not fit occupied content.
`workspace_size`, `workspace_gap`, `workspaces_render_geo`, and
`render_workspaces` in `src/layout/monitor.rs` scale the viewport, center the
selected row, leave one tenth of its height between rows, and clip vertically
while allowing the horizontal strip to extend beyond its workspace frame.

Evidence is retained in `hagia-overview-fix/.artifacts/h004/`:

- `overview-red.log`: fixed-half-size assertions fail against the h003 fit.
- `navigation-camera-red.log`: with a committed camera anchor, the first
  fixed-zoom candidate cannot navigate back from a normal window whose center
  coincides with its fullscreen neighbor.
- `overview-first-fixed-run.log` and the first adapter failure record fixture
  assumptions and the navigation defect, rather than a successful gate.
- `clipping-adapter-red.log` reproduces the selected thumbnail below a
  fullscreen neighbor. Its separate oversized-floating fixture is refused by
  ordinary policy validation, so it is not evidence of an invisible border.
- `overview-green.log` and `adapter-green.log`: focused corrected policy and
  adapter runs. The adapter confirms the original window after moving back.
- `verify.log`, `verify.exit`, and `run-verify.py`: full contributor gate and
  its device-hidden execution environment.

Checksummed durable copies, `gate-summary.json`, and the built candidate are at
`~/.local/state/hagia/development-evidence/h004-e3fe2b4/`. The executable's
SHA256 is `8dae3277819b319962d8c85fb18437d2b0e63971a9615f8a4b0e70716b5d5d04`.

## Finding and resolution

The sizing error belongs to Hagia's pure overview projection. Each source now
uses fixed 1/2 geometry, independent of population. The selected workspace is
centered in the output; each row clips to the output's horizontal bounds and
its own vertical extent. Offscreen sources are omitted, and selection pans only
a private projection candidate to reveal the selected window. Cancelling leaves
the committed model untouched.

Fullscreen and maximized output-anchored rectangles can coincide with another
column after panning. Scroller navigation uses the underlying strip projection
on a separate private candidate with expansion removed, preserving directional
order without changing the displayed size or the actual client state.
The selected preview is raised within its own workspace row so a fullscreen
neighbor cannot cover it. Ordinary application stacking stays unchanged.

This supersedes h003's content-fit and stationary-preview rules. Its historical
headless evidence remains valid for the old rule; it did not establish the
visual size requested here. No new wire, configuration setting or renderer
behavior is introduced by h004.

## Validation and remaining work

Focused checks cover a nine-window strip, both scrolling axes, two outputs,
differently populated workspaces, fullscreen/full-width neighbors, a settled
camera, round-trip navigation, selected preview stacking, unchanged ordinary
projection and cancellation.
The full `nimble verify` contributor gate passes on source `e3fe2b4`: 325 Nim
cases, both eleven-scenario policy corpora, paired profile admission, pointer
focus, five overview/capability controls and launch origin, eight Alloy
assertions, Z3 expectations and four TLA+ checks. Two existing ignored paired
controls remain excluded; filtered zero-test targets are not counted as proof.
Formatting and the data-oriented layout gate pass. All paired execution hides
devices and live session sockets, clears inherited smoke/configuration flags,
uses a disk-backed Cargo cache, and runs at nice 10 with two Cargo jobs. Nim
builds are serial.

Review also considered a selected rectangle surrounding all four clip sides,
which could leave an emphasis border with no drawable bands. No production
route to that rectangle was established: floating geometry must remain inside
its output, and the valid minimum-width scroller control retains top/bottom
bands. The refused fixture and corrected constraint fixture are retained. No
speculative emphasis change is included. The first full gate was deliberately
interrupted for the stacking review fix; its partial log makes no acceptance
claim.

Further live acceptance requires Sophia t246. Its independently reproduced
backend defect rejects a Present whose source is legitimately absent from a
replacement publication. Fixed-zoom clipping intentionally omits such sources.
Its production-owner controls also found that ordinary visibility could retry
a policy-hidden first Present and reset its expiry; t246 owns that correction.
The exact cause of the reported live crash remains unproven because its raw
error and publication were unavailable. No install, reload or physical test is
part of this evidence.

## Connections

- [h003 strip sizing](83tcbclk-overview-strip-scale-changes-when-selection-moves-between-windows.md)
  records the superseded fit rule and its original regressions.
- [Overview plan](../plans/64ac6jf6-workspace-overview-across-hagia-narthex-and-sophia.md)
  records the WM/rendering ownership boundary.
- Sophia t246 investigation:
  `docs/notes/investigations/kc13g2uh-an-unsampled-present-can-terminate-a-replacement-presentation-session.md`.
