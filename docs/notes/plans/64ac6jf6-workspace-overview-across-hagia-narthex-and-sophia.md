---
id: 64ac6jf6
date: 2026-09-24
kind: plan
status: proposed
tags: [plan]
---
# WM-owned workspace overview on generic presentation support

## Intent and source

Hagia h002 owns the Super+O workspace overview requested by niltempus. The initial
experiment spanned the WM, shell and Sophia; the 2026-09-25 ownership correction
places all overview policy in the WM. Triad
baseline `fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9` supplies the behavior:
workspace strips, spatial navigation, Return to select, Escape to cancel.
`~/src/niri` is a design reference only. The personal config was inspected as
an example and is not copied or modified.

## Authority and implementation

Hagia owns a pure preview of output-local workspace layouts and validates
selection of a logical view/window. Preview generation must preserve the
committed workspace, focus, widths, and cameras. It does not configure windows
at thumbnail sizes. Only a confirmed selection changes WM policy.

Hagia must also own overview arrangement, open/close behavior, modal navigation
and the selected workspace/window. Sophia supplies generic, capability-checked
surface presentation and reduced actions tied to the retired presentation. A
shell is not a required intermediary. The provisional shell navigation reducer
and overview-specific Sophia service are preserved experiments to be superseded;
the corrected ownership has not yet been fully implemented.

Sophia t242 defines the generic presentation and input contract as a planning
prerequisite to paired acceptance t241. Its architecture document is
`docs/rendering-foundation.md` in the Sophia repository; its linked zk plan and
investigation distinguish existing renderer mechanisms from proposed instances.
Documentation and contract definition are authorized. The planning task alone
does not admit the proposed foundation implementation or a wire freeze.

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
native frame lowering uses the existing owned source path. Source leases must
survive queued/executing render work; copied native backings survive submission,
display and retirement. Closing the overview revokes input immediately without
releasing either resource while its consumer needs it. Hidden client content
must remain resident while referenced by a render operation.

The provisional design mapped shell slots to workspace/surface identities.
That shell-specific mapping is superseded by t242's role-based contract work.
The generic version must bind WM instance/action identities to their connection,
generation, output topology and exact presented state. Close, topology change,
source loss or reconnect revoke input authority; late replies cannot recreate it,
and swallowed presses retain their release debt. This is an acceptance
requirement, not a claim that the unfinished session integration satisfies it.

The production preview-only source/update control subsequently passed with
simulated native completion. It found and fixed source lookup omitting preview
references. Source leases remain owned through queued/installed copying; copied
native backings remain owned until retirement. Both negative controls and the
restored pass are retained under
`~/.local/state/hagia/development-evidence/h002-preview-20260925/`.
The development investigation in Sophia is
`docs/notes/investigations/egmb00jq-rendering-foundation-inventory-and-overview-ownership-correction.md`.
Complete WM navigation, the generic wire/input contract, end-to-end lifecycle
proofs and physical acceptance remain outside that rendering test's claim.

## Implementation authorization and policy checkpoint

The subsequent instruction from niltempus to implement the rendering plan
supersedes the planning-only restriction above. Sophia implementation now uses
`rendering/foundation`, `rendering/instances` and `rendering/input`; the earlier
overview-specific prototype remains preserved. Narthex is not required for
Hagia's overview. Sophia t242–t245 provide generic presentation mechanisms;
Hagia h002 continues to own layout, navigation and selection policy.

Hagia checkpoint `e326c298` replaces the provisional overview wire with the
independent generic presentation codec. Its four presentation controls, four
shared wire corpus controls, standalone build and data-oriented layout gate
pass. The following policy slice adds transient overview state, per-output
preview geometry and modal actions. Eight overview controls and all 180 policy
model controls pass. Opening, navigating and cancelling preserve ordinary
focus and layout; confirmation applies the selected workspace and window.
Checkpoint restoration does not serialize this transient state.

Adapter publication, exact target mapping, receipt retirement and paired
session input acceptance remain required. These checks establish deterministic
policy behavior and do not claim a complete or physically accepted overview.
