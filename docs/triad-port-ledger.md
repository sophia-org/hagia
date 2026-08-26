# Triad Port Completion Ledger

This ledger records what “Triad is ported to Hagia” meant when Sophia froze
revision 3 of `sophia_wm_v1`. The unit of parity is retained behavior,
not source files, process shape, River protocols, or command spelling.

The reviewed source baseline is
`fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9`. A row is complete only when its
retained behavior has an owner, a bounded interface, deterministic tests, and
the required live evidence. Moving behavior to the correct Sophia authority is
part of the port; putting every feature in the Hagia policy process would
violate the architecture.

## Completion Rule

Interface major 1, wire revision 3 is stable. The port gate closed on
2026-08-26 when the last retained row moved from Partial to Complete. Closure
required:

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
implemented” is not an exclusion. Excluded behavior remains visible in this
ledger and in the post-freeze roadmap; it does not silently disappear from the
product. A later Triad change is considered separately and does not move this
recorded baseline.

The frozen 28-row classification is 21 complete, 0 partial, 0 open, and 7
excluded. The freeze profile is the checked-in Hagia daily-driver profile, not
all 137 bindings in Triad's historical default.

## Spatial Policy — Hagia

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Stable logical windows, outputs, tags, views, columns, and reconciliation | Complete | Keep opaque Sophia identities adapter-local and preserve complete-snapshot settlement. |
| Scrolling columns and fixed-point geometry | Complete | The retained scroller covers automatic and fixed Q16.16 proportions, focus centering, column/window movement, zero configured gaps, constraints, overflow saturation, and deterministic integer projection. Width and height actions are bounded; excluded layout families do not reopen it. |
| Tags, workspaces, names, dynamic creation/pruning, occupancy navigation, and output affinity | Complete | Nine fixed views, nonempty multi-tag actions, dynamic creation/pruning, occupied navigation, stable output affinity, and indicator labels are implemented. The freeze profile configures no custom workspace names; names outside the 32-byte indicator contract and commands outside the checked-in profile are excluded. |
| Focus, movement, exchange, grouping, histories, and cross-output behavior | Complete | Every checked-in focus, view, column, consume/expel, output-focus, and cross-output movement target resolves to Hagia's bounded action catalog. Deterministic model tests cover grouping and bounded focus/minimize histories; historical commands absent from the profile are excluded. |
| Floating, fullscreen, maximize, minimize, restore, and client-visible state | Complete | Reducers, frontend settlement, checkpoint persistence, and signed installed evidence cover floating, fullscreen, maximize, minimize, and restore. Snapping and metadata-rule-driven defaults are excluded; reduced dialog defaults remain covered by the complete transient row. |
| Dialogs, transients, popups, and scratchpads | Complete | Reduced parent/role facts drive dialog defaults; standard and named scratchpads cycle and restore through bounded logical relations. Popup rendering remains outside WM policy. |
| Additional native layouts, frames, tabs, BSP/split trees, grid, and layout switching | Complete | The retained five-layout compiled native cycle has per-view state, deterministic projections, checkpoint persistence, an opaque action, Tier-0 visible status, and installed restart evidence. Frames, tabs, and additional BSP/split layouts are excluded from this freeze because the daily-driver profile does not select them and their chrome belongs to a later shell tranche. |
| Declarative policy configuration | Complete | Provenance-bearing startup candidates reconcile configured views and native layouts on a clone, validate the full logical model, and preserve last-known-good state on failure. Watched reload remains deferred to the cross-authority protocol. |
| Janet commands and layouts | Excluded | Embedded policy execution is not selected by the daily-driver profile and adds a separate determinism, memory, and fallback boundary without exercising a missing WM correspondence. Keep it on the post-freeze Hagia roadmap. |
| Placement, sticky behavior, swallowing, size policy, and window rules | Complete | Trusted registered-launch provenance emits one opaque class for the first observed surface. Hagia maps retained classes 1..9 to view slots without switching the active view; retry/reconnect preserves the grant until the manage projection commits. Hagia never receives title, app ID, PID, path, namespace identity, or regex input. Sticky behavior, swallowing, and metadata-matched rule parity are excluded from this freeze. |
| Completed and continuous pointer policy interactions | Complete | The retained pointer surface is move and resize. Engine capture crosses as ordered Begin/Update/End values with latest queued Update replacement; topology, VT, seat, and policy-restart revocation clear capture and prioritize Cancel, which Hagia applies as a spatial no-op. Drag and scroll policy producers are excluded because the daily-driver profile registers only move and resize pointer actions; their wire enum values remain reserved. |
| Checkpoint, crash, reconnect, and last-layout preservation | Complete | Checkpoint restart passed physically. The independent Nim client now completes the shared eleven-scene corpus both on one retained connection and across two supervised processes with fresh epochs while Sophia pins the last committed projection. Configuration recovery and full retained-state parity remain covered by Hagia's checkpoint/session suites. |

