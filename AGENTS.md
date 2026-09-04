# Hagia Agent Guide

Read `README.md`, `docs/architecture.md`, and `docs/roadmap.md` before changing
Hagia. Use Triad's style and data-oriented discipline for Nim code, but apply
Sophia's authority boundaries to every port.

## Working Rules

1. Keep Hagia standalone. Do not add River, Wayland, Sophia source, or Triad as
   a runtime or build dependency.
2. Hagia is a window manager only. It owns spatial policy: stable logical IDs,
   tags, views, layouts, focus, and the reducers over them. It does not own
   compositor internals, client metadata, rendering, physical input, session
   launching, or portal payloads, and it does not grow into desktop-shell
   surface work such as panels, launchers, trays, or notifications. Port policy
   deliberately against that boundary; when a feature would need one of those,
   it belongs to Sophia or to a separate project.
3. Keep the Sophia adapter thin. It translates complete opaque snapshots into
   Hagia data and translates projections back. Sophia IDs stay adapter-local.
4. Keep data passive and mutation centralized. Types define records; state
   modules own indexed mutation; projection modules remain pure.
5. **Strict style and architecture adherence.** `docs/style-guide.md`,
   `docs/data-oriented-design.md`, and `docs/dry-principles.md` are
   foundational mandates, not suggestions. Use two-space indentation,
   `camelCase` values and procs, `PascalCase` types, pure enums, UFCS, single
   semantic ownership, and bounded centralized mutation. Format every touched
   Nim-family file with `nph`.

   **Separate data from code.** Every record, enum, distinct ID, mask, wire
   layout, and bound belongs in `src/types`; procedures belong in the domain
   module that owns the behavior. A types module is a leaf and imports only the
   standard library and its siblings. Do not reach data through a logic module
   that re-exports it. `tools/check_data_oriented_layout.sh` enforces this and
   fails the build; run `nimble layout` before you commit.

   **Re-read the mandates.** To keep this consistent across a long session, you
   must re-read `docs/style-guide.md` and `docs/data-oriented-design.md` on
   every session initialization and after every context compaction. These rules
   erode silently: the separation in rule 5 was declared once and then lost
   across twenty of twenty-six modules before anyone noticed. Do not rely on a
   summary of them.
6. Run Nim builds and tests serially because they share Nim caches. The
   cross-repository gate is:

   ```sh
   SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble test
   ```

   Use `nimble verify` for the formatting-plus-test contributor gate.

7. Do not run or reload Hagia inside a live Sophia session without explicit
   approval. Offline unit and local socket-conformance tests are safe.
8. Record the Triad source baseline and review each ported domain. Do not copy
   River/Wayland adapters, generated protocol code, mutable home configuration,
   or project history.
9. Leave concise comments for ownership boundaries, invariants, and surprising
   constraints. Do not narrate obvious code.
10. Do not kill or restart `gpg-agent`. If signing is unavailable, preserve the
    staged work and ask the user to unlock it.
