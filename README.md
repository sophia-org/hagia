# Hagia

Hagia is the reference window manager for the
[Sophia display server](https://github.com/sophia-org/sophia-stack): a
standalone spatial-policy client that owns tags, views, layouts, and focus,
and draws nothing. It's also a real window manager, ported deliberately from
[Triad](docs/provenance.md) and driven daily — a reference implementation in
the sense that it's the canonical example to learn from, not in the sense of
being a toy.

Hagia is one corner of a triangle. Sophia owns the server and the protocols.
[Narthex](https://github.com/sophia-org/narthex) is the reference shell — the
switcher and work-area client with a strictly smaller capability. If you're
deciding what to build and where it goes, start with Sophia's
[Building on Sophia](https://github.com/sophia-org/sophia-stack/blob/master/docs/building-on-sophia.md);
if you're building a window manager, this repository is the one to copy from.

## What It Does

Hagia independently implements the `sophia_wm_v1` wire in Nim — no Sophia,
Wayland, River, or Triad library anywhere in the build. It connects to the
session-owned `SOPHIA_WM_SOCKET`, assembles complete snapshots, reconciles
them into stable logical entities, and answers each projection request with a
complete, deterministic layout. Sophia keeps scene truth, input, rendering,
validation, atomic commit, supervision, and scanout; Hagia only ever proposes.

The policy surface: stable logical IDs, nine shared tag slots with
output-local views, deterministic fixed-point scrolling columns, atomic
cross-output movement, bounded focus and minimize histories, output reconnect
affinity, scratchpads, and reduced pointer move/resize. The freeze profile —
one scrolling layout, nine views — is complete, and wire revision 3 is
frozen. The full row-by-row record lives in
[the port ledger](docs/triad-port-ledger.md); signed physical archives back
the claims that need hardware to prove.

Sessions survive restarts. An optional `HAGIA_POLICY_CHECKPOINT` file is
written atomically after every committed cycle, and a restarted Hagia
revalidates it against a complete snapshot before trusting it. `SIGHUP` asks a
running Hagia to hand over to a rebuilt binary; `SIGUSR1` dumps its state;
`HAGIA_POLICY_TRACE` records a session that `hagia replay` can re-run offline,
byte for byte, on any machine.

## Verify It

The conformance gate runs against a Sophia checkout:

```sh
SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble test
```

It checks the same valid, malformed, and fixed-record corpus that Sophia's
generated Rust and C99 codecs parse, then drives the compiled Hagia client
through Sophia's authenticated transport and canonical Engine reducer.
`nimble verify` adds formatting, bounded Alloy/Z3 entity invariants, and the
TLA+ startup/rollback lifecycle. `nimble layout` checks the data-oriented
module discipline alone, in under a second.

The installed hardware procedure lives in Sophia's
`tools/hagia_policy_physical_gate.sh` and is deliberately not part of
`nimble test` — taking DRM/KMS and physical input needs an operator's
explicit say-so.

## Configuration

Inspect or migrate a desktop profile without opening a session:

```sh
hagia config check [--config=/absolute/path]
hagia config print-effective [--config=/absolute/path]
hagia config migrate-triad --input=/path/config.kdl --output-dir=/new/directory
```

`examples/config/default.kdl` is the copyable default and the exact compiled
fallback. Personal profiles stay user-owned; migration never overwrites an
output file, and it reports every setting it retained, transformed, or
excluded — with the reason.

## For Contributors

`docs/README.md` indexes the rules. The short version: NEP-1 with `nph` as
the formatter, data separated from code and gated mechanically, one lookup
per decision, and every boundary failing closed. Hagia carries Triad's
discipline while adapting it to Sophia's stricter authority lines.

## License

BSD 3-Clause. Copyright 2026 Mason Austin Green. Triad-derived portions and
their MIT terms are recorded in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
