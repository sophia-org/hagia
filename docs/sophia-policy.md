# Sophia Policy Client

Hagia is a standalone project. It carries no Triad history, River or Wayland
dependency, inherited binaries, or Triad build scaffolding. Its eventual port
of Triad's useful policy and desktop experience must be reviewed as explicit
Hagia work against Sophia's authority boundaries.

The first Hagia boundary is `src/sophia/wm_v1.nim`: an independent Nim
implementation of Sophia's fixed envelope and v1 record layouts. It imports no
generated Sophia binding and no River or Wayland protocol machinery. The
conformance test accepts a Sophia checkout path so both repositories can check
the same retained golden corpus without making either build depend on the
other repository's source tree.

The independent proof client also exercises Sophia's credential-checked socket,
strict complete-snapshot assembly, exact affected-output request, full
projection encoding, and explicit committed outcome. The first policy port now
reduces the complete snapshot into stable Hagia IDs, private tags and views,
and a deterministic affected-output projection. This remains a dormant
conformance path, not a login session; the installed Sophia candidate continues
to use its experimental v7 xmonad bridge while the public protocol matures.

Each affected output also emits nine presentation-only indicator slots and one
output status record. Stable private view IDs become opaque indicator IDs;
labels, state flags, and activation tokens cross the wire, while tag masks and
the private layout model do not.
