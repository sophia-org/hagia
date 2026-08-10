# Verification Changelog

## Round 1 - Trace Validation

- [fix] Initial startup trace and strong post-state checks added.
- [fix-inv] `TraceMatched`: INIT/NEXT admits semantic stuttering before the
  final event, so completion is conditioned on weak fairness of `TraceNext`.

## Round 1 - Model Checking

- No specification or invariant changes were required.

## Result

Converged in 1 round. Standard model: 778 distinct states. Bug hunting:
no bugs found across two exhaustive configurations. Startup trace: pass.

## Round 2 - Executable Cross-Authority Barrier

- [extension] Replaced the atomic activation abstraction with per-authority
  preparation, activation, failure, and rollback-completion actions matching
  `reduceProfileActivation`.
- [extension] Added authority symmetry and rollback-specific safety checks.
- [trace] Expanded startup evidence to seven prepare and seven activation
  completions with strong post-state cardinality checks.

The extended model converged without a counterexample: 1,360 distinct standard
states, 228 partial-prepare hunt states, 939 stale-completion hunt states, and a
17-state startup trace.

## Round 3 - Generation Identity Fidelity

- [bug] Code/model cross-check found that a rejected `(generation, digest)`
  could be admitted again, allowing delayed completions from the rejected
  attempt to promote it. A public-API reducer reproduction confirmed the
  violation before `latestGeneration` made every attempt monotonic.
- [extension] Model candidate identity as the exact generation/digest pair,
  retain `latestGeneration` across rollback, permit digest reuse only at a
  newer generation, and explore stale completions with independently chosen
  generations and digests.
- [fix-inv] `CandidateIdentityIsFresh` now applies before rollback. The initial
  form incorrectly rejected the required state where a rejected candidate is
  retained while generation-wide rollback acknowledgements remain pending.

The repaired model converged with no remaining counterexample: 2,271 distinct
standard states, 228 partial-prepare states, 1,427 stale-completion states, and
a 17-state generated startup trace. All four finite state spaces were exhausted.
