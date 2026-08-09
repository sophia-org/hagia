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
| `ActiveWasFullyPrepared` | `base.tla` | direct | both hunt cfgs |
| `RejectedNeverActivated` | `base.tla` | direct | stale-completion cfg |
| `PartialPreparationNotActive` | `base.tla` | direct | partial-prepare cfg |
| `LastKnownGoodOnReject` | `base.tla` | direct | partial-prepare cfg |

## Model-checkable findings

| Finding | Trigger | Expected invariant | Hunting configuration |
|---|---|---|---|
| MC1 | activation during partial prepare | `ActiveWasFullyPrepared` | partial-prepare |
| MC2 | completion for rejected digest | `RejectedNeverActivated` | stale-completion |
