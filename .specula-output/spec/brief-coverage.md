# Brief Coverage

## Scenarios

| Scenario | Hunting configuration |
|---|---|
| Partial authority preparation | `MC_hunt_partial_prepare.cfg` |
| Stale completion after replacement | `MC_hunt_stale_completion.cfg` |

## Safety invariants

| Invariant | Defined | Wired | Enabled |
|---|---|---|---|
| `TypeOK` | `base.tla` | `MCTypeOK` | both hunt cfgs |
| `ActiveWasFullyActivated` | `base.tla` | direct | both hunt cfgs |
| `RejectedNeverPromoted` | `base.tla` | direct | stale-completion cfg |
| `PartialCandidateNotActive` | `base.tla` | direct | partial-prepare cfg |
| `LastKnownGoodUntilPromotion` | `base.tla` | direct | partial-prepare cfg |
| `RollbackCannotPromote` | `base.tla` | direct | partial-prepare cfg |

## Model-checkable findings

| Finding | Trigger | Expected invariant | Hunting configuration |
|---|---|---|---|
| MC1 | promotion during partial prepare or activation | `ActiveWasFullyActivated` | partial-prepare |
| MC2 | completion for rejected digest | `RejectedNeverPromoted` | stale-completion |
