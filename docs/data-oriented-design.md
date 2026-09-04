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

Data is passive. Logic is active. They do not share a module. This is the
foundational rule of this document, and every other rule here depends on it.

Hagia keeps five explicit territories:

1. `src/types` defines passive data and nothing else. Every record, enum,
   distinct ID, mask, wire layout, and bound lives here.
2. `src/policy` owns ID generation, indexed mutation, invariants, the reducer
   transition, and pure geometry projection.
3. `src/config` owns profile parsing, digesting, activation, and migration.
4. `src/runtime` owns the connection lifecycle transition and effect execution.
5. `src/sophia` assembles complete wire values, reconciles opaque identities,
   stages candidates, and lowers committed policy back to Sophia records.

The adapter is not a second policy model. It owns only the mapping necessary to
reconcile current generational handles with stable Hagia IDs.

## The Types Layer

A module under `src/types` declares data. No logic lives there.

The one admitted exception is the interop Nim requires to use a distinct type
at all: `==`, `$`, and `hash` in `types/core.nim`. Nothing else. A helper that
computes, decides, validates, or transforms is logic and belongs with the
procedures that own the behavior.

A types module is a leaf. It may import the standard library and its siblings
under `src/types`. It may not import a logic module, so data can never depend on
behavior. When a logic module needs a record, it imports the types module by
name; it does not reach the record through some other logic module that happens
to re-export it. Re-exporting data from a logic module recreates exactly the
coupling this layer removes — it is how a codec ends up as a mandatory
dependency of every module that only wanted a record.

The modules are:

| Module | Owns |
| --- | --- |
| `types/core.nim` | logical IDs, tag masks, scale, geometry primitives, dense `EntityStore`, ID counters |
| `types/model.nim` | window, column, view, tag, output, scratchpad records and `PolicyModel` |
| `types/actions.nim` | the `PolicyAction` vocabulary and its stable ordinals |
| `types/policy_messages.nim` | policy reducer messages, intents, and updates |
| `types/projection.nim` | logical placements and per-output projections |
| `types/runtime.nim` | runtime phase, model, messages, and effects |
| `types/config_values.nim` | profile authorities, values, generations, and the activation vocabulary |
| `types/migration.nim` | migration items and reports |
| `types/session.nim` | snapshot, cause, request, projection, and outcome records |
| `types/handoff.nim` | startup profile handoff phase, model, and disposition |
| `types/wm_v1.nim` | `sophia_wm_v1` message kinds, records, offsets, and bounds |
| `types/shell_v1.nim` | shell descriptor records, bounds, and reducer model |
| `types/observability.nim` | evidence records and rotation bounds |

Three kinds of declaration stay outside this layer, each for a stated reason:

- an error type and the enum that classifies it belong to the module that
  raises them;
- a closure vtable such as `RuntimeEffectExecutor` is injected behavior, not
  passive data; and
- an encapsulated state machine whose fields are private on purpose, such as
  `PolicyAdapter` and `PolicySession`, stays private. Exporting its fields to
  satisfy a file-location rule would trade a real authority boundary for a
  cosmetic one.

These are the only exceptions, and each is named in the enforcing gate.

## Enforcement

`tools/check_data_oriented_layout.sh` fails the build when a routine appears in
`src/types`, when a types module imports a logic module, or when a public record
is declared outside the layer. It runs in `nimble test` and `nimble verify`, and
`nimble layout` runs it alone.

The gate exists because this separation was declared once and then eroded until
twenty of twenty-six modules mixed records with the procedures that consumed
them. A rule with no gate decays. Adding a name to the gate's allowlist must be
a deliberate act with a reason recorded beside it, never a way to make the check
quiet.

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
