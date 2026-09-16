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

The revision-3 boundary names the presented active output in both snapshot and
proposal, carries the admitted private policy generation on every request, and
maps a committed binding to an optional advertised session-operation slot.
It also reserves a distinct capability and exact generation/digest control
records for transactional desktop-profile prepare, activation, and rollback.
Those controls remain inactive until Sophia's pre-graphical coordinator is
wired; ordinary policy configuration retains its independent generation.
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

## Configured workspace ownership

An optional `policy { workspace 4 output-key=2; }` assignment maps a global
number (1–9) to a stable, nonzero operator key. Sophia publishes the key through
`output_policy_keys`; connector names remain in Session. Profiles without
assignments preserve legacy local slots. `output_actions` carries a bar click's
exact runtime output/generation independently from affected-output coverage.
A click cannot be redirected to the globally active monitor. Keyboard numbered
workspace actions select the current owner and focus it in one proposal.

Checkpoint schema 18 retains output keys and assignments. The stable key can
rebind a new output handle; unplug keeps the preferred owner while existing
fallback migration hosts the views. Legacy schema 4–17 checkpoints are still
readable. Enabling assignments remaps unambiguous local ordinal views and their
window/scratchpad membership together, preserving ViewIds, window IDs, layout,
cameras and focus. Ambiguous memberships or dynamic-slot collisions refuse the
speculative candidate. Established assignments cannot silently change on reload.
An absent cold-start output is dormant, not synthesized. Dynamic assigned
workspaces reserve configured numbers and use remaining numbers up to 9.

DP-1 can own 1–3 and DP-2 4–6 using keys 1 and 2. These are WM profile settings,
not Lom behavior. Set `policy-key` in each Sophia `output.named` entry and keep
Super+number bindings in the same WM profile. Both capabilities are required
before Hagia accepts an assigned profile's startup activation.
