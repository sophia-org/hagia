# Contributing

Hagia is small by design. Keep changes bounded, explicit, and reviewable under
failure. Explain behavior changes that affect policy, projection, recovery, or
the Sophia boundary.

Read these contracts before changing code:

- [style guide](docs/style-guide.md);
- [data-oriented design](docs/data-oriented-design.md);
- [DRY principles](docs/dry-principles.md); and
- [architecture](docs/architecture.md).

Triad ports must name the reviewed source files and baseline in
[port provenance](docs/provenance.md). Do not copy River/Wayland machinery or
expand Hagia's Sophia authority to preserve a source implementation detail.

## Verification

Format touched Nim files with `nph`, then run:

```sh
SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble verify
```

The gate checks formatting and runs the independent valid, malformed, semantic,
and authenticated transport suites. Live Sophia sessions require separate
operator approval and are never part of the ordinary contributor gate.

Prefer direct commit messages that describe the resulting tree. Keep process
notes and slogans out of commit subjects.

