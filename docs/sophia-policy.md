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

The independent client exercises Sophia's credential-checked socket, strict
complete-snapshot assembly, exact affected-output request, full projection
encoding, and explicit committed outcome. The policy port reduces the complete
snapshot into stable Hagia IDs, private tags, views, and one deterministic
scrolling-column projection. Sophia's native public-policy owner now supervises
this long-running client; the v7 xmonad bridge is retained compatibility
evidence rather than the promotion path.

The revision-2 boundary names the presented active output in both snapshot and
proposal, carries the admitted private policy generation on every request, and
maps a committed binding to an optional advertised session-operation slot.
Hagia never infers operation authority from an action number. It validates the
opaque operation token and its target permission separately, then waits for the
projection commit before requesting the operation.

Each affected output also emits nine presentation-only indicator slots and one
output status record. Stable private view IDs become opaque indicator IDs;
labels, state flags, and activation tokens cross the wire, while tag masks and
the private layout model do not.

Sophia gives the installed client an owner-only `HAGIA_POLICY_CHECKPOINT` path
inside the policy endpoint directory. Hagia writes a bounded, fsynced,
same-directory atomic replacement after a committed projection. On restart it
validates the private indexes and treats the result only as a candidate for
complete-snapshot reconciliation. The format is neither portable configuration
nor part of `sophia_wm_v1`.
