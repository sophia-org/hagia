# Hagia Agent Guide

Read `README.md`, `docs/architecture.md`, and `docs/roadmap.md` before changing
Hagia. Use Triad's style and data-oriented discipline for Nim code, but apply
Sophia's authority boundaries to every port.

## Working Rules

1. Keep Hagia standalone. Do not add River, Wayland, Sophia source, or Triad as
   a runtime or build dependency.
2. Port policy deliberately. Stable logical IDs, tags, views, layouts, and
   reducers belong here; compositor ownership, client metadata, rendering,
   physical input, session launching, and portal payloads do not.
3. Keep the Sophia adapter thin. It translates complete opaque snapshots into
   Hagia data and translates projections back. Sophia IDs stay adapter-local.
4. Keep data passive and mutation centralized. Types define records; state
   modules own indexed mutation; projection modules remain pure.
5. Follow NEP-1 and use two-space indentation, `camelCase` values and procs,
   `PascalCase` types, pure enums, and UFCS. Format every touched Nim-family
   file with `nph`.
6. Run Nim builds and tests serially because they share Nim caches. The
   cross-repository gate is:

   ```sh
   SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble test
   ```

7. Do not run or reload Hagia inside a live Sophia session without explicit
   approval. Offline unit and local socket-conformance tests are safe.
8. Record the Triad source baseline and review each ported domain. Do not copy
   River/Wayland adapters, generated protocol code, mutable home configuration,
   or project history.
9. Leave concise comments for ownership boundaries, invariants, and surprising
   constraints. Do not narrate obvious code.
10. Do not kill or restart `gpg-agent`. If signing is unavailable, preserve the
    staged work and ask the user to unlock it.
