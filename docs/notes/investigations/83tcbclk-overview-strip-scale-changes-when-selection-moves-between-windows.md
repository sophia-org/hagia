---
id: 83tcbclk
date: 2026-09-25
kind: investigation
status: resolved
tags: [investigation]
---
# Overview strip scale changes between windows and workspaces

## Question

Why does navigating overview resize the strip between a fullscreen window and
an ordinary Kitty window, and between desktops with different window counts?
These are niltempus's live observations after installing the paired overview
implementation. Hagia h003 owns the bounded policy correction.

## Evidence

The baseline is signed Hagia `d3accb15530ad4863073a207c38f371fe76d9077`.
The fix is developed on `fix/overview-strip-sizing` in
`~/dev/hagia-overview-fix`, with signed source checkpoint `3d8efff`.
Paired checks use Sophia's clean
`rendering/foundation` worktree at `c0f54161`, whose tree equals accepted master
`8bd8c41c2ced6a06200ed20faa870c4180889155`.

Three deterministic failures reproduce the reported behavior:

- `overview-red.log`: selection changes a fullscreen thumbnail from 640 by 400
  to 960 by 600. Its ordinary neighbor also changes size. The test covers both
  scrolling axes, full-width columns, fullscreen state, a reserved panel area
  and a negative output origin.
- `adapter-red.log`: a real `PolicySession` reduction changes generic instance
  geometry and generations merely by moving selection; the fullscreen instance
  grows from 480 by 360 to 720 by 540. Returning selection does not recover the
  original instance records.
- `workspace-scale-red.log`: after fixing selection-driven camera movement, a
  three-window desktop still has 320 by 400 thumbnails while a one-window
  desktop has 480 by 600 thumbnails.

These are headless reproductions of policy and adapter behavior, not captures
of the running compositor. Original logs live under
`~/dev/hagia-overview-fix/.artifacts/h003/`; checksummed durable copies and the
built candidate are retained at
`~/.local/state/hagia/development-evidence/h003-3d8efff/`.

## Finding and resolution

Hagia projected each workspace after changing its private focus to the overview
selection. In a scrolling layout that moved the preview camera. Fullscreen
placements stayed anchored to the output, changing the union of source bounds
and therefore the fit scale. Separately, each workspace computed its own fit,
so a sparse workspace magnified windows relative to a wider occupied strip.

Scrolling previews now retain the workspace's camera while navigation changes
only the selection emphasis. Monocle and deck still promote the selected window
inside their preview, preserving their existing navigation behavior.

The geometry owner computes every included workspace's source extent, including
rows currently clipped outside the output, then derives one aspect-preserving
ratio for that monitor. All its previews use that ratio. The physical output
bounds provide a shared baseline even when normal placements use a panel-reduced
work area. Every occupied strip still fits; a sparse desktop no longer enlarges
its thumbnails. Real changes to contents or output geometry may change the fit.

The change stays in Hagia's pure projection and passive extent data. Sophia's
rendering, input authority, source retirement and wire contract are unchanged.
Ordinary client geometry and focus remain unchanged until confirmation.

## Validation and remaining work

The policy regression checks both scrolling axes and both fullscreen and
full-width cases, unchanged normal projection, return navigation and cancellation.
The workspace regression checks equal-size sources on differently populated
desktops and stable dimensions while changing desktops. The adapter regression
checks exact instance records and generations stay fixed while emphasis changes.

All eleven policy and eleven adapter tests pass. The complete `nimble verify`
contributor gate exits zero: 323 Nim cases, both eleven-scenario policy corpora,
paired profile admission, pointer focus, five overview/capability controls and
launch origin, eight Alloy assertions, Z3 expectations and four TLA+ checks.
The paired gate retains two existing ignored controls; it claims no coverage
from filtered or ignored cases. Formatting and data-oriented layout pass.

All paired execution hides devices and live session sockets, clears inherited
smoke/configuration flags, uses a disk-backed Cargo cache and runs at nice 10
with two Cargo jobs. Nim builds run serially. The first full run stopped because
the temporary directory prefix exceeded the Unix socket path limit in Sophia's
profile-admission test. `verify-long-temp-path-red.log` preserves that failure.
The successful rerun maps a private disk directory to `/tmp`; source is unchanged.

The live reports establish the original problem. The implementation exit is
complete, with physical acceptance still pending. niltempus subsequently
authorized a Hagia-only live reload; at this checkpoint no reload, installation
or synthetic input has occurred. The installed session uses a root-owned sealed
desktop release, so any temporary live test must preserve its original binary
and release verification. A running replacement and the visual result must be
verified separately from the headless checks.

## Connections

The [h002 lifecycle investigation](knylvwd5-overview-generic-publication-and-receipt-lifecycle-checkpoint.md)
records the paired overview foundation. The
[overview plan](../plans/64ac6jf6-workspace-overview-across-hagia-narthex-and-sophia.md)
owns the original feature scope. This correction changes preview geometry only;
the separate maximize persistence defect remains Hagia h001 in
[the queue](../../../todo.md).
