# Hagia Roadmap

## 2026-09-06: select newly admitted windows in the active view

Normal use of Sophia `8b750b30` showed new terminals being admitted while the
previous terminal remained focused. The scroller therefore kept its existing
camera anchor. Reconciliation now passes newly admitted logical IDs to focus
policy after applying scene focus. The newest eligible window in the active
view receives focus, so the existing projection reveals it. Unassigned windows
are placed on the active output, including when it is the second monitor.

Initial snapshot synchronization preserves existing focus. Background views,
other outputs, minimized or non-focusable windows, and popups do not steal
active focus. Explicit request causes run afterward. Focus and camera changes
remain candidates until Sophia commits them; rejected admission retries leave
the previous state intact. The adapter retains only opaque identity mapping,
while the selection rule belongs to `systems/focus.nim`.

Offline regressions cover repeated admissions, camera containment, rejection
and retry, initial and repeated snapshots, exclusion cases, and second-output
placement. The operator subsequently installed Sophia `05ef0eb8` with Hagia
`12f7493` and confirmed that opening new windows in the scrolling layout moves
the camera to them. Logs show three added terminals receiving focus and
committed layout moves, with no runtime fatal at capture time. Evidence is
retained in `/tmp/sophia-panel-camera-confirmed-05ef0eb8`. New-window camera
following is accepted; second-output placement, vertical scrolling and close
behavior remain separate normal-use checks.

## Current Position

The September 5 scrolling audit is implemented against Niri `dd75865f` and
Triad `fb8fb27`: committed camera anchors, incoming-neighbor overflow,
focus-relative admission, close restoration, bounded directional navigation,
and per-column focus memory. Hagia submits optional generic translation groups;
Sophia owns GPU motion. Deterministic camera, reconciliation, checkpoint and
shared-wire regressions accompany the change. Physical acceptance of three
Kitty windows, vertical scrolling, both outputs and moving-content clicks is
still pending. The running session has not been reloaded.

The policy configuration boundary now has one semantic owner. Sophia preserves
ordered Policy records within the session envelope; Hagia checks their setting
names, values, and duplicate identities. Offline `config check` and startup both
construct the policy model, with startup preparation preceding any activation
acknowledgement. Socket and cross-repository regressions cover repeated workspace
records and rejection of malformed policy before graphical admission. This is
parser/activation coverage, not a new physical-session acceptance claim.

Hagia independently implements the draft `sophia_wm_v1` wire in Nim and passes
Sophia's shared valid, malformed, and record corpus. Its proof client completes
the shared eleven-cycle behavior corpus through Sophia's canonical reducer on
one authenticated connection and across two supervised processes with fresh
epochs, retaining private state across two-output
admission, loss, migration, generational return, an ordered action, timeout,
stale/invalid rejection, and recovery after every noncommitted outcome.

The retained freeze-profile policy now includes stable Hagia IDs, a shared nine-slot
tag profile on every output, commit-aware multi-cycle reconciliation, bounded
output affinity, hidden-surface admission, deterministic fixed-point scrolling
columns, and the complete checked-in focus, view, movement, state, layout, and
size action surface. An executable profile gate requires every `policy:` target
to resolve to Hagia's action catalog or the two Engine-owned pointer modes. The
long-running `hagia` client uses Sophia's session-hosted frontend-settled public
transport. The installed physical checkpoint/restart workload has passed.
Signed Sophia physical archive `0005` also promotes Hagia's Tier-0 per-head
indicator and captured-action path. Signed physical archive `0001` closes the
last retained output-authority row, and the completed ledger records interface
major 1, wire revision 3 as stable.

