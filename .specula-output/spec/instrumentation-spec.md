# Desktop Profile Lifecycle Instrumentation

## 1. Trace Event Schema

Every NDJSON record has `tag="trace"` and an `event` object. The event carries
`name`, an optional `digest` or `authority`, and a post-state snapshot with the
active/candidate identities, phase, generation, and cardinalities for prepared,
locally activated, rollback-pending, rejected, and promoted sets. Profile
values and authority-local payloads are excluded.

## 2. Action-to-Code Mapping

### BeginProfile

- Code: `src/config/coordinator.nim:111-121`
- Trigger: after the candidate identity is retained and prepare effects exist
- Event: `BeginProfile`

### PrepareAuthority / RejectPreparation

- Code: `src/config/coordinator.nim:122-133`
- Trigger: after one typed authority preparation result is reduced
- Events: `PrepareAuthority` or `RejectPreparation`

### RequestActivation

- Code: `src/config/coordinator.nim:134-143`
- Trigger: after the complete prepare set passes the activation barrier
- Event: `RequestActivation`

### ActivateAuthority / RejectActivation

- Code: `src/config/coordinator.nim:144-159`
- Trigger: after one typed authority activation result is reduced
- Events: `ActivateAuthority` or `RejectActivation`

### CompleteRollback

- Code: `src/config/coordinator.nim:160-168`
- Trigger: after one authority acknowledges idempotent rollback
- Event: `CompleteRollback`

### IgnoreStaleCompletion

- Code: `src/config/coordinator.nim:123-124,145-148,161-162`
- Trigger: when a completion identity does not match the current candidate or
  a late activation result arrives during rollback
- Event: `IgnoreStaleCompletion`

## 3. Special Considerations

The checked trace is a deterministic successful startup sequence with seven
prepare and seven activation completions. Unit tests cover rejection and
rollback traces. Raw Sophia handles, application metadata, and configuration
values remain outside the evidence schema.
