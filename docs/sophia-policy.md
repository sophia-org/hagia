# Sophia Policy Client

Hagia is a standalone project. It carries no Triad history, River or Wayland
dependency, inherited binaries, or Triad build scaffolding. Triad remains a
design reference; any future port must be reviewed as an explicit Hagia change.

The first Hagia boundary is `src/sophia/wm_v1.nim`: an independent Nim
implementation of Sophia's fixed envelope and v1 record layouts. It imports no
generated Sophia binding and no River or Wayland protocol machinery. The
conformance test accepts a Sophia checkout path so both repositories can check
the same retained golden corpus without making either build depend on the
other repository's source tree.

The independent proof client also exercises Sophia's credential-checked socket,
strict complete-snapshot assembly, exact affected-output request, full
projection encoding, and explicit committed outcome. This is a dormant
protocol proof, not a login-session migration. Hagia's private tags, views,
focus history, layouts, and checkpoint state will be added above this module
only after the Sophia protocol reducer and Milestone 12 promotion gate permit
live integration.