The first shell slice is live and physically proven. Sophia launches the standalone
Narthex in a separate protected domain, sends only bounded sanitized
descriptors and opaque actions, and admits `Super+P` through the session-owned
shortcut path when a shell profile enables it. Engine renders and captures the
exact presented list; the broker checks the issuer before Hagia policy receives
an ordinary focus request. Disconnect revokes interaction and reconnects at a
fresh epoch. Core and admitted XI explicit pointer grabs now join Engine's
application lease arbitration, and the compiled profile enables `Super+P`.
Signed archive `0006` proves presentation, activation, crash, reconnect,
withdrawal, and clean teardown. The freeze profile retains this generic
switcher and its bounded visible work-area claim; MRU policy, filtering,
previews, icons, and persistent panels remain post-freeze shell work. The
copyable tracked default is also the exact compiled fallback, while personal
profiles remain outside project source. Trusted launch placement and shared reconnect/restart
are complete. Physical archive `0001` proves frame-fed apply, first
presentation, frontend publication, forced rollback after final KMS acceptance,
physical input, and clean teardown.

## Milestone 1: Geometry And Reconciliation

- [x] Implement the independent fixed wire and malformed-frame checks.
- [x] Complete one authenticated policy cycle without a Sophia library.
- [x] Complete the sequential revision-2 behavior corpus while retaining the
  private adapter across output loss and generational return.
- [x] Add private tag/view state with stable logical identities.
- [x] Reconcile complete Sophia snapshots without leaking opaque IDs into the
  policy model.
- [x] Return complete affected-output column projections with constraints and
  focus.
- [x] Retain logical state across multiple request/outcome cycles.
- [x] Model stale, invalid, timed-out, disconnect, and reconnect outcomes.
- [x] Preserve output reconnect affinity rather than only migrating on removal.

## Milestone 2: Public Protocol Alignment

- [x] Port Triad's scrolling-column mathematics as a pure Hagia projection.
- [x] Update the independent codec and conformance corpus for Sophia's draft
  the draft revision-2 output, surface-state, cause, configuration,
  interaction, and session-operation records.
- [x] Accept one complete reduced cause per policy request and retain ordered
  non-idempotent action activations without exposing raw input.
- [x] Project private per-output views into the revision-2 indicator descriptor
  and emit exact indicator/status transfer counts without exposing tag masks.
- [x] Resolve terminal, browser, close, and logout actions through advertised
  profile-local session-operation slots; keep their tokens opaque and send an
  optional focused target only when the advertised operation permits it.
- [x] Request one bounded fresh policy cycle after a restored private
  checkpoint reconciles and commits, without sending unsolicited geometry.
  The request advances the private generation, scopes itself to the complete
  live output set, and cannot recur during ordinary action cycles.
- [x] Prove frontend settlement, stale replacement, timeout, and last-committed
  preservation against Sophia's canonical reducer. Hagia's actual socket loop
  discards a timed-out action candidate before the next complete projection;
  Sophia retains separate staged-reducer, frontend-acknowledgement, restart,
  and exact X-property settlement tests.

## Milestone 3: Daily-Driver Spatial Policy

- [x] Add nine-view activation, focus movement, cross-output movement, and
  move-to-view reducer messages driven by opaque registered actions.
- [x] Add nonempty multi-tag view and focused-window mutation without exposing
  raw input or Sophia identities to the private model. Dynamic workspace
  creation, pruning, and occupied navigation now preserve stable identities;
  configured names and the complete migrated command surface remain open.
- [x] Add output focus, column consume/expel, and width/height adjustment for
  the one retained scrolling layout.
- [x] Add reduced dialog/transient defaults and scratchpads. Standard and named
  scratchpad relations use a private non-view tag and bounded restore state;
  dialogs inherit logical output/tag ownership and parent-centered constrained
  geometry, while popup rendering remains outside WM policy.
- [x] Add bounded Engine-owned completed pointer move and resize interactions;
  Hagia receives only the exact target and final output-local geometry.
- [x] Add bounded session-local checkpointing with exact snapshot
  reconciliation. Sophia carries an opt-in two-output physical gate, and the
  retained installed run has passed.
- [x] Prove policy crash/restart while applications and the committed scene
  remain alive. The installed two-output gate retained fullscreen, restored a
  nonempty checkpoint at connection epoch two, completed the post-restart
  action sequence, and shut down with clean session health.

