# Confirmed Bugs

## HAGIA-PROFILE-1: rejected profile generation reuse

- **Source:** Code Review during TLA+ implementation-fidelity validation
- **Novelty:** NEW; all open/closed `sophia-org/hagia` issues and pull requests
  were searched on 2026-08-10 and no report of this mechanism was found.
- **Status:** REPRODUCED and fixed
- **Severity:** Medium
- **Location:** `src/config/coordinator.nim:112`
- **Description:** Candidate admission compared a new generation only with the
  active generation. Rollback therefore permitted the exact rejected
  `(generation, digest)` to be begun again, and delayed completions from the
  rejected batch could satisfy the replacement attempt and promote it.
- **Trigger scenario:** Begin generation 5, reject its preparation, acknowledge
  all rollbacks, begin generation 5 again, then deliver the first attempt's
  delayed successful prepare and activation completions.
- **Developer intent investigation:** The coordinator comment, tests, modeling
  brief, and architecture all require stale identities to be ignored and the
  previous active profile to survive rejection. No contrary intent was found.
- **Reproduction test:**
  `.specula-output/confirmation/profile_generation_reuse/repro/test_bug1_rejected_generation_reuse.nim`
  at escalation Level 0 through the public reducer API.
- **Reproduction command:**
  `timeout 5m nim c -r --path:src --nimcache:/tmp/hagia-repro-nimcache .specula-output/confirmation/profile_generation_reuse/repro/test_bug1_rejected_generation_reuse.nim`
- **Reproduction result:** PASS. Before the repair it printed
  `BUG: delayed completions promoted rejected generation 5`. After the repair
  it prints `SAFE: rejected generation cannot be reused`.
- **Recommendation:** Retain a monotonic last-attempted generation across
  rollback, require every candidate generation to exceed it, and treat counter
  exhaustion as terminal. Implemented as `latestGeneration` with a permanent
  regression test and generation-aware TLA+ invariants.
