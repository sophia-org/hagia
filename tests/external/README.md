# Current SDK lifecycle assertions

`lifecycle.rs` is an external test-source overlay, not part of Hagia's Nim
build and not shipped inside Sophia. niltempus's `tools/wm_lifecycle.rs`
mounts it beneath the production Session launch/reload tests in an archived,
explicitly pinned Sophia checkout. This grants test access to private owners;
it does not add a Hagia dependency or special case to Sophia.

Startup and replacement use Session's authenticated launch owners and Hagia's
ordinary launch-relay authentication. A generic Sophia fixture supplies the
trusted Session-to-Factotum channel; the Factotum conversation, launch
registration, protected child and WM authentication are exercised. The fixture
drives the authentication coordinator while waiting for asynchronous replacement
and records the active registration with each observation. It does not launch
the installed Factotum agent or qualify its bootstrap channel.

The twenty-three explicitly ignored cases must be listed and invoked individually:

- `sdk_presented_backend_revocation_precedes_withdrawal` in
  `presentation_service.rs`: after Presented on both mirrors, remove a sampled
  source through authority observation, production projection and a CPU cycle.
  The backend generates the revocation record. The fixture queues the ordinary
  replacement on the mirror target and completes both heads before Session's
  service call. That one call must queue the exact Revoked then Withdrawn, in
  that order. Missing notification consumption or wrong backend publication
  identity cannot be masked by headless fallback: it revokes too late to settle
  withdrawal in that turn. The first correlated Hagia answer closes the switcher,
  drops the departed window and preserves focus. Source removal, CPU content,
  composition scheduling and head completion are supplied; the records and
  frame stamps are production-derived. No native timing or device claim.

- `sdk_presented_service_revokes_before_requested_restart` in
  `presentation_service.rs`: request replacement through Session's actual
  control-restart admission, with an authenticated peer and a backend-derived
  Presented receipt. Before polling replacement, the production service must
  revoke and remove the publication while the old peer is alive and the epoch
  unchanged. Availability stays true; completing both simulated mirror heads
  lets the stopping service settle Withdrawn once. Replacement then authenticates
  a new peer, preserves committed state, returns chord credits and answers its
  two recovery cycles without resurrecting the switcher. The fixture chooses
  retirement before replacement; queued old-epoch receipts are local evidence,
  not an old-peer delivery claim. Controls omit stopping from revocation or
  incorrectly block withdrawal settlement while stopping. Initial installation,
  CPU sources and device completion retain the shared prefix's supplied limits.

- `sdk_presented_service_withdraws_when_unavailable` in
  `presentation_service.rs`: after backend-derived Presented on both mirror
  heads, call the actual `service_presented_policy` owner with supplied
  availability loss. It must issue the exact Revoked and remove the runtime's
  installed publication. The first correlated real-Hagia SceneChanged answer
  closes the switcher without changing focus. Both heads then retire the
  replacement, but the unavailable service must defer Withdrawn; restoring
  availability settles it exactly once. Controls remove availability-based
  revocation, runtime withdrawal, or the availability gate on settlement.
  The inherited prefix still installs against a supplied head and observes
  initial Presented through the abbreviated helper. Availability and device
  submit/flip are supplied. This joins the production service's loss and
  withdrawal branches, not device detection, stopping/authentication logic,
  backend-initiated revocation, native install or repaint scheduling. The
  chord remains open: availability alone does not claim lock cancellation.

- `sdk_lifecycle_startup`: ordinary Hagia, protected supervisor launch, exact
  profile activation, nonempty action catalog and capability ceiling. No
  checkpoint is created before a committed cycle.
- `sdk_lifecycle_profile_rollback`: accept view-count 8, then have real Hagia
  reject view-count 10. The Session reload/restart owners preserve the accepted
  profile, catalog and checkpoint until new committed cycles. Both replacements
  answer their own queued scene and checkpoint refresh request.
- `sdk_lifecycle_restart`: terminate the fixture's supervised child and let
  the automatic owner restart it, then invoke the requested restart owner.
  Each successor has a new peer and epoch, retains the profile/catalog and
  checkpoint, and supplies its own post-restore Dirty continuation.
- `sdk_occupied_settlement` in `occupied.rs`: two supplied mapped surfaces,
  different generational handles, real catalog focus action, then supplied
  timeout and a deliberately advanced stale scene. Refusals must preserve the
  committed placements, focus and checkpoint; a fresh action can then commit.
