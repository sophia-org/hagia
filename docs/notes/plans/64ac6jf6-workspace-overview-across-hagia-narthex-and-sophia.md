---
id: 64ac6jf6
date: 2026-09-24
kind: plan
status: proposed
tags: [plan]
---
# Workspace overview across Hagia Narthex and Sophia

## Intent and source

Hagia h002 implements the user's Super+O workspace overview request. The user
explicitly approved expanding implementation to Narthex and Sophia. Triad
baseline `fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9` supplies the behavior:
workspace strips, spatial navigation, Return to select, Escape to cancel.
`~/src/niri` is a design reference only. The personal config was inspected as
an example and is not copied or modified.

## Authority and implementation

Hagia owns a pure preview of output-local workspace layouts and validates
selection of a logical view/window. Preview generation must preserve the
committed workspace, focus, widths, and cameras. It does not configure windows
at thumbnail sizes. Only a confirmed selection changes WM policy.

Narthex owns overview open/close, ordered workspace descriptors and selection.
It receives bounded shell slots, never surface IDs, geometry, buffers or pixels.
Sophia bridges published WM facts to those slots, renders scaled scene previews,
captures modal input against retired presentation, and validates activation.
The shell does not acquire screenshot or application-input authority.

The interface must be negotiated and bounded, retain independent Nim codecs,
and revoke stale presentation on output loss, window removal, WM or shell
restart, and conflicting modal surfaces. Existing switcher/help/launcher paths
keep their current semantics.

## Acceptance

Super+O opens and closes the workspace overview. Arrow keys and h/j/k/l navigate;
Return selects; Escape cancels without changing workspace or focus. Pointer
selection is tied to the displayed generation. Each output retains its own
workspace. Empty workspaces remain selectable. Tests exercise input capture,
stale/rejected candidates, cancellation, output loss and reconnect. CPU and
native paths share the same preview geometry without resizing application
buffers. Offline tests precede any live acceptance; live reload/install remains
unauthorized.

## Work locations

Hagia and Narthex use branches named `overview`. Sophia uses branch `overview`
in `~/dev/sophia-overview`, isolated from Claude's main-tree XTS gates. Sophia
baseline `4f5ff135` and Hagia baseline `ad3a738d` were captured at branch creation.

## Boundary review: 2026-09-25

The retained work was signed before rebasing Sophia onto `97a6b6f6`.
The t159 default shortcut catalog/admission changes remain intact. No live
install/reload, main-tree changes, X-authority changes, or device negotiation
changes are part of this work.

Preview commands refer to generational Engine surfaces and sample their committed
content at a separate destination and clip. They do not mutate client geometry,
input geometry, buffer size, or content. CPU rendering borrows retained pixels;
native frame lowering uses the existing owned source path. Frames already queued
must retain their source ownership until ordinary frame retirement. Closing the
overview revokes input immediately; it does not release a source still held by a
submitted frame. Hidden client content must remain resident while referenced by
a frame. This last residency/retirement path still needs end-to-end verification.

The session must retain the slot-to-workspace/surface mapping for one WM epoch,
catalog generation, shell epoch and output generation. Only a candidate retired
on that output grants overview input authority. Each input request names its
presentation epoch; candidate replies must match the outstanding request and
catalog, and activation must match the requested selection. Close, topology
change, WM invalidation or reconnect must revoke this mapping and capture before
any later input can be admitted. Swallowed presses retain their release debt
after revocation. Queued work and old replies cannot recreate authority.

These are acceptance rules, not a claim that the unfinished session integration
already satisfies them. Renderer compilation and focused model/wire tests are
the first checkpoint; modal integration and headless lifecycle proofs remain.
