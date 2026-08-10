# Hagia Desktop Profile Lifecycle Modeling Brief

## 1. System Overview

Hagia is a Nim spatial-policy client whose new profile coordinator partitions a
single validated KDL profile into seven authority-local candidates. This target
is Category A (message-passing): safety depends on prepare/activate results from
independent authorities plus durable staging, not shared-memory interleavings.
The implementation milestone deliberately permits transactional startup only;
watched reload is excluded until the same barrier is implemented. Core modeled
logic is implemented in `src/config/coordinator.nim`; the policy connection's
independent settlement lifecycle remains in `src/runtime/reducer.nim`.

## 2. Scenarios

### Scenario 1: Partial authority preparation

**Mechanism**: A candidate may be staged, prepared, or locally activated by
only a subset of its authorities before one authority rejects.

**Evidence**:
- Code analysis: `src/config/coordinator.nim:111-121` retains one candidate and
  dispatches prepare to all seven authorities.
- Code analysis: `src/config/coordinator.nim:144-159` records per-authority
  activation but promotes only when the complete set has acknowledged.
- Code analysis: `src/config/coordinator.nim:93-101` dispatches idempotent
  rollback to every authority after either preparation or activation failure.

**Affected code paths**: `stageDesktopProfile`, `reduceProfileActivation`.

**Suggested modeling approach**: Track the exact candidate generation/digest,
the monotonic latest-attempted generation, prepared authority set, phase,
active identity, and rejected/activated histories. Split per-authority prepare,
activation, rejection, and rollback completion into distinct actions.

**Priority**: High. Partial activation would violate authority isolation and
last-known-good startup.

### Scenario 2: Stale completion after replacement

**Mechanism**: A completion for a rejected or superseded generation/digest must
not activate that identity, including when a newer generation reuses a digest.

**Evidence**:
- Code analysis: `src/config/coordinator.nim:123-124,145-148,161-162` ignores
  stale identities and late activation completions during rollback.
- Code analysis: `src/config/coordinator.nim:227-252` embeds one shared generation
  and digest in every staged authority fragment and manifest.

**Affected code paths**: `candidateFragment`, `reduceRuntime(effectCompleted)`.

**Suggested modeling approach**: Parameterize candidate admission and stale
completion by generation and digest; allow stale identities nondeterministically
and guard activation on the exact identity plus complete preparation.

**Priority**: High. Epoch/digest confusion can promote a rejected profile.

## 3. Modeling Recommendations

### 3.1 Model

- Candidate versus active identity and last-known-good preservation (Scenarios 1-2).
- One prepare transition per authority, since staging and authority acceptance
  are separate failure boundaries.
- Reject/rollback at every partial-preparation point.
- Stale completion attempts for non-current generations and digests.

### 3.2 Do Not Model

- KDL parsing and include byte limits; deterministic tests are a better fit.
- Filesystem byte-level atomic replacement; existing fsync/rename tests cover it.
- Live file watching; the milestone explicitly defers watched reload.
- Sophia rendering, input, or application metadata; those authorities never
  enter Hagia's policy candidate.

## 4. Proposed Extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Authority barrier | `candidate`, `prepared`, `locallyActivated`, `phase` | Represent partial prepare and activation | 1 |
| Rollback barrier | `rollbackPending` | Require every authority to discard candidate state | 1 |
| Candidate history | `rejected`, `promoted` | Reject stale promotion | 2 |
| Stable active state | `active`, `activeGeneration` | Preserve last-known-good | 1, 2 |
| Monotonic attempts | `latestGeneration` | Prevent rejected epoch reuse | 2 |

## 5. Proposed Invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety | Every state remains structurally typed | Both |
| `ActiveWasFullyActivated` | Safety | Every active digest crossed both full barriers | 1 |
| `RejectedNeverPromoted` | Safety | Rejected identities never enter promoted history | 2 |
| `PartialCandidateNotActive` | Safety | A partial candidate cannot be globally active | 1 |
| `LastKnownGoodUntilPromotion` | Safety | Candidate work does not change active state | 1, 2 |
| `RollbackCannotPromote` | Safety | Rollback never changes the active digest | 1 |
| `GenerationNeverRecycles` | Safety | Every attempt permanently advances its generation | 2 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable

| ID | Description | Expected invariant violation | Scenario |
|---|---|---|---|
| MC1 | Can any subset of authority acknowledgements promote a digest? | `ActiveWasFullyActivated` | 1 |
| MC2 | Can a stale completion promote a rejected digest? | `RejectedNeverPromoted` | 2 |

### 6.2 Test-Verifiable

| ID | Description | Suggested test approach |
|---|---|---|
| T1 | Include safety, cycles, and aggregate limits | Temporary-file unit tests |
| T2 | Stable partition digest and provenance | Reorder-free deterministic fixtures |

### 6.3 Code-Review-Only

| ID | Description | Suggested action |
|---|---|---|
| CR1 | Sophia must remain the session coordinator | Review authority ownership on integration |

## 7. Reference Pointers

- `src/config/profile.nim`
- `src/config/coordinator.nim`
- `src/runtime/reducer.nim`
- `docs/architecture.md`