- `sdk_occupied_restart`: the same occupied scene with changed private column
  sizing. Automatic and requested restart must restore placements, focus and
  occupied checkpoint relationships through the real restore/Dirty exchange.
- `sdk_operation_settlement` in `operations.rs`: a real catalog terminal action
  produces a committed projection and then an SDK operation naming its activation
  serial. Session accepts one typed launch intent, kept local, or refuses a
  supplied timed-out operation. Both outcomes release the peer for another cycle.
- `sdk_operation_refused_action`: a supplied projection timeout owes no operation;
  the next cycle is recovery SceneChanged, and a fresh explicit action still works.
- `sdk_operation_disconnect`: terminate the fixture child with either an action
  projection or its operation unsettled. Automatic restart clears both operation
  obligations and restores the committed occupied state without action replay.
- `sdk_slow_peer_response_deadline` in `slow_peer.rs`: after proving the
  protected peer is this fixture's grandchild, pause only that process with
  SIGSTOP and send one explicit action. Session's unmodified twelve-second
  response deadline, not a process exit, must request the transport restart:
  the protected leader is still running and the recorded restart line names the
  response deadline. Nothing commits while stalled; the replacement has a new
  peer and epoch, owns no stalled request, restores the occupied state through
  its own Dirty exchange and answers a fresh action. Detection and replacement
  times are recorded observations, not a latency qualification. A guard resumes
  the exact paused process if an assertion fails first.
- `sdk_presented_chord_switcher` in `presentation.rs`: Session's native
  presentation ceiling is selected without a device, and the case's own profile
  binds Alt+Tab to recent-window-next; Hagia's configuration declares the
  chord's lifecycle. Three supplied surfaces carry owned CPU buffers committed
  through one ordinary CPU production cycle. Alt+Tab, routed by Session's
  production routing and the real router, opens a chord; Held, at a supplied
  router time, makes real Hagia publish its held switcher. That unmodified
  publication is refused by a runtime without the sources and with no head,
  then passes production preflight. Installed without a completed frame it
  issues no receipt and captures nothing. A supplied completion issues one
  Presented receipt; a captured Right then carries that exact identity, owes
  its release until released, and steps the switcher in Hagia. The republished
  switcher rejects the old identity. Revoked and Withdrawn follow in order, and
  Alt's release commits the third window, expected from the checkpoint and
  Hagia's documented candidate order before the run. Chord credit and capture
  debt are checked at each step.
- `sdk_presented_revocation_closes_switcher` in `presentation_revocation.rs`,
  a child of `presentation.rs` that reuses its prefix through the installed Held
  publication: no Right press and no release debt. A supplied completion issues
  Presented. A supplied completed frame that still shows policy content but
  lacks the publication stamp makes Session revoke: Revoked carries the
  original identity and leaves before the next cycle. The first cycle admitted
  afterwards is captured at admission; no other cycle is admitted until it is
  answered. That exact SceneChanged answer must be a staged proposal with no
  presentation and unchanged W1 focus. A refusal of that request, or a
  proposal that still draws the switcher, fails a named assertion. Only after
  that answer is committed does a supplied replacement frame withdraw the
  revoked identity. Alt's release then returns the chord credit without
  committing a selection, and W1 stays focused.

- `sdk_presented_disconnect_preserves_release_debt` in
  `presentation_disconnect.rs`: terminate only the fixture peer with a captured
  Right action staged but uncommitted, and Right still down. Automatic replacement
  must preserve that release debt while clearing old presentation and chord
  authority, returning credits and preserving committed focus and checkpoint.
  The owed release is swallowed; a duplicate release reaches the no-focus path.
  The replacement restores its occupied state and a fresh routed Alt+Tab chord
  commits W2. No pending layout settlement is created, so AbortSettlement is
  outside this case.

- `sdk_presented_cancel_preserves_focus` in `presentation_cancel.rs`: supply
  the transition out of keyboard matching to Session's existing owner while
  the Held switcher is presented. It must emit one Cancelled for the exact
  chord; a repeated nonmatching turn emits none. The exact terminal cause
  closes Hagia's switcher without selecting W2, before any Revoked/Withdrawn
  receipt can mask cancellation. Credits return; the later Alt release emits
  no second terminal. A fresh distinct chord can still select W2 on Released.
  The matching transition is supplied, not an actual lock or routing-mode
  change in the owner loop.

