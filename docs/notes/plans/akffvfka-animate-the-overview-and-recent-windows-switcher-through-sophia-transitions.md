---
id: akffvfka
date: 2026-10-02
kind: plan
status: proposed
tags: [plan, milestone]
---
# Animate the overview and recent-windows switcher through Sophia transitions

## Scope and exit

niri's overview opens and closes with a smooth zoom, and Hagia's jumps.
Sophia plan bzofyaco (t285-t288) adds compositor-driven transitions. The WM
declares a target presentation plus a transition, and Sophia interpolates at
display rate. Hagia stays blind and event-driven: it never runs a clock and
never publishes per-frame state.

Exit for each task: adapter and model tests showing the declared transition
specs and enter sources, unchanged behaviour when the capability is not
negotiated, and replay. Live acceptance means comparing Super+o and the
switcher beside niri, including interrupting mid-animation and reduced
motion. This plan does not claim it.

## Task details

<a id="h016"></a>
**h016: overview open and close transition, candidate.** Peer:
sophia/t286. Depends on h009.
- With Sophia's presentation-transition bit negotiated, the overview
  publication declares niri's spring (stiffness 800, damping ratio 1.0)
  as its default.
- Each window instance enters from its source surface's placement, which
  gives the zoom-out. Closing withdraws the publication with a reverse exit
  transition.
- Without the bit, the publication is unchanged.

<a id="h017"></a>
**h017: recent-windows strip transition, candidate.** Peer: sophia/t286.
Depends on h009.
- The held strip and the modal switcher fade in on open and out on close.
- The selection highlight retargets smoothly between candidates.
- Preview instances keep the t284 custody rules. Scope changes (a, w, o, s)
  retarget the instance set rather than replacing it.

## Connections

- Sophia plan bzofyaco (compositor-driven transitions) and its candidates
  t285-t288. The engine design is approved: TEA-shaped and closed-form in
  time.
- [niri parity plan](n6dx1wbt-niri-parity-for-the-recent-windows-switcher.md)
  (h009-h015).
- [Workspace overview](64ac6jf6-workspace-overview-across-hagia-narthex-and-sophia.md).
- niri reference: `~/src/niri` 5f4469b6, `src/layout/mod.rs`
  compute_overview_zoom and `niri-config/src/animations.rs`.
