# Hagia Desktop Profile Lifecycle Modeling Brief

## 1. System Overview

Hagia is a Nim spatial-policy client whose new profile coordinator partitions a
single validated KDL profile into seven authority-local candidates. This target
is Category A (message-passing): safety depends on prepare/activate results from
independent authorities plus durable staging, not shared-memory interleavings.
The implementation milestone deliberately permits transactional startup only;
watched reload is excluded until the same barrier is implemented. Core modeled
logic is approximately 180 lines in `src/config/coordinator.nim` and
`src/runtime/reducer.nim`.

## 2. Scenarios

### Scenario 1: Partial authority preparation

**Mechanism**: A candidate may be staged or prepared by only a subset of its
authorities before one authority rejects or the coordinator loses progress.

**Evidence**:
- Code analysis: `src/config/coordinator.nim:77` stages seven distinct fragments.
- Code analysis: `src/runtime/reducer.nim:80` retains a candidate separately from
  the active digest, while rejection clears only the candidate at lines 93-95.

**Affected code paths**: `stageDesktopProfile`, `reduceRuntime` configuration
branches.

**Suggested modeling approach**: Track the candidate digest, prepared authority
set, phase, active digest, and rejected/activated histories. Split per-authority
prepare, rejection, and activation into distinct actions.

**Priority**: High. Partial activation would violate authority isolation and
last-known-good startup.

### Scenario 2: Stale completion after replacement

**Mechanism**: A completion for a rejected or superseded digest must not activate
that digest.

**Evidence**:
- Code analysis: `src/runtime/reducer.nim:134-138` compares effect digest with the
  current candidate before promotion.
- Code analysis: `src/config/coordinator.nim:68-75` embeds one shared generation
  and digest in every authority fragment.

**Affected code paths**: `candidateFragment`, `reduceRuntime(effectCompleted)`.

**Suggested modeling approach**: Parameterize preparation and activation by
digest; allow stale completions nondeterministically and guard activation on the
current digest plus complete preparation.

**Priority**: High. Epoch/digest confusion can promote a rejected profile.

## 3. Modeling Recommendations

### 3.1 Model

- Candidate versus active digest and last-known-good preservation (Scenarios 1-2).
- One prepare transition per authority, since staging and authority acceptance
  are separate failure boundaries.
- Reject/rollback at every partial-preparation point.
- Stale completion attempts for non-current digests.

### 3.2 Do Not Model

- KDL parsing and include byte limits; deterministic tests are a better fit.
- Filesystem byte-level atomic replacement; existing fsync/rename tests cover it.
- Live file watching; the milestone explicitly defers watched reload.
- Sophia rendering, input, or application metadata; those authorities never
  enter Hagia's policy candidate.

## 4. Proposed Extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Authority barrier | `candidate`, `prepared`, `phase` | Represent partial prepare | 1 |
| Candidate history | `rejected`, `activated` | Reject stale promotion | 2 |
| Stable active state | `active`, `generation` | Preserve last-known-good | 1, 2 |

## 5. Proposed Invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety | Every state remains structurally typed | Both |
| `ActiveWasFullyPrepared` | Safety | Every active digest crossed the full barrier | 1 |
| `RejectedNeverActivated` | Safety | Rejected digests never enter activated history | 2 |
| `PartialPreparationNotActive` | Safety | Current partial candidate cannot be active | 1 |
| `LastKnownGoodOnReject` | Safety | Rejection does not change the active digest | 1, 2 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable

| ID | Description | Expected invariant violation | Scenario |
|---|---|---|---|
| MC1 | Can any subset of authority acknowledgements activate a digest? | `ActiveWasFullyPrepared` | 1 |
| MC2 | Can a stale completion activate a rejected digest? | `RejectedNeverActivated` | 2 |

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
