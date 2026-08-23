# Triad Port Completion Ledger

This ledger defines what “Triad is ported to Hagia” means before Sophia may
freeze revision 3 of `sophia_wm_v1`. The unit of parity is retained behavior,
not source files, process shape, River protocols, or command spelling.

The reviewed source baseline is
`fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9`. A row is complete only when its
retained behavior has an owner, a bounded interface, deterministic tests, and
the required live evidence. Moving behavior to the correct Sophia authority is
part of the port; putting every feature in the Hagia policy process would
violate the architecture.

## Completion Rule

Revision 1 remains experimental while any retained row below is partial or
open. The port gate closes only when:

1. every Triad feature family is classified as retained or excluded;
2. every retained family works through its assigned authority with no hidden
   River, Wayland, Triad, or Niri runtime dependency;
3. the retained default desktop configuration has a validated migration and
   no accepted command silently loses behavior;
4. deterministic parity scenarios cover state transitions, failure, restart,
   and authority loss; and
5. ordinary installed sessions cover the physical workflows that cannot be
   established offline.

An exclusion requires a written architectural or product rationale. “Not yet
implemented” is not an exclusion. A later Triad change is considered
separately and does not move this recorded baseline.

The current 28-row classification is 3 complete, 14 partial, and 11 open.

## Spatial Policy — Hagia

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Stable logical windows, outputs, tags, views, columns, and reconciliation | Complete | Keep opaque Sophia identities adapter-local and preserve complete-snapshot settlement. |
| Scrolling columns and fixed-point geometry | Partial | The retained scroller is implemented; port remaining user-visible proportions, focus/centering rules, movement, gaps, and constraint behavior selected by the migrated profile. |
| Tags, workspaces, names, dynamic creation/pruning, occupancy navigation, and output affinity | Partial | Nine fixed views, nonempty multi-tag actions, dynamic creation/pruning, occupied navigation, and stable output affinity exist; configured names and complete command parity remain open. |
| Focus, movement, exchange, grouping, histories, and cross-output behavior | Partial | Core focus and column operations exist; complete Triad command semantics and parity cases remain open. |
| Floating, fullscreen, maximize, minimize, restore, and client-visible state | Partial | Core reducers and frontend settlement exist; complete floating placement, snapping, restoration, and rule-driven defaults remain open. |
| Dialogs, transients, popups, and scratchpads | Complete | Reduced parent/role facts drive dialog defaults; standard and named scratchpads cycle and restore through bounded logical relations. Popup rendering remains outside WM policy. |
| Additional native layouts, frames, tabs, BSP/split trees, grid, and layout switching | Partial | The five-layout compiled native cycle is implemented with per-view state and deterministic projections. Frames, tabs, BSP/split trees, and visible feedback remain open and shell chrome stays outside WM policy. |
| Declarative policy configuration | Complete | Provenance-bearing startup candidates reconcile configured views and native layouts on a clone, validate the full logical model, and preserve last-known-good state on failure. Watched reload remains deferred to the cross-authority protocol. |
| Janet commands and layouts | Open | Bound execution and memory, validate candidates, make output deterministic, and prove native fallback before activation. |
| Placement, sticky behavior, swallowing, size policy, and window rules | Open | Hagia consumes only opaque broker-issued classifications and reduced parent/state facts. It never receives title, app ID, PID, path, or regex input. |
| Completed and continuous pointer policy interactions | Partial | Engine-captured move/resize now cross as ordered Begin/Update/End values with latest queued Update replacement; topology, VT, seat, and policy-restart revocation clear capture and prioritize Cancel, which Hagia applies as a spatial no-op. Drag/scroll producers remain open. |
| Checkpoint, crash, reconnect, and last-layout preservation | Partial | Checkpoint restart passed physically; shared reconnect/restart, configuration recovery, and full retained-state parity remain open. |

## Visible Desktop — Hagia Shell

These behaviors cannot be moved into `sophia_wm_v1`. They require a separate,
least-authority shell endpoint and target-resolved input.

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Overview and workspace previews | Open | Port navigation, preview geometry, hot corners, scroller overflow hints, and hold/cycle behavior without granting WM metadata or raw input. |
| Recent-window switcher | Partial | Sophia's offline title-only reference proves bounded brokered descriptors, shell-supplied order/selection, per-head rendering, exact presented opaque activation, and cancellation. A protected Hagia Shell client, recency policy, scope, filtering, debounce, previews, dispatch, and live evidence remain open. |
| Frame tabs, tab bars, BSP preselection, and drop previews | Open | Render shell-owned display lists tied to opaque policy entities and presented target snapshots. |
| Hotkey overlay, layout toast, notifications, and confirmation dialogs | Open | Keep visual state in the shell and privileged effects in session/portal services. |
| Panels, status, shell profiles, and shell state streams | Partial | Hagia's bounded view and layout descriptors feed Sophia's Tier-0 per-head indicator chrome and opaque captured actions; signed physical archive `0005` proves fullscreen coexistence, restart, view-2/view-1 pointer activation, both outputs, and clean teardown. Rich panels, shell profiles, output/session health, and Tier-1 state streams remain separate shell work. |

