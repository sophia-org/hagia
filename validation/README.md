# Foundation Verification Models

- `alloy/entities.als` checks logical-ID uniqueness, ownership, nonempty
  membership, and dangling-reference invariants over bounded entity worlds.
- `z3/entities.smt2` asks for three representative invariant violations and
  requires each query to be unsatisfiable.
- `.specula-output/spec/base.tla` checks the cross-authority profile lifecycle.
  A candidate cannot promote until every authority prepared and activated the
  shared digest; preparation failure, partial activation, rollback, and stale
  completion preserve the last-known-good profile. `MC.cfg` and the two hunt
  configurations provide the executable TLC entry points.

The richer Specula model-checking and trace-validation artifacts live under
`.specula-output/`. They include bounded partial-prepare and stale-completion
hunt configurations plus the startup NDJSON trace mapping.
