# Current SDK lifecycle assertions

`lifecycle.rs` is an external test-source overlay, not part of Hagia's Nim
build and not shipped inside Sophia. niltempus's `tools/wm_lifecycle.rs`
mounts it beneath the production Session launch/reload tests in an archived,
explicitly pinned Sophia checkout. This grants test access to private owners;
it does not add a Hagia dependency or special case to Sophia.

The fourteen explicitly ignored cases must be listed and invoked individually:

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

- `sdk_disconnect_aborts_pending_settlement` in `abort_settlement.rs`, a child
  of `occupied.rs`: stage real Hagia's fullscreen proposal through the production
  layout owner, with frontend state acknowledgements withheld. A supplied
  30-second initial deadline distinguishes forced abort from natural expiry.
  After the fixture peer exits, AbortSettlement must fence transport and shorten
  that deadline while retaining the old epoch. The exact TimedOut result must
  settle without promoting fullscreen; only then may replacement restore the
  occupied baseline and answer a fresh fullscreen action. Frontend controls stay
  in a local queue; application delivery, ACKs and physical rollback are absent.

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
independent namespace inventory or a new 9P authentication claim. The requested
restart calls the Session owner directly, not the public control socket.

The presentation case bypasses Session admission and visual readiness for its
CPU pixels; display heads, frame completions and router time are supplied.
It is semantic owner qualification, not native retirement, pixels, physical
input or latency. A receipt leaving Session's queue is transport progress, not
proof that the peer consumed or acknowledged that receipt, and Hagia's model
ignores Presented receipts. The revocation case observes that the answer
closes the switcher. Session exposes no refusal-reason record for a staged
projection rejection, so a refused answer's cause, such as a stale presentation
generation, is a source inference; only scene-advanced staleness has
diagnostic accounting.
Revocation by native retirement or source loss, pointer release debt,
other cancellation triggers and native settlement rollback remain open. The disconnect case checks
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
latency, native receipts, or the rest of h006/Sophia t249.
