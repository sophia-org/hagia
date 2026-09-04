# Hagia Style Guide

This is Hagia's adaptation of Triad's style guide at the baseline recorded in
[port provenance](provenance.md). Sophia's authority rules override any
compositor-shaped convention from the source project.

## Nim Style

Follow NEP-1 and let `nph` decide formatting:

- indent with two spaces and never tabs;
- use `PascalCase` for types;
- use `camelCase` for values, procedures, and constants;
- make enums pure with `{.pure.}`;
- prefer a noun for a read accessor, such as `model.window(id)`;
- use an explicit domain verb for a reducer transition, such as
  `model.restoreOutput(...)`; and
- use a property setter only for a direct value assignment, not for a
  multi-index state transition.

Run `nph` on every touched Nim-family file. `nimble verify` checks formatting
without rewriting files.

## Data And Code Are Separate Modules

Data stays passive and logic stays in procedures, and the two do not share a
module. Every record, enum, distinct ID, mask, wire layout, and bound belongs
in `src/types`; the procedures that read and change it belong in the domain
module that owns the behavior.

This is not a filing preference. A record declared beside its consumer makes
that consumer a mandatory dependency of everyone who only wanted the record,
and the coupling is invisible until you try to remove it. Hagia had four Sophia
modules importing a KDL profile loader, and four more importing a wire codec,
purely to reach data.

When you add a type, ask where the data goes first, then write the procedure.
Do not import data through a logic module that re-exports it; name the types
module directly. `docs/data-oriented-design.md` lists the layer, the three
admitted exceptions, and the gate that enforces them. Run `nimble layout` to
check a change before you commit it.

## Dot Syntax

Put the primary state or value first and call procedures with UFCS:

```nim
let window = model.window(windowId)
model.focusRelative(outputId, 1)
```

Dot syntax is a reading convention, not object-oriented ownership. It must not
hide mutation, I/O, capability checks, or a Sophia round trip.

## One Lookup Per Decision

Do not probe an entity table and then repeat the same lookup for the decision.
That is two hash lookups to answer one question:

```nim
# BAD: probes the table, then hits it again to read the same row.
if windowId in model.windows:
  let window = model.windows[windowId]

# GOOD: one lookup, one Option, one decision.
let windowOpt = model.window(windowId)
if windowOpt.isSome():
  let window = windowOpt.get()
```

Use the typed `Option` accessor once and retain the result. Mutation procedures
may validate an ID before taking a `var` table reference, but the validation
and mutation must stay inside the state layer rather than being repeated by
callers.

Projection and reconciliation loops should build bounded local maps or retain
records already found. Do not trade an obvious bounded pass for a clever cache
without measurement.

## Boundary Code

Protocol code should be plain enough to audit from offsets to semantic records.
Validate counts, reserved fields, generations, and identities before exposing a
complete value. Do not hide wire operations behind generic reflection or
macros that make the fixed layout difficult to compare with Sophia's corpus.

Keep ownership visible in names and comments. Hagia never acquires rendering,
physical-input, application-metadata, process-launch, or session authority.

## Errors, Comments, And Tests

- Fail closed at malformed or unauthorized boundaries.
- Keep the last committed model intact when a candidate fails.
- Comment ownership, invariants, and surprising bounds; do not narrate syntax.
- Add a focused deterministic test for reducer, projection, reconciliation, or
  wire behavior.
- Name unfinished behavior directly in documentation.

