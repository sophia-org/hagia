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