## Visible Desktop — Hagia Shell

These behaviors cannot be moved into `sophia_wm_v1`. They require a separate,
least-authority shell endpoint and target-resolved input.

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Overview and workspace previews | Excluded | Overview navigation, previews, hot corners, overflow hints, and hold/cycle behavior require a broader shell display-list and input vocabulary than the freeze profile needs. They remain post-freeze shell work. |
| Window switcher | Complete | The retained product is the bounded generic `Super+P` switcher, not an MRU or app-ID-filtered switcher. The protected shell supplies deterministic order and selection; Engine renders per head and activates only an exact presented opaque target; broker dispatch, withdrawal, cancellation, pointer-grab arbitration, shell restart, and fresh-epoch reconnect are proven by signed archive `0006`. Recency, app-ID filtering, debounce, previews, and icons are excluded from this freeze because no redacted focus-history or texture contract exists. |
| Frame tabs, tab bars, BSP preselection, and drop previews | Excluded | These correspond to layout families excluded above and require broader shell chrome. Keep them together on the post-freeze shell roadmap. |
| Hotkey overlay, layout toast, notifications, and confirmation dialogs | Excluded | Tier-0 status already provides retained layout feedback. General overlays, notifications, and confirmations require shell or portal authorities unrelated to the WM wire freeze. |
| Panels, status, shell profiles, and shell state streams | Complete | The retained product is Engine's Tier-0 per-head workspace/layout strip with opaque captured actions; signed archive `0005` proves fullscreen coexistence, restart, activation, both outputs, and teardown. Rich persistent panels, shell profiles, health streams, and Tier-1 rendering are excluded. Reservation archive `0007` remains a regression for coherent shell/work-area commits, but the ordinary switcher profile carries no panel claim because one switcher candidate stream is not a persistent panel. |

## Session And Dedicated Sophia Authorities

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Physical key, pointer, axis, gesture, switch, and shortcut matching | Complete | The retained profile uses Engine-owned key matching plus the two move/resize pointer bindings, all resolved to opaque actions after the seven-owner startup barrier without raw input crossing policy IPC. Axis, gesture, and switch bindings are excluded from this freeze; ordinary application wheel delivery remains supported. |
| Input-device and XKB configuration | Complete | Startup activation applies the retained RMLVO, repeat, lock-state, natural-scrolling, acceleration, handedness, middle-emulation, and wheel-scaling candidate through the input authority slot. Per-device overrides and watched activation/rollback are excluded; startup rejection remains fail-closed. |
| Output mode, scale, position, transform, VRR, enablement, power, and reservations | Complete | Signed Sophia physical archive `0001` binds Sophia `870ba46ae231081220b982ecc3a5a95517df7a90` and Hagia `a83c8fa022a4ceff5d8b96a01c46052bbd8ba64a`. It proves atomic multi-head apply, first presentation, frontend publication, a forced rollback after final KMS acceptance but before installation/publication, physical input, and clean teardown. Output power stays a separate post-freeze authority. |
| Launch, startup environment, configured processes, and shell supervision | Complete | The retained product resolves terminal, browser, startup, logout, and switcher selectors only against Sophia's registered applications, activates the typed session payload at startup, and supervises the separately protected Hagia Shell through fresh-epoch reconnect. Arbitrary commands, ambient launch environments, and general process lists are excluded. |
| Lock, logout, session exit, idle inhibition, and shortcut inhibition | Excluded | Clean logout and session exit remain retained through registered operations above. Lock, idle inhibition, and shortcut inhibition require a dedicated security authority and are post-freeze product work; they cannot widen the blind WM boundary. |
| Cursor theme, visibility, inactivity, and find feedback | Excluded | The existing Engine cursor remains the v1 baseline. Theme configuration, inactivity, and find feedback are independent Engine/shell capabilities and do not gate the WM contract. |
| Configuration discovery, validation, activation, reload, and rollback | Complete | Discovery, partitioning, exact fragment admission, seven-owner preparation, startup activation, generation/digest identity, and rollback on timeout, disconnect, rejection, or local failure are retained and tested. Watched reload and durable cross-authority recovery are explicitly excluded from this freeze. |