## Milestone 4: Hagia Experience

- [x] Port the retained native scroller, tile, grid, monocle, and vertical
  scroller cycle with per-view logical state, deterministic geometry tests,
  checkpoint persistence, and an opaque `Super+n` action. The installed
  two-output physical gate commits the cycle on both sides of a supervised
  restart and reconciles its nonempty checkpoint at connection epoch two.
  Frames, tabs, BSP, and split trees have since landed as the tree family;
  Janet layouts remain a separate later tranche.
- [x] Add the bounded unified desktop profile foundation, provenance-bearing
  authority candidates, compiled fallback, offline CLI, and semantic Triad
  migration. Trusted Sophia startup now validates and stages all authority
  fragments while Hagia receives only its policy candidate. The executable
  prepare/activate/rollback barrier is modeled and tested. Policy candidates
  reconcile atomically against live/checkpoint logical state and retain the
  last-known-good model on failure. A generation-aware TLA+ gate now exhausts
  partial preparation, activation, rollback, and stale-completion state spaces;
  its implementation-fidelity pass also closed rejected-generation reuse.
  Sophia now carries the matching pure seven-authority reducer over its
  canonical identities plus an exhaustively failure-position-tested
  startup-only driver. One shared pure participant model now defines monotonic
  admission, exact-key retries, prior-active restoration, and fail-closed
  identity matching for every authority. It remains disconnected from
  production handlers. Coordinator-to-participant refinement tests found and
  closed skipped-participant generation reuse with an exact unseen-rollback
  tombstone, then proved convergence and recovery across every authority
  failure position. Startup will use the graphical launch gate for global
  visibility. Sophia now also retains one canonical prepared candidate bundle
  after checking all seven raw candidate identities, removing a duplicate
  shortcut parse and preserving one future handler input. Its startup loader
  now returns that bundle, raw provenance, and exact activation key in one pass
  instead of immediately preparing a validated profile again. A shared Sophia
  loader now admits each staged fragment only for its assigned authority and
  exact key using owner-safe bounded I/O; Hagia's policy loader remains the
  independent implementation. A generic pure authority-local slot now couples
  one participant identity to its bounded active, previous, and prepared
  payloads; typed and admitted-fragment preparation shares this path, semantic
  retries ignore only provenance paths, and every rejected transition leaves
  identity and payload unchanged. The slot is not a coordinator-owned state
  collection and has no production effect handler. Sophia's offline refinement
  executor now runs the full prepare, activate, rollback, and recovery failure
  matrix through seven such slots, proving payload promotion and
  last-known-good restoration as well as identity convergence. An integration
  case now drives the same path from all seven exact owner-safe staged
  fragments through semantic payload promotion. Sophia session preparation now
  also centralizes the canonical candidate and a typed, bounded CLI-superior
  application overlay into one pure cloned-registry operation; rejected
  selectors leave accepted state unchanged. The canonical typed session payload
  is now retained in its real authority-local slot and effective configuration
  reads that prepared payload, but startup assembly cannot activate it. A
  shared constructor now prepares the public shortcut owner's separate slot;
  registration resolution reads only that retained payload. No centralized
  slot collection was introduced. The transient typed bundle is now partitioned
  once into separate session, input, output, and shortcut ownership; current
  input overlays and output reconciliation read those prepared payloads. Live
  public-session preparation now also occurs before display/device setup: one
  linear context stages and re-admits every exact fragment and transfers into
  policy launch with cleanup on early failure. The coordinator now also exposes
  a prepare-only driver that stops at the complete seven-authority `Prepared`
  barrier and performs rollback without any activation call. Public Hagia
  startup now dispatches that barrier through fixed references to the separate
  owners before graphical setup, including generation-wide rollback tests at
  every failure position. An explicit opt-in now activates the six local
  owners, completes Hagia's exact prepare/activate handshake as the final
  barrier, and retains the started supervisor and worker for graphical session
  construction. Bounded missing-client admission, process failure, rejection,
  and disconnect abort before graphics and roll all owners back. The installed
  default and watched reload remain deliberately unchanged.
