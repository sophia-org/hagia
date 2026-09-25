---
id: 1ncr7rbo
date: 2026-09-25
kind: investigation
status: diagnosed
tags: [investigation]
---
# Expanded overview preview sizing differs from niri column geometry

## Question

After reporting that overview looked good in the new live session, niltempus
requested a comparison with Niri for normal, maximized and fullscreen windows.
Does h004's fixed zoom also preserve those windows' sizes during selection?

The initial sections retain the post-install audit of h004. The h005 follow-up
below records the subsequently authorized correction and its headless evidence.
Neither is a physical acceptance claim for these specific cases.

## Evidence

Hagia source is signed master `6717db5de1c62e1fe5869b674382f6b8ef7bc611`.
The read-only Niri reference is `5f4469b6a992492cf7221b269e9379f42e737649`
in `~/src/niri`; its existing deleted `docs/uv.lock` was left untouched.

Offline probes and logs are retained under
`~/.local/state/hagia/development-evidence/overview-sizing-6717db5/`:

- `sizing_probe.nim` and `probe.log` exercise normal, full-width,
  edge-maximized and fullscreen windows in both Hagia scrolling axes, plus
  an ordinary floating window. The output is 1600 by 1000, with a 32-pixel
  reserved top area and negative horizontal origin in the tiled cases.
- `niri-size-invariant-red.log` and its exit file retain the failed assertion
  that an expanded preview keeps its dimensions when selection leaves it.
- `adapter_probe.nim` and `adapter.log` run the existing adapter suite plus
  a reproduction through real `PolicySession.prepare`/commit and validated
  outgoing generic presentation records. Completion is synthetic; no Sophia
  session or device participates.
- `policy-suite.log` records the unchanged overview policy suite.

The reference behavior comes from Niri source inspection, not a Niri live test:
`niri-config/src/misc.rs` defaults to zoom 0.5;
`src/layout/mod.rs::compute_overview_zoom` applies that fixed zoom;
`src/layout/monitor.rs::render_workspaces` scales the rendered workspace without
choosing a different window size for selection. In `src/layout/scrolling.rs`,
`update_tile_sizes_with_transaction` requests expanded sizes, `width` uses the
largest actual tile width, and `column_xs` adds those widths and gaps. Its
`columns_with_render_positions` moves those columns by the view offset.
`src/layout/tile.rs::request_maximized` uses the parent work area;
`request_fullscreen` uses the full viewport. Hagia's vertical scroller is an
additional policy, not a layout supplied by Niri.

An independent read-only review by w9:pF confirmed both differences. In Niri,
maximized state is persistent per column; changing the active column does not
clear it. That reviewer also confirmed that the parent area passed to maximized
tiles is the workspace work area, and that full-width columns remain a separate
gap-aware sizing mode. Neither review ran or modified Niri.

## Finding and resolution

The fixed 50% scale and workspace row dimensions are correct. The audit found
two remaining differences in Hagia's overview projection.

| Window state | Hagia result | Comparison with Niri |
| --- | --- | --- |
| Normal tiled | 800 by 968 becomes 400 by 484; selection preserves size | Matches the fixed zoom rule |
| Normal floating | 640 by 400 becomes 320 by 200; selection preserves geometry | Matches the fixed zoom rule |
| Full-width column | 1600 by 968 becomes 800 by 484; selection pans without resizing | Matches the full-width column rule; this is distinct from edge maximization |
| Edge-maximized tiled | 800 by 484 preview becomes 400 by 484 when selection leaves it | Diverges: Niri retains expanded size as focus/scroll changes |
| Fullscreen | 1600 by 1000 becomes 800 by 500 and retains that size | Size matches; placement remains output-anchored rather than consuming a full-size strip column |

For edge maximization, [overviewWorkspaces](../../../src/policy/overview.nim)
sets focus on a private candidate to follow selection, then calls the ordinary
layout. [appendFloating](../../../src/policy/projection.nim) derives effective
tiled maximization from the focused family. Leaving that family removes its
expansion, and the ordinary suppression of its neighbors also lifts. Thus the
preview changes size even though the scale and row frame stay constant. The
vertical analogue is 800 by 484 becoming 800 by 242.

The adapter reproduction confirms this is emitted behavior: on its 1200 by 900
fixture the same source identity changes destination from 600 by 450 to
300 by 450. Both publications pass wire-shape validation, and their ordinary
application projections remain equal. Sophia receives a narrower destination
for the same retained source; this is not a renderer choosing another scale.

Fullscreen has a separate placement difference. The first fullscreen preview
occupies x=-1200..-400, while its ordinary neighbor occupies x=-800..-400.
Their interiors overlap. Raising the selected preview makes navigation usable,
as h004 established, but does not reproduce Niri's separate expanded column
footprint. Niri's column positions are derived from full tile widths before
the entire workspace is scaled.

The existing test named "selection does not resize a strip with a full-width
or fullscreen neighbor" sets `column.fullWidth` and optionally `fullscreen`;
it never sets `window.maximized`. Its passing result did not cover the
edge-maximized case. The fullscreen adapter control likewise checks size and
selected stacking, not disjoint column footprints.