## Brokers And Portals

| Behavior family | State | Port requirement |
| --- | --- | --- |
| Application classification and launch placement | Complete | One-shot placement classes originate only in Sophia's trusted registered-launch path, cross in the negotiated uncounted `0xFF00` snapshot extension, survive stale/reconnect recovery, and are consumed by one committed surface admission. Metadata-matched placement and a general window-rule broker are excluded. |
| Window lists and shell-facing descriptors | Complete | The protected broker emits sanitized exact-generation descriptors and nonreused action grants. Experimental `sophia_shell_v1` has strict Rust, C, and Nim clients plus signed installed presentation, activation, withdrawal, crash, and reconnect evidence in archive `0006`. Keep all metadata out of WM input and policy hot paths. |
| Screenshots and capture sessions | Excluded | Capture requires its own visible, revocable portal grant and does not exercise a missing WM correspondence. It remains a post-freeze product tranche. |
| Clipboard, drag-and-drop, files, and notifications | Complete | Retain the proven bounded small-text `CLIPBOARD` and `PRIMARY` paths. Large `INCR`, drag-and-drop, files, URI launching, and notifications are excluded from this freeze and remain portal work. |

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

Native output mirroring is implemented and physically proven separately.
Equal-mode scanout cloning remains a post-freeze output-service optimization.

## Freeze Result And Post-Freeze Order

Signed physical archive `0001` closes the frame-fed atomic output row. The
shared reconnect/restart corpus, public xmonad migration, and immutable archived
client also pass, so revision 3 is frozen. Later work is additive and cannot
silently widen the blind policy boundary.

The binding inventory also exposes a public-boundary pressure. Hagia's
compiled profile contains 51 Sophia-owned chords resolved against Hagia's
66-entry action catalog, while Triad's
baseline default configuration contains 132 key bindings and 137 total
physical bindings. Those counts cross multiple authorities, so they do not
mechanically choose a new WM bound. The freeze profile accepts only the
checked-in Hagia bindings. The semantic migrator still classifies all 137
physical bindings and records shortcut-match ownership, target behavior
authority, and an explicit exclusion for every binding outside the product
profile; no accepted command may silently lose behavior.

The recorded daily-driver authority subset also migrates keyboard/XKB, mouse,
initial view count and layout, terminal/logout, and named output mode, scale,
position, focus, enablement, and VRR values. Duplicate values fail closed in
the report. Triad's physical output layout is intentionally not converted into
guessed positions while automatic scale is unresolved. Capability-backed
automatic layout conversion is post-freeze work and does not reopen the
retained named-output profile.

Deferred shell, session, broker, and portal work proceeds against separate
interfaces after the WM freeze and cannot widen the blind policy boundary.
The cross-client reconnect/restart corpus, public xmonad migration, and archived
compatibility client are permanent stable revision-3 evidence alongside the
physical output archive.