- [x] Extend the shared `sophia_wm_v1` schema to revision 3 with bounded,
  typed prepare, activate, and rollback records for the external policy
  authority. Hagia validates exact epoch, generation, digest, outcome, and
  reserved fields against the generated Sophia corpus. The capability is
  requested only by the explicit pre-graphics activation path.
- [x] Add independent Sophia- and Hagia-side pure handoff reducers. They prove
  exact epoch/transaction/generation/digest settlement, inert stale replies,
  deterministic retry, explicit rollback after rejection, and candidate-state
  discard. Normal policy sessions still omit the capability.
- [x] Add opt-in typed socket plumbing and isolated Unix-socket tests for the
  startup handoff. Hagia's participant receive path is bounded and rejects
  normal policy traffic before activation. The cross-repository gate now runs
  the real Hagia executable through Sophia's opt-in pre-graphics admission and
  proves all-owner activation and teardown. Restart uses the same activated key
  with a fresh connection epoch. The installed default still omits the option.
- [x] Promote the Tier-0 indicator path with Sophia's signed physical Hagia
  gate. Hagia already emits nine output-local opaque view actions plus layout
  status; Sophia now renders them independently per head, reserves their work
  area, and routes clicks from the last-presented target. Archive `0005` proves
  the strip above fullscreen, the causal restart, pointer activations for views
  2 and 1, nonzero presentation on both outputs, and clean teardown.
- [ ] Add bounded Janet policy and layouts only after failure and deterministic
  fallback semantics are modeled and tested. Janet is explicitly outside the
  WM freeze profile.
- [x] Prove the separate protected Hagia Shell in an installed physical run.
  The source implementation now runs against Sophia's modeled shell lifecycle.
  Start with the bounded title-only switcher proven by
  Sophia's offline descriptor reference; keep ordering and selection here and
  rendering, hit-testing, and presentation in Engine. Defer previews, icons,
  generic textures, and broader shell furniture until that first installed
  reconnect path is exact. The standalone Narthex client implements the
  revision-1 codec and deterministic reducer, validates Sophia's shared golden
  and malformed corpora, and now completes live launch, shortcut admission,
  presentation, exact activation, broker-checked dispatch, withdrawal, and
  fresh-epoch reconnect in a separate protected process. Sophia's core/XI
  explicit pointer-grab arbitration and compiled-profile enablement are now
  complete. Signed archive `0006` supplies the retained physical evidence.
- [x] Add only trusted one-shot launch placement before the freeze. Session
  provenance issues one opaque class for the first surface of a trusted
  registered launch. The capability-gated uncounted snapshot extension survives
  retry/reconnect until commit, and Hagia maps retained classes to view slots
  without changing the active view. General metadata-matched rules, sticky
  behavior, and swallowing remain post-freeze.
- [ ] Request launch, logout, capture, locking, and configuration through
  opaque session capabilities or dedicated authorities. Terminal, browser,
  startup, and logout selectors are now prepared by Sophia against its trusted
  application registry and lowered to opaque operation slots. Typed keyboard
  and pointer startup candidates now activate through Sophia with strict
  libinput failure. Typed output candidates activate through the frame-fed
  authority transaction; signed archive `0001` proves atomic apply and rollback
  on physical hardware. Capture, locking, broader launch environment,
  device-scoped reload/rollback, and remaining dedicated configuration services
  remain.

## Milestone 5: Freeze-Profile Completion And Revision-3 Evaluation

- [x] Close every non-excluded row in `triad-port-ledger.md` across Hagia
  policy, Hagia Shell, Sophia services, and brokers/portals.