- `sdk_presented_receipts_require_all_heads` in `presentation_consensus.rs`:
  after the shared Held prefix, the installed switcher publication is
  validated against the two mirror heads of the backend's test-support
  target, and the production backend composes and queues the retained frames
  for them. Only the worker/device submit and per-head page flips are
  simulated; the runtime derives each input projection from the retired frame
  lists, and no stamp, projection or receipt is supplied. A publication
  retired by one head must not be Presented; after both it is Presented once,
  and republishing is not another presentation. Session cancels the chord at
  matching loss; the exact cancel answer closes the switcher with W1 focused,
  and installing that state issues Revoked before any replacement retires. The
  ordinary replacement must retire on both heads before one Withdrawn. CPU
  sources remain supplied, the `service` mirror omits
  `service_presented_policy`'s native-target selection tail, and the inherited
  prefix's first install used one supplied head; there is one output and no
  physical display.

- `sdk_presented_source_repaint_preserves_identity` in
  `presentation_repaint.rs`: the switcher is Presented on both mirror heads as
  in the consensus case. One previewed surface then commits new CPU bytes
  through authority observation, projection and an ordinary CPU cycle, with no
  WM cause. After the backend recomposes the retained switcher and both heads
  retire it, no WM request has started, the Presented identity, installed
  publication and retired stamp are unchanged, and every retired preview of
  that surface on both heads samples the new committed generation while every
  other preview and every instance identity is unchanged. The backend, not
  the WM, resolves those sampled generations. The fixture queues the
  recomposition itself, so production repaint scheduling is not exercised, and
  the target does not rasterize, so no preview pixels are claimed.

- `sdk_disconnect_aborts_pending_settlement` in `abort_settlement.rs`, a child
  of `occupied.rs`: stage real Hagia's fullscreen proposal through the production
  layout owner, with frontend state acknowledgements withheld. A supplied
  30-second initial deadline distinguishes forced abort from natural expiry.
  After the fixture peer exits, AbortSettlement must fence transport and shorten
  that deadline while retaining the old epoch. The exact TimedOut result must
  settle without promoting fullscreen; only then may replacement restore the
  occupied baseline and answer a fresh fullscreen action. Frontend controls stay
  in a local queue; application delivery, ACKs and physical rollback are absent.

- `sdk_occupied_manage_settles_admission` in `manage.rs`, a child of
  `occupied.rs`: a supplied X authority request for a new policy-managed
  top-level enters Session's admission owner. The owner's own selection names
  it; queued and in-flight manage requests coalesce. Real Hagia places and
  focuses it, and production staging moves admission to ControlPending with
  exact AdmitSurface and SetPresentationState controls. Those controls are
  dispatched by the production queue; supplied Delivered answers are correlated
  by it and applied through the owner loop's two acknowledgement arms. A wrong
  transaction and repeated answers are refused. The committed Manage answer
  must end the owner's admission request. Session retains Hagia's returned
  placement, and its committed focus matches the checkpoint. No pixels are
  supplied, so the surface remains
  AwaitingPixels: Managed state, extent reconciliation and launch visibility
  are not claimed. No later relayout is run, since restaging an AwaitingPixels
  surface re-enters admission control.

- `sdk_occupied_manage_admits_cpu_candidate` in `manage_pixels.rs`, a child of
  `occupied.rs`: the same supplied request arrives with the client's first
  frame, a supplied CPU backing snapshot without a Present. Production intake
  quarantines the frame and selects it as the admission candidate. Real Hagia
  places and focuses the surface; Session must reconcile that placement to the
  candidate's extent, and staging must select the exact quarantined frame.
  After the supplied control answers, which follow the same queue and owner
  arms as the previous case, the commit admits the surface. The next authority
  turn releases the frame through the owner loop's projection to an ordinary
  headless CPU production cycle. That commits generation 1 at Session's
  geometry; the scene retains the exact source bytes, and one interior pixel of
  the headless composed frame matches. A second frame must then reach
  production directly, without quarantine, before the case checks that
  admission is Managed and the recovery extent is released. A presented
  candidate would instead wait for native retirement, which is not exercised.

- `sdk_occupied_reused_surface_generation_after_restart` in
  `reused_identity.rs`, a child of `occupied.rs`: after an actual supervised
  restart of the fixture peer, and before recovery, the second occupied surface
  is removed through the owner loop's two calls and its numeric index returns
  with a new generation as supplied surface facts. Real Hagia's two recovery
  cycles commit a checkpoint holding the surviving surface and the replacement
  but not the old identity. With focus on the surviving surface and nothing
  queued, a focus request naming the old identity is refused synchronously by
  Session's exact-identity guard, starting no request; a fresh request for the
  replacement produces the correlated Focus cause and commits its focus. A
  non-admitting poll then confirms a healthy transport, the same epoch and a
  running peer before teardown. Only focus-request authority is joined; other
  surface-keyed authorities, Manage admission, pixels and input are not.

