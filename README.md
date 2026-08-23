# Hagia

Hagia is a standalone spatial-policy project for the Sophia display server.
It is the planned Sophia-native port of Triad's useful policy and desktop
experience, not a Triad plugin, compatibility branch, or River client. Hagia
imports none of Triad's River/Wayland runtime machinery or project history. It
ports useful policy deliberately from a recorded Triad baseline, reusing
authority-neutral storage, identity, include-expansion, and test patterns with
source-level provenance and license notices.

The first retained slice independently implements Sophia's `sophia_wm_v1`
wire in Nim. Its proof client negotiates a private session socket, strictly
assembles a complete snapshot, reconciles it into stable Hagia entities,
answers the exact affected-output request with a complete private-tag
projection, and requires an explicit committed outcome. It imports no Sophia,
Wayland, River, or Triad runtime library.

Run its cross-repository conformance gate against a Sophia checkout:

```sh
SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble test
```

The gate checks the same valid, malformed, and fixed-record corpus used by
Sophia's generated Rust and C99 codecs, then runs the independently compiled
Hagia client through Sophia's authenticated transport and canonical Engine
reducer.

`nimble verify` additionally checks formatting, bounded Alloy/Z3 entity
invariants, and the generation-aware TLA+ startup/rollback lifecycle. Set
`HAGIA_TLA2TOOLS_JAR` when the TLC jar is not under `~/src/Specula/lib/`.

Hagia now carries the first bounded Triad-policy slice: stable logical IDs, nine
shared tag slots with output-local views, commit-aware complete-snapshot
reconciliation, bounded output reconnect affinity, deterministic fixed-point
scrolling columns, atomic cross-output movement, output focus, column
consume/expel, bounded focus/minimize histories, presentation-state reduction,
nonempty multi-tag view/window mutation, completed reduced pointer move/resize,
and a checked-in native action and chrome profile. The retained bootstrap
profile has one scrolling layout and
nine fixed views. It proves the boundary but does not complete the Triad port,
and Sophia revision 3 remains experimental until the retained behavior in
`docs/triad-port-ledger.md` is implemented across its assigned authorities. The
`hagia` executable is a long-running client of the session-owned
`SOPHIA_WM_SOCKET`; it does not create or own that endpoint. Persistent
recovery uses an optional `HAGIA_POLICY_CHECKPOINT` file with bounded,
owner-only, atomic replacement; restored state is revalidated and reconciled
against a complete snapshot before use. Checkpoint v2 is an explicit,
stable-ID-ordered logical DTO; v1 is rejected and rebuilt from a complete
snapshot. The physical checkpoint/restart and presentation-state workload has
passed. The separate `hagia-shell` executable now drives Sophia's protected,
title-only live switcher when a shell profile enables it. Explicit X-grab
arbitration, compiled-profile enablement, signed installed evidence, and broader
shell work remain open. Broader parity and continuous pointer interaction also
remain open. Sophia owns scene truth, input
authority, validation, atomic
commit, rendering, supervision, and scanout. See
`docs/architecture.md`,
`docs/capability-map.md`, `docs/provenance.md`, and `docs/roadmap.md`.

Contributor rules are indexed in `docs/README.md`. Hagia carries Triad's
reviewed NEP-1/`nph`, data-oriented, single-lookup, and DRY discipline while
adapting it to Sophia's stricter authority and independent-wire boundaries.

Validate or inspect the unified desktop profile without opening a session:

```sh
hagia config check [--config=/absolute/path]
hagia config print-effective [--config=/absolute/path]
hagia config migrate-triad --input=/path/config.kdl --output-dir=/new/directory
```

The profile uses explicit authority sections and bounded owner-safe includes.
Migration never overwrites output files and reports every retained,
transformed, unsupported, or authority-excluded Triad setting.

Sophia carries the opt-in installed hardware procedure in
`tools/hagia_policy_physical_gate.sh`. It is intentionally not part of
`nimble test`: taking DRM/KMS and physical input ownership requires explicit
operator authorization.

## License

Hagia is released under the BSD 3-Clause License. Copyright 2026 Mason Austin
Green. Source-derived Triad portions and their MIT terms are recorded in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
