# Hagia Data-Oriented Design

This document ports Triad's data-oriented discipline into Hagia's smaller,
capability-bounded policy role. It is a design contract, not a requirement to
copy Triad's storage implementation.

## Authority Before Storage

Sophia owns scene truth, physical input, frontend protocols, validation,
rendering, presentation, and session services. Hagia owns a private logical
policy model and may return bounded proposals. A convenient data structure
never expands that authority.

Opaque Sophia handles live only in `src/sophia`. Policy records contain Hagia
logical IDs, explicit tag membership, columns, histories, presentation
intent, and deterministic geometry.

## Territories

Hagia keeps four explicit territories:

1. `src/policy/types.nim` defines passive IDs, masks, and records.
2. `src/policy/state.nim` owns ID generation, indexed mutation, and invariants.
3. `src/policy/projection.nim` reads a valid model and computes geometry without
   mutation or I/O.
4. `src/sophia` assembles complete wire values, reconciles opaque identities,
   stages candidates, and lowers committed policy back to Sophia records.

The adapter is not a second policy model. It owns only the mapping necessary to
reconcile current generational handles with stable Hagia IDs.

## Canonical State And Derived Indexes

`PolicyModel` is the canonical private policy state. Each entity kind uses a
dense sequence plus an ID-to-slot index. Swap-and-pop removal updates that
index, while separate ordered ID sequences retain semantic order. A state transition
must update every related index in one procedure and finish in a state accepted
by `model.validate()`.

Callers do not patch tables to implement behavior. They invoke state
transitions. Projection code never repairs invalid state. Checkpoint restore
validates the canonical model and every forward/reverse adapter index before it
can become a reconciliation candidate.

The shared `EntityStore[Id, T]` is storage only. It never owns focus, layout,
membership, or ordering semantics. `validateDense` and `PolicyModel.validate`
jointly check physical indexes and logical relationships after centralized
mutation.

## Identities And Relationships

Logical ID zero is null and is never issued. Physical storage position has no
meaning. Relationships use IDs and bounded tables or masks rather than object
graphs:

- tags are stable `TagId` entities and window/view membership is explicit;
- views select tag masks;
- columns and outputs hold ordered logical IDs;
- focus and minimize history are bounded ID sequences; and
- external surface/output handles remain adapter mappings that include their
  generation.

Compatibility mask helpers exist only at the action boundary; masks are not
canonical identity. An opaque handle reused with a new generation receives a
new logical identity.

## Unidirectional Settlement

State flows in one direction:

1. assemble and validate a complete Sophia snapshot;
2. reconcile it into a clone of the last committed adapter/model;
3. apply exactly one reduced cause to that candidate;
4. compute a pure complete affected-output projection;
5. wait for Sophia's explicit terminal outcome; and
6. promote only on `committed`.

Rejection, timeout, disconnect, malformed input, or restart discards the
candidate. Checkpointing happens after promotion and is never a second commit
authority.

## Memory And Performance

Keep all collections protocol-bounded. Retain only state needed for future
policy decisions. Hagia owns no pixels or screen-sized buffers. Prefer one
lookup, one bounded pass, and immutable local projection data. Add caches only
with an invalidation owner, a bound, and measurement evidence.
