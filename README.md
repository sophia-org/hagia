# Hagia

Hagia is a standalone spatial-policy project for the Sophia display server.
It is the planned Sophia-native port of Triad's useful policy and desktop
experience, not a Triad plugin, compatibility branch, or River client. Hagia
imports none of Triad's River/Wayland runtime machinery or project history. It
ports useful policy deliberately from a recorded Triad baseline.

The first retained slice independently implements Sophia's `sophia_wm_v1`
wire in Nim. Its proof client negotiates a private session socket, strictly
assembles a complete snapshot, reconciles it into stable Hagia entities,
answers the exact affected-output request with a complete private-tag
projection, and requires an explicit committed outcome. It links only Nim's
standard library.

Run its cross-repository conformance gate against a Sophia checkout:

```sh
SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble test
```

The gate checks the same valid, malformed, and fixed-record corpus used by
Sophia's generated Rust and C99 codecs, then runs the independently compiled
Hagia client through Sophia's authenticated transport and canonical Engine
reducer.

Hagia now carries the first bounded Triad-policy port: stable logical IDs, nine
shared tag slots with output-local views, commit-aware complete-snapshot
reconciliation, bounded output reconnect affinity, deterministic fixed-point
scrolling columns, and a checked-in native action and chrome profile. The
`hagia` executable is a long-running client of the session-owned
`SOPHIA_WM_SOCKET`; it does not create or own that endpoint. Persistent
recovery, floating, pointer interaction, and shell work remain explicit later
milestones. Sophia owns scene truth, input authority, validation, atomic
commit, rendering, supervision, and scanout. See
`docs/architecture.md`,
`docs/capability-map.md`, `docs/provenance.md`, and `docs/roadmap.md`.

## License

Hagia is released under the BSD 3-Clause License. Copyright 2026 Mason Austin
Green.
