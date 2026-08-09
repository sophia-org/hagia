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

## Data And Dot Syntax

Data stays passive and logic stays in procedures. Put the primary state or
value first and call procedures with UFCS:

```nim
let window = model.window(windowId)
model.focusRelative(outputId, 1)
```

Dot syntax is a reading convention, not object-oriented ownership. It must not
hide mutation, I/O, capability checks, or a Sophia round trip.

## One Lookup Per Decision

Do not probe an entity table and then repeat the same lookup for the decision.
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