- [x] Validate migration of the retained Triad default configuration without
  silent command or behavior loss. Every source binding must have a retained
  or excluded disposition. Typed input, named-output,
  initial-workspace, terminal, logout, and every recorded physical binding now
  have deterministic migration results; deferred layout geometry, commands,
  and feature families remain explicit unsupported/excluded rows. The current
  generated profile passes both Hagia's structural check and Sophia's complete
  typed authority-candidate check with the same digest.
- [x] Pass deterministic parity, authority-loss, restart, and installed
  physical scenarios for the completed desktop.
- [x] Run the shared cross-client reconnect/restart corpus, migrate the xmonad
  recovery profile to the public projection transport, and pin a digest-checked
  revision-3 compatibility client. Physical archive `0001` closes the last
  physical row and makes the archived client permanent.

## Post-Freeze Feature Queue

The Triad-to-Hagia gap analysis (2026-09-04) classified every Triad feature
Hagia lacks. The ledger's exclusions stand; this queue records what could come
next, ordered by the two product lenses — daily-driver muscle memory first,
layout power second — and annotated by cost.

The queue is now being worked toward a stated goal: **every Triad command whose
authority is spatial policy becomes a Hagia action.** The rules for growing the
catalog, and why the wire never blocks it, are in
[the action vocabulary](action-vocabulary.md). Progress is measured by
`hagia config migrate-triad` over Triad's recorded default, pinned in
`tests/tfoundation.nim`: 108 of its bindings now carry over, up from 40 at
revision 3, and the parity test pins that no policy command is excluded for
lack of a capability.

### Tier 1 — muscle memory, model-ready or near

- [x] Named-scratchpad actions. Four bounded slots, with `toggle-named-scratchpad N`
  and `move-to-named-scratchpad N` actions over the model that was already
  implemented and checkpointed. Migration numbers Triad's scratchpad names in
  first-seen order, so the same profile always migrates the same way.
- [x] Workspace naming, as `view-name <slot> "<name>"`. The name rides the
  32-byte indicator label Freeze Decision 1 reserved; the slot stays the wire
  identity, so a name is still not an identity. A rename lands on reload.
- [x] `focus-last`. Walks the bounded per-output focus history back to the most
  recent window that is still a candidate, so a closed or moved window is
  skipped rather than resurrected.
- [x] Spatial focus (`focus-left/right/up/down`). Order-based, not geometric:
  `focus-column-prev/next` step across columns keeping the row where possible,
  and `focus-window-above/below` step inside the focused column. Direct layout
  selection (`layout-scroller` and its four siblings) landed alongside them.

### Tier 2 — muscle memory, new model work

All landed. `entities/column_ops.nim` holds the positional primitives —
`insertColumnAt`, `moveColumnToIndex`, `swapWindowsInColumn`,
`moveWindowToColumnAt` — and `systems/movement.nim` composes them. Positions
are read from `visibleColumns`, the same query focus and projection use, so a
move lands where the user saw the window.

- [x] Window movement within and between columns. Pushed past the last column
  a window opens a column there rather than wrapping, so a repeated press
  expels it instead of cycling it back.
- [x] Column reordering. Columns clamp at the ends rather than wrapping, and
  reordering one output permutes only that output's slots in the shared
  `columnOrder`.
- [x] `zoom`, as `promote-column`: Hagia's master is whichever column sits
  first, so promoting moves a column rather than swapping two fixed roles.
- [x] `swap-to-tag` as nine `swap-with-view` slots, and
  `move-workspace-to-output` as `move-view-to-output-prev/next` — Hagia steps
  through output order rather than screen geometry, so Triad's four compass
  directions collapse onto two neighbours.
- [x] `move-to-tag-left/right` as `move-to-view-prev/next`.
- [x] `expel-window` now opens its column beside the stack the window left,
  rather than appending it to the far end of the scroller, so it agrees with
  the edge behavior of `move-window-column-next`.

### Tier 3 — layout power inside the retained families

- [x] A consume that inverts an expel, as `consume-window-prev`. An expelled
  window opens a column just right of the one it left, so consuming leftward
  undoes it, and a round-trip test pins that.

