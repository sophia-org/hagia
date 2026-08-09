# Hagia DRY Principles

DRY means one semantic owner for each fact. It does not mean every similar line
must share an abstraction.

## One Owner Per Fact

- `PolicyModel` owns private logical policy.
- Sophia snapshots own current external scene facts.
- The adapter owns generational-handle-to-logical-ID mappings.
- The action profile owns action/chord/operation-slot associations.
- The Sophia KDL schema owns the canonical wire layout.
- Retained golden and malformed corpora own cross-language conformance examples.

Derived values are recomputed or updated by the owning transition. Do not add a
second mutable copy merely to make a caller convenient.

## Intentional Independent Wire Duplication

Hagia's Nim `sophia_wm_v1` codec deliberately repeats Sophia's fixed offsets and
record sizes. Importing generated Sophia code would violate the standalone
boundary and remove independent conformance evidence. This duplication is
acceptable only because:

- the shared corpus detects drift;
- Hagia implements the codec independently;
- semantic values are converted at one adapter boundary; and
- protocol changes update schema, generated artifacts, corpus, and independent
  decoder in the same reviewed change.

Do not use this exception to duplicate Sophia runtime policy or authority.

## Useful Reuse

Extract a helper when it centralizes an invariant, a bound, an identity
conversion, or a transition used in more than one place. Keep code local when
the only commonality is syntax. Avoid helper layers that merely rename a call,
generic repositories over a handful of typed tables, and speculative layout or
widget frameworks.

Tests may repeat small fixture construction when it makes the scenario easier
to audit. Production constants, wire sizes, action identities, and permission
mappings must have one Hagia owner and be referenced symbolically elsewhere.

## Change Checklist

Before adding state or an abstraction, answer:

1. Which authority owns this fact?
2. Where is its single canonical representation?
3. Which indexes or projections derive from it?
4. Which procedure updates or invalidates every derivative?
5. Is apparent duplication an independence or verification boundary?
6. Does the abstraction remove an invariant, or only move lines around?