## Validation and remaining work

The existing 12 policy controls and 12 adapter controls pass. The additional
adapter reproduction passes by asserting the observed size change; it is
evidence of the defect, not an acceptance test for Niri parity. The explicit
stable-expanded-size assertion fails as expected. All eight tiled probe cases
preserve the ordinary projection, restore the initial preview after reverse
navigation, and leave the full model unchanged after cancellation. The floating
probe also preserves its size and ordinary state.

An overview correction should keep expanded preview dimensions independent of
speculative selection, allocate their actual extents in the preview strip, and
move the camera to reveal selection. It belongs to Hagia's spatial projection;
ordinary focus-dependent edge maximization and Sophia's generic rendering
contract need not change. That implementation has not been made by this audit.
Future controls should cover edge maximization separately from full width,
expanded-neighbor non-overlap, both Hagia axes, panel work areas, selection
round trips and unchanged ordinary client geometry. Integer/fractional pixel
rounding and animation parity were not assessed here.

No live commands, install, reload, main-tree edits or source changes were made.
The user's positive live observation is retained without inferring that these
specific edge cases were physically exercised. No new queue item was opened
or completed during the review.

## h005: authorized overview correction

niltempus subsequently authorized correcting these differences. The scope is
Hagia's overview geometry, navigation and tests. Sophia's protocol, renderer,
ordinary application configuration and live session are outside this change.

`policy/overview_scroller.nim` builds a private preview strip. Maximized tiles
use the workspace work area, fullscreen tiles use the physical output bounds,
and their sizes do not depend on selection. Every column consumes its actual
preview width before the fixed 50% zoom. The preview camera reveals the selected
column using the shared scroller reveal/center arithmetic. The vertical
scroller applies the same rule through the existing transpose operation.

Following Niri's `set_maximized` and `set_fullscreen` extraction rule, an
expanded tile sharing a scrolling column gets a virtual column immediately to
the right of its remaining siblings. Existing entity operations perform this
on a deep clone. Multiple expanded siblings use their deterministic original
column order; Niri's resulting order instead depends on the expansion event
sequence. The ordinary column membership and restore semantics stay
Hagia's; confirming a preview names the original window and workspace. This is
an intentional difference between the overview strip and the ordinary strip,
not a change to application layout. Non-scrolling layouts keep their existing
projection. Full-width columns remain distinct from edge maximization; when
both flags exist, overview maximization takes precedence, including with gaps.

The camera remains a pure projection of the committed workspace and current
overview selection. Its baseline is the clone's ordinary reveal for the selected
window after virtual extraction, derived from the committed camera. That offset
is translated into preview coordinates before reveal. It has no separate
movement history: returning to a
previous selection restores its derived camera, whereas Niri can keep the last
camera still when a backward step is already visible. Adding retained preview
camera state is outside this sizing correction; stationary backtracking and
animation parity are not claimed.

The ordinary projection's combined tiled/floating pass is split without changing
its call order. Both paths reuse the same floating-family resolver after tiled
geometry is final. Dialogs resolve against preview parents, and raising a
selected parent retains its children above it. Ordinary floating geometry stays
unchanged. Hagia's expanded floating windows retain their existing semantics;
Niri instead tiles such windows with a restore-to-floating flag. This correction
does not introduce that separate state transition.

The old navigation workaround, which erased expansion to recover distinct
centers, is removed. Navigation now reads the same expanded strip that overview
shows. Instance clipping still intersects both the row and output bounds;
empty intersections are omitted before publication. Source and instance ids
remain adapter-owned and unchanged by this policy pass.

The six added policy controls cover stable size and full footprints on both
axes, multiple expanded columns, shared-column extraction and confirmation,
floating/dialog size and stacking, translated camera centering and visibility,
and maximization taking precedence over full-width sizing with gaps. The camera
walk starts with the expanded column first; its backward bound is the strip
start. The adapter control follows actual outgoing records and preserves source
identity, expanded dimensions, positive clipped area and ordinary projections.

The initial full contributor gate passed before the camera/full-width review
corrections. The final focused policy suite passes 18 controls. Independent
read-only review accepted the geometry and camera correction. An early camera
fixture assumed two half-width columns triggered on-overflow centering; they
correctly fit. Its failure is retained as a fixture error, not defect evidence.
The corrected fixture uses widths that do overflow, and an isolated copy with
camera translation removed supplies the negative control. Final contributor
results and the signed candidate identity follow below. The initial h005 failure
and the original audit's stable-size failure remain retained as red evidence.
Live installation, hardware rendering, animations and physical acceptance are
not part of this headless correction.

## Connections

- [h004 fixed zoom](0soihz85-overview-uses-fixed-niri-zoom-instead-of-fitting-occupied-strips.md)
  owns the landed scale, camera and stacking correction; this audit narrows its
  maximized/fullscreen comparison claim with additional evidence.
- [Overview plan](../plans/64ac6jf6-workspace-overview-across-hagia-narthex-and-sophia.md)
  keeps layout and selection in Hagia while Sophia owns generic presentation.