- [x] Tile master count and ratio, as `master-count` and `master-ratio`
  profile keys with paired increase/decrease actions. Both are global rather
  than per-view; Triad keeps them per tag, which is a refinement worth making
  once something needs it.
- [x] Runtime gap adjustment. `increase-gaps`/`decrease-gaps` step by the
  configured `gap-step`, and `toggle-gaps` hides the configured gaps without
  discarding them. Projections read `effectiveGaps`, so hidden gaps stay
  readable in the profile.
- [x] `maximize-column`, which had been folded onto `toggle-maximized` by the
  migration. It is a decision about a column, so it now has its own action.
- [x] Center-tile, right-tile, vertical-grid, and deck, ported from Triad's
  bundled Janet layouts as native modes. Nine layouts now exist; the shipped
  cycle still lists five, and every mode has a select action whether bound or
  not. `deck` puts the focused window in the master area and gives every other
  window one shared rectangle, which the wire's bottom-to-top placement order
  already expresses.
- [x] Column width presets, as `column-width-presets` plus
  `cycle-column-width` and its reverse. Triad's `set-column-width <value>`
  migrates onto the cycle: an absolute width is an argument, and actions
  carry none, so the widths live in the profile.
- [x] `spiral` and `tgmix`. Both are stateless: a spiral is recursive
  geometry over the window order, and a mixed layout is a rule about which
  layout to run — master and stack below four windows, a grid above. Eleven
  layouts now exist.

### Window groups

- [x] `group-windows`, `ungroup-window`, and `focus-next-in-group`. A group is
  a set of windows one key steps through; it decides nothing about geometry,
  which is what grouping does in Triad outside its frame tree. The membership
  model is also what a tabbed substrate needs to know what a tab holds, so it
  is built before the substrates rather than with them.

### Tier 4 — layout power, large and coupled

- [x] The BSP substrate: `dwindle` and its four directional splits, landed on
  the same persistent tree the tabbed layouts use. A new window splits the
  focused leaf, orientation alternating with depth — the dwindle spiral —
  and `dwindle-preselect-left/right/up/down` aim one insert, spent on use,
  cancelled by repeating the same direction. Triad's `dwindle-split-*` were
  aliases for exactly this BSP preselect, and the migration says so. This was
  the last policy capability Triad had and Hagia did not.
- [x] Native frame-tree/Notion and split-tree/i3 state, projection and descriptor
  bars through Sophia shell revision 2. See [tabbed layouts](tabbed-layouts.md).
  Physical multi-output, input, restart and fullscreen acceptance remains an
  operator gate; deterministic checks are recorded separately.
- [ ] Janet policy and layouts, gated as Milestone 4 records: model
  determinism, fuel, and fallback semantics first.

### Routed elsewhere — recorded so nobody looks for them here

- Overview, MRU switcher previews/filtering, hotkey overlay, toasts,
  confirmation dialogs → Narthex and `sophia_shell_v1` r2.
- Screenshots and capture sessions → the portal tranche.
- Lock, idle inhibition, shortcut inhibition → the dedicated security
  authority.
- Axis, gesture, and switch bindings; per-device input overrides → the input
  authority.
- Watched config reload → still unbuilt, but the reload itself now exists:
  `session:reload-profile` re-reads the profile on request. What is missing is
  the watcher, not the mechanism.
- Metadata window rules, sticky, swallowing → excluded with the metadata
  boundary; a classification-based subset (size policy by broker class) is
  the only compatible shape.

### Config keys queue

- [x] Scratchpad geometry, as `scratchpad-size`. Both places that centred a scratchpad shared one hardcoded fraction; they now share one helper.
- [x] Workspace-name key, landed with the naming above.
- [x] Per-workspace default layout, as `view-layout <slot> "<layout>"`. It seeds a view when the view is born; a runtime switch owns it afterwards.
- [x] Floating placement defaults, as `floating-size`. Zero keeps the current whole-output behavior.
- [ ] Sophia-stack installer wiring for `hagia config init` — sophia-stack's
  installer owns this, so it is out of scope for hagia tranches.