- `sdk_occupied_manage_admits_software_present` shares the CPU admission setup
  in `manage_pixels.rs`, adding a supplied software-Present submission to the
  initial frame. The exact candidate must remain AwaitingRetirement after the
  policy commit. The ordinary headless CPU backend releases and commits that
  frame, generates its copy-retirement record, and the fixture requires the
  exact candidate and extent before calling Session's production retirement
  owner. Only then must the next backing frame reach production without
  quarantine; Managed state and released recovery extent are checked afterwards.
  The retirement record is backend-generated, with zero native frame and timing
  fields. Frontend answers are supplied, and the drain/owner call is driven by
  the fixture. Native service selection, native Present retirement and physical
  display remain separate gaps.

The original three cases use an empty headless scene. The occupied cases
supply mapped authority facts and source-less layers, and directly complete
the proposed layout through the layout commit owner. They bypass visual
readiness: no application, pixels, configure ACK, rendering or native
presentation is proved. Focus assertions compare policy focus, not physical
keyboard routing. The timeout is supplied to the production settlement owner,
not generated by a real resize deadline. The fixture waits separately for
checkpoint replacement; transport Ready alone cannot prove that write ended.
The slow-peer case uses the same supplied facts. It does not exercise
AbortSettlement, ACK-credit exhaustion or the paused peer observing ESTALE: a
stopped process reads nothing, and the restart kills it.
Operation tests use the same supplied occupied facts and completion. Their
returned launch tuple never reaches the operation queue or executor, so no
application launch or exactly-once external effect is claimed. A disconnected
proposal is discarded, not submitted to the successor. These tests observe
owner state and real peer continuations, not every byte the peer might send.
Protection evidence is the supervisor's observation, not an
independent namespace inventory. Authentication uses the supplied trusted
Factotum channel described above. The requested
restart calls the Session owner directly, not the public control socket.

The original presentation case bypasses Session admission and visual readiness for its
CPU pixels; display heads, frame completions and router time are supplied.
It is semantic owner qualification, not native retirement, pixels, physical
input or latency. A receipt leaving Session's queue is transport progress, not
proof that the peer consumed or acknowledged that receipt, and Hagia's model
ignores Presented receipts. The revocation case observes that the answer
closes the switcher. Session exposes no refusal-reason record for a staged
projection rejection, so a refused answer's cause, such as a stale presentation
generation, is a source inference; only scene-advanced staleness has
diagnostic accounting.
Source-loss notification and its same-turn withdrawal ordering are now joined
by `sdk_presented_backend_revocation_precedes_withdrawal`. Availability loss
and requested stopping also call the actual presentation-service owner in
their dedicated cases. Native installation/retirement, pointer release debt,
other cancellation triggers, native settlement rollback and admission through
a presented candidate's native retirement remain open. The CPU admission case
reads retained source bytes and a headless composed pixel; no physical head,
scanout or frontend delivery is involved. The disconnect case checks
keyboard routing with empty input focus, not application delivery.
The copied dispatch arms and routing call mirror pinned production spans,
which the runner hashes by semantic anchors.

Each case records its profile, checkpoint where present, negotiated
capabilities, connection epoch and protection evidence. Normal exit checks
child reaping; the external PID namespace and timeout bound failure cleanup.
The SDK vendor manifest, ordinary binary hash, source identities, overlay hash,
tool versions and test list belong to the external runner's records.

The old `tools/sophia_pairing` suite remains historical and unchanged. This
small current-source suite does not qualify all negotiated capabilities,
latency, physical scanout, or the rest of h006/Sophia t249. The consensus case
derives receipts through the backend's production composition and publication
owners with simulated completion; it does not run the concrete native-target
selection tail of Session's presentation service.

The October 13 coverage reconciliation in Sophia's investigation `5rzn1zue`
maps all 23 capability bits and explicit acceptance phrases to these cases,
retained generic/attended evidence and remaining owner boundaries. It supersedes
the old fourteen-case gap table without changing h006/t249's exit. The next
bounded external join is pointer move/resize/coalescing/cancel through the real
Session owner, with per-offer accounting before any rate/load campaign. Frozen
pairing fixtures may inform its design but must not run against current master.
