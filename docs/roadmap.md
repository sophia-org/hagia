# Hagia Roadmap

## Current Position

Hagia independently implements the draft `sophia_wm_v1` wire in Nim and passes
Sophia's shared valid, malformed, and record corpus. Its proof client completes
one authenticated snapshot/request/projection/outcome cycle through Sophia's
canonical reducer.

The first Triad-policy slice now includes stable Hagia IDs, a shared nine-slot
tag profile on every output, commit-aware multi-cycle reconciliation, bounded
output affinity, hidden-surface admission, deterministic fixed-point scrolling
columns, and registered focus, view, movement, and size actions. The
long-running `hagia` client is ready for Sophia's session-hosted endpoint; live
promotion waits on Sophia's frontend-settled public transport path.

## Milestone 1: Geometry And Reconciliation

- [x] Implement the independent fixed wire and malformed-frame checks.
- [x] Complete one authenticated policy cycle without a Sophia library.
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
  the draft revision-1 output, surface-state, cause, configuration,
  interaction, and session-operation records.
- [x] Accept one complete reduced cause per policy request and retain ordered
  non-idempotent action activations without exposing raw input.
- [x] Project private per-output views into the revision-1 indicator descriptor
  and emit exact indicator/status transfer counts without exposing tag masks.
- [x] Resolve terminal, browser, close, and logout actions through advertised
  profile-local session-operation slots; keep their tokens opaque and send an
  optional focused target only when the advertised operation permits it.
- [ ] Request a bounded fresh policy cycle after private state changes without
  sending unsolicited geometry.
- [ ] Prove frontend settlement, stale replacement, timeout, and last-committed
  preservation against Sophia's canonical reducer.

## Milestone 3: Daily-Driver Spatial Policy

- [x] Add nine-view activation, focus movement, cross-output movement, and
  move-to-view reducer messages driven by opaque registered actions.
- [ ] Add general tag mutation and explicit output-focus actions without
  exposing raw input or Sophia identities to the private model.
- [ ] Add output focus and atomic cross-output movement, column grouping,
  consume/expel, width/height adjustment, layout cycling, and reset actions.
- [ ] Add private floating restore geometry, reduced dialog/transient defaults,
  fullscreen, minimize/restore, scratchpads, and bounded focus history.
- [ ] Add bounded Engine-owned pointer move and resize interactions when the
  public protocol carries them.
- [ ] Add session-local checkpointing with exact snapshot reconciliation.
- [ ] Prove policy crash/restart while applications and the committed scene
  remain alive.

## Milestone 4: Hagia Experience

- [ ] Port additional layouts only after deterministic geometry tests exist.
- [ ] Add candidate-validated declarative configuration only after the public
  policy lifecycle is stable; retain a checked-in bounded profile until then.
- [ ] Add bounded Janet policy and layouts only after failure and deterministic
  fallback semantics are modeled and tested.
- [ ] Design a separate Hagia shell against a future Sophia shell interface.
- [ ] Add metadata rules only through a trusted classification broker.
- [ ] Request launch, logout, capture, locking, and configuration through
  opaque session capabilities or dedicated authorities.