### Blocked on Sophia's session vocabulary

Lock, screenshot, wallpaper, and audio are the desktop capabilities the
README names as queued. Nothing in Hagia blocks them, and neither does the
wire:

- Sophia advertises every session operation with its slot in each snapshot
  (`SnapshotSessionOperation`, record kind 4, max 256 — Hagia uses four).
  `sophia/policy_session.nim` resolves an action's slot to the advertised
  operation and sends `SessionOperationRequest`. Adding an operation needs no
  revision: the slot is profile-local and the token is opaque.
- What is closed is Sophia's own vocabulary: `DesktopSessionShortcut` in
  `crates/sophia-config/src/shortcut_candidate.rs` holds exactly the
  variants whose `profile_name()` strings are Hagia's session whitelist in
  `config/profile.nim`, and `WmActionBehavior` in `.../types.rs` is closed
  the same way. Each capability also needs its behavior implemented, and
  lock's is a security transition rather than a launch — which is why the
  migration classifier already refuses `lock-session` for wanting "a
  dedicated security transition capability".

So the work is sophia-stack's, tracked in its `todo.md` under Native WM and
shell product. Hagia's side per capability is one whitelist string in
`config/profile.nim`, one appended action whose `sessionOperationSlot`
returns the new slot, and a binding — a few lines, once the slot exists.
Record each in the ledger as it becomes real.

## Desktop-profile parity with a Triad configuration

Measured against a real Triad profile in daily use. Everything below is a key
that profile sets and this one cannot yet express, so the list is a statement
of what an operator would have to give up, not a wish list.

Single settings, each a policy key and a projection term:

- `smart-gaps` — suppress gaps for a lone window.
- ~~Separate row-height scales for the vertical scroller.~~ Done:
  `default-row-height` and `row-height-presets` name the along-axis extent in
  vertical mode and inherit the column values when unset, and each scroll
  axis keeps its own camera offset.
- `default-window-width` / `default-window-height` — per-window proportions;
  column width exists, the window inside it does not.
- floating `x-ratio`, `y-ratio`, `min-width`, `min-height` — only the size
  pair exists today.
- spiral `ratio`, `main-pane`, `clockwise` — the layout ships, its tuning
  does not.
- `presentation-mode`, `frame-rate` — Engine-facing, so an output-authority
  key rather than a policy one.
- `mirror-hjkl-arrows` — refused so far for wanting deterministic shortcut
  expansion; the expansion is the work.

Subsystems, each needing an authority decision before any key:

- **Appearance** — border width and colours, frame-tab background, layout
  toast. No appearance authority exists in the profile schema; deciding
  whether policy or Engine owns border colour is the actual question.
- **Animations** — `enable-animations`, `animation-speed`. Engine owns
  pixels, so this is an Engine capability a profile names.
- **Window rules** — needs app-id and title, which the broker deliberately
  withholds from policy. A classification-based subset is the only compatible
  shape.
- **Shells** — active shell, cycle, watchdog, per-shell launch and stop.
  Hagia has `shell { enabled; panel }`; the rest is session-authority work.
- **Overview** and its modal bindings — Hagia has no modal binding concept,
  which is the prerequisite.
- **Recent-windows MRU** — the Alt+Tab family, a bounded focus history with
  its own presentation.
- **Hotkey overlay** — needs bind properties (`hotkey-overlay-title`), and
  the profile grammar rejects properties on `bind` today.
- **Screenshot**, **screen-lock** — portal and security authorities.
- **Janet** — scripted layouts, its own tranche.
- **spawn-at-startup** — `session.startup` is accepted by the schema and has
  no consumer; it must either grow one or stop being accepted.
- **Per-layout binding scopes** — Triad scopes bindings inside `layout "i3"`
  blocks; Hagia chords are global.
