# Hagia Roadmap

## Current Position

Hagia independently implements the draft `sophia_wm_v1` wire in Nim and passes
Sophia's shared valid, malformed, and record corpus. Its proof client completes
one authenticated snapshot/request/projection/outcome cycle through Sophia's
canonical reducer.

The first Triad-policy slice is now active. It introduces stable Hagia IDs,
private tags and views, deterministic column projection, complete-snapshot
reconciliation, hidden-surface admission, and output-loss migration. It remains
an offline conformance path while Sophia's installed session uses experimental
WM API v7.

## Milestone 1: Geometry And Reconciliation

- [x] Implement the independent fixed wire and malformed-frame checks.
- [x] Complete one authenticated policy cycle without a Sophia library.
- [x] Add private tag/view state with stable logical identities.
- [x] Reconcile complete Sophia snapshots without leaking opaque IDs into the
  policy model.
- [x] Return complete affected-output column projections with constraints and
  focus.
- [ ] Retain logical state across multiple request/outcome cycles.
- [ ] Model stale, invalid, timed-out, disconnect, and reconnect outcomes.
- [ ] Preserve output reconnect affinity rather than only migrating on removal.

## Milestone 2: Daily-Driver Spatial Policy

- [ ] Port Triad's scrolling-column mathematics as a pure Hagia projection.
- [ ] Add view activation, tag changes, focus movement, and window movement as
  reducer messages driven by opaque registered actions.
- [ ] Add bounded Engine-owned pointer move and resize interactions when the
  public protocol carries them.
- [ ] Add session-local checkpointing with exact snapshot reconciliation.
- [ ] Prove policy crash/restart while applications and the committed scene
  remain alive.

## Milestone 3: Hagia Experience

- [ ] Port additional layouts only after deterministic geometry tests exist.
- [ ] Design a separate Hagia shell against a future Sophia shell interface.
- [ ] Add metadata rules only through a trusted classification broker.
- [ ] Request launch, logout, capture, locking, and configuration through
  opaque session capabilities or dedicated authorities.
