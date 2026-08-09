# Desktop Profile Lifecycle Instrumentation

## 1. Trace Event Schema

Every NDJSON record has `tag="trace"` and an `event` object. The event carries
`name`, an optional `digest` or `authority`, and a post-state snapshot containing
`active`, `candidate`, `preparedCount`, `phase`, `generation`, `rejectedCount`,
and `activatedCount`. Digests are bounded SHA-256 identifiers; fragments and
configuration values are never recorded.

## 2. Action-to-Code Mapping

### BeginProfile

- Code: `src/runtime/reducer.nim:80`
- Trigger: after the candidate digest is retained and before dispatching effects
- Event: `BeginProfile`
- Fields: digest and complete post-state envelope

### PrepareAuthority

- Code: `src/config/coordinator.nim:88`
- Trigger: after one owner-only authority fragment is staged and acknowledged
- Event: `PrepareAuthority`
- Fields: authority and complete post-state envelope

### RejectProfile

- Code: `src/runtime/reducer.nim:93`
- Trigger: after candidate discard, before returning last-known-good state
- Event: `RejectProfile`
- Fields: digest and complete post-state envelope

### ActivateProfile

- Code: `src/runtime/reducer.nim:131`
- Trigger: after exact digest comparison and full prepare acknowledgement
- Event: `ActivateProfile`
- Fields: digest and complete post-state envelope

### IgnoreStaleCompletion

- Code: `src/runtime/reducer.nim:134`
- Trigger: when an effect result does not match the current candidate digest
- Event: `IgnoreStaleCompletion`
- Fields: stale digest and unchanged post-state envelope

## 3. Special Considerations

The first milestone has no watcher and no live activation endpoint. The checked
trace is therefore a startup trace. When Sophia gains the cross-authority
barrier, its trusted coordinator must emit the same action granularity. Raw
Sophia handles, application metadata, and profile values remain excluded.
