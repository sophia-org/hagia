# Foundation Verification Models

- `alloy/entities.als` checks logical-ID uniqueness, ownership, nonempty
  membership, dangling references, private scratchpad isolation and restore
  membership, and acyclic parent relations over bounded entity worlds.
- `z3/entities.smt2` asks for representative invariant violations and requires
  each query to be unsatisfiable. The dynamic-workspace query also rejects an
  empty dynamic tag after it is no longer active, a scratchpad tag selected by
  a view, missing restore membership, and a self-parent relation.
- `.specula-output/spec/base.tla` checks the cross-authority profile lifecycle.
  A candidate cannot promote until every authority prepared and activated the
  shared generation/digest; every attempt advances monotonically, while
  preparation failure, partial activation, rollback, and stale completion
  preserve the last-known-good profile. `MC.cfg` and the two hunt configurations
  provide the executable TLC entry points.

The richer Specula model-checking and trace-validation artifacts live under
`.specula-output/`. They include bounded partial-prepare and stale-completion
hunt configurations plus the startup NDJSON trace. `TraceData.tla` is generated
from that trace, and the gate rejects any source/generated drift.

Run the bounded entity gate with pinned Alloy 6.2.0 and Z3 4.16.0:

```sh
tools/check_foundation_models.sh
```

Run the lifecycle trace and all exhaustive TLA+ configurations with a local
TLC jar (or set `HAGIA_TLA2TOOLS_JAR` explicitly):

```sh
tools/check_profile_lifecycle_model.sh
```
