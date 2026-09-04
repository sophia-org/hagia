# Hagia Documentation

Hagia is a standalone Sophia spatial-policy client. These documents describe
the policy model, its authority boundary, and the engineering rules used when
porting useful Triad behavior.

## Architecture

- [Architecture](architecture.md): ownership, module boundaries, reconciliation,
  and projection lifecycle.
- [Sophia policy boundary](sophia-policy.md): independent wire and settlement
  contract.
- [Capability map](capability-map.md): where Triad features belong under
  Sophia's split authorities.
- [Triad port completion ledger](triad-port-ledger.md): retained behavior,
  ownership, evidence, and the completed record that froze `sophia_wm_v1`
  revision 3.
- [Port provenance](provenance.md): reviewed Triad sources and baseline.
- [Roadmap](roadmap.md): implemented and deferred work.
- [Action vocabulary](action-vocabulary.md): how the policy action catalog
  grows, why the frozen wire never blocks it, and the rules every new action
  follows.

## Reference

- [Environment](environment.md): every environment variable Hagia reads, what
  it does, and who sets it, plus the signal surface. `hagia --help` prints the
  common subset.

## Engineering

- [Style guide](style-guide.md): Nim conventions and boundary-code rules.
- [Data-oriented design](data-oriented-design.md): the types layer, canonical
  state, indexes, mutations, and pure projections. Enforced by
  `tools/check_data_oriented_layout.sh` via `nimble layout`.
- [DRY principles](dry-principles.md): semantic ownership, justified
  duplication, and abstraction rules.
