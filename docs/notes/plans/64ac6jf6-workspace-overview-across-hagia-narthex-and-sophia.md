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