## Session And Dedicated Sophia Authorities

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Physical key, pointer, axis, gesture, switch, and shortcut matching | Partial | The public shortcut owner retains its canonical typed candidate in a separate authority-local slot, crosses the mandatory seven-owner startup activation barrier, and resolves Hagia's semantic action catalog into Engine-owned matching without sending raw input to Hagia. Add the retained axis, gesture, and switch candidates. |
| Input-device and XKB configuration | Partial | The canonical typed input payload resides in a cohesive authority-local owner slot and crosses the mandatory startup activation barrier; existing RMLVO, repeat, lock-state, natural-scrolling, acceleration, handedness, middle-emulation, and wheel-scaling preparation reads that payload. Add device-scoped capabilities and cross-authority watched prepare/activate/rollback. |
| Output mode, scale, position, transform, VRR, enablement, power, and reservations | Partial | The canonical typed output payload resides in a cohesive authority-local owner slot, crosses the mandatory startup identity-activation barrier, and reconciles purely against immutable capabilities. The atomic owner exposes read-only libdrm facts, and a pure adapter joins them to Engine outputs without overclaiming support. Identity activation does not apply hardware: add atomic multi-output testing/apply, rollback, reservations, and a separate power authority. |
| Launch, startup environment, configured processes, and shell supervision | Partial | Typed terminal/browser/startup/logout selectors resolve only against Sophia's registered applications. A bounded immutable overlay centralizes CLI-superior application additions, arguments, startup order, and action mappings in one pure cloned-registry preparation seam. The canonical session payload now crosses the mandatory startup activation barrier; port the remaining retained launch environment and supervision behavior. |
| Lock, logout, session exit, idle inhibition, and shortcut inhibition | Open | Security transitions preempt lower authorities, advance epochs, revoke leases/captures, and settle through dedicated services. |
| Cursor theme, visibility, inactivity, and find feedback | Open | Engine owns the cursor; expose only bounded configuration and shell feedback. |
| Configuration discovery, validation, activation, reload, and rollback | Open | Discovery, partitioning, staging, exact fragment admission, and typed preparation exist. The generation/digest barrier retains a monotonic attempt counter and executable TLA+ proofs; Sophia carries the matching coordinator, exact-key participant reducer, and separate prepare-only startup driver. Every public Hagia launch now prepares all seven owners, activates six local slots, and promotes only after Hagia acknowledges the exact Policy identity, all before graphical construction. Timeout, disconnect, rejection, or local failure rolls the generation back. Cross-layer and production-path tests cover identity/payload convergence and rollback. Watched reload remains disabled until a separate global visibility and durable-recovery protocol is modeled and implemented. |

## Brokers And Portals

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Application classification and launch placement | Open | A trusted broker maps sensitive metadata to opaque, expiring placement grants. |
| Window lists and shell-facing descriptors | Partial | The protected broker emits sanitized exact-generation descriptors, and Sophia's offline reference renders their labels while preserving but not rendering icon tokens. Add the protected shell-role transport, admitted client lifecycle, revocation/dispatch path, and live proof; keep all metadata out of WM input and policy hot paths. |
| Screenshots and capture sessions | Open | Require explicit portal grants, visible indicators, bounded lifetime, and revocation. |
| Clipboard, drag-and-drop, files, and notifications | Open | Use dedicated portals with typed payload limits and authority-local disclosure. |

## Excluded Compatibility Machinery

The following are not part of the port gate because they adapt Triad to a
different compositor or expose compatibility surfaces rather than retained
desktop behavior:

- River and Wayland client adapters, registry code, and generated protocols;
- Niri command, JSON, socket, and shell-compatibility façades;
- River-specific layer-shell, screencopy, output-management, input-management,
  XKB, pointer-warp, and presentation protocol glue;
- the Triad mirror executable and compositor-specific diagnostic paths; and
- unrestricted command execution or a general metadata-rich Triad IPC socket.

Native output mirroring is not silently excluded: it remains an output-service
product decision and must be either implemented with evidence or explicitly
rejected before the port gate closes.

## Port Order

The first blocking tranche has converted the retained key/pointer subset and
session launch selectors into validated authority-local startup candidates.
It now continues into typed input/output preparation and cross-authority
activation without introducing a policy-only reload path.
Each later command family ports or reimplements the relevant Triad tests before
live integration.

The binding inventory also exposes a public-boundary pressure. Hagia's
compiled profile contains 50 Sophia-owned chords resolved against Hagia's
66-entry action catalog, while Triad's
baseline default configuration contains 132 key bindings and 137 total
physical bindings. Those counts cross multiple future authorities, so they do
not mechanically choose a new WM bound. The new multi-tag transitions therefore
remain unbound private reducer capabilities until configuration migration
selects retained commands and their correct owners. The inventory does prove
that 64 cannot be frozen without first classifying and migrating that set. The
semantic migrator now classifies all 137 physical bindings and separately
records shortcut-match ownership and target behavior authority. Unsupported
rows remain explicit and cannot be mistaken for activated parity.

The recorded daily-driver authority subset also migrates keyboard/XKB, mouse,
initial view count and layout, terminal/logout, and named output mode, scale,
position, focus, enablement, and VRR values. Duplicate values fail closed in
the report. Triad's physical output layout is intentionally not converted into
guessed positions while automatic scale is unresolved; it remains an explicit
output-authority row pending capability-backed physical-layout resolution.

Shell, session, broker, and portal work then proceeds against separate
interfaces. Discoveries may revise experimental `sophia_wm_v1`; that is the
reason revision 3 cannot freeze early. When every retained row is complete,
the cross-client reconnect/restart corpus and archived compatibility client are
the final freeze checks, not substitutes for the port.
