# Port Provenance

Hagia is a standalone port, not a Git-history fork. This preserves Triad as a
River window manager and lets Hagia review each feature against Sophia's
stricter authority boundary.

The initial policy port uses the local Triad baseline:

```text
fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9
docs: document River-blocked mirroring path
2026-07-22
```

Hagia's engineering guidance reviews `docs/triad-style-guide.md`,
`docs/dod-architecture.md`, `docs/architecture.md`, and `CONTRIBUTING.md` at
that same baseline. `docs/style-guide.md`, `docs/data-oriented-design.md`, and
`docs/dry-principles.md` adapt those rules to Hagia. River/Wayland ownership,
screen-buffer advice, and compositor-specific runtime rules are not copied as
requirements where Hagia has no such authority or measurement evidence.

The foundation milestone deliberately reuses these authority-neutral Triad
parts instead of designing replacements:

- `src/state/entity_manager.nim` supplies the dense indexed storage and
  swap-and-pop deletion algorithm. Hagia adapts it as `EntityStore[Id, T]`,
  keeping IDs in a parallel dense sequence so payloads do not need an embedded
  identity. Semantic order and relationships remain outside the store.
- `src/state/id_gen.nim` supplies the centralized increment-before-issue,
  zero-reserving, terminal-exhaustion ID pattern. Hagia extends its counters to
  views and connection histories.
- `src/config/loading.nim` supplies deterministic, relative, in-place include
  expansion and the depth-10 bound. Hagia retains those semantics but rejects
  optional includes and last-writer-wins overlays, and adds safe-file checks,
  cycle/repeat detection, 64-file and one-MiB bounds, source digests, and value
  provenance.
- `tests/tconfig_loading_reload.nim` supplies the include ordering, nested
  include, missing-file, and recursion test shapes. Hagia ports those cases and
  adds unsafe-mode, duplicate-ownership, digest, and partition-isolation cases.
- `src/systems/update.nim` and `src/types/runtime_effects.nim` provide the typed
  message/effect precedent. Hagia keeps the reducer boundary but splits pure
  policy from lifecycle state and intentionally does not port Triad's
  compositor-wide monolithic message/effect families.

The source-derived storage and ID portions retain Triad's MIT terms in
`THIRD_PARTY_NOTICES.md`.

The earlier policy slice carried forward these design concepts:

- typed logical window, view, output, and tag identities;
- nonzero tag masks and tag-intersection visibility;
- ordered stable entities independent of compositor handles;
- centralized state mutation and pure layout projection; and
- output-loss migration as an explicit state transition.

The scrolling-column slice reviews Triad's `src/layouts/scroller.nim` and
`tests/tlayouts.nim` at the same baseline. Hagia reimplements the behavior with
bounded Q16.16 scales, integer target geometry, and its own tests; it does not
copy Triad's float-based implementation or runtime interpolation.

The native layout-cycle slice reviews Triad's `src/layouts/grid_math.nim`,
`src/janet/bundled_layouts/tile.janet`,
`src/janet/bundled_layouts/grid.janet`,
`src/janet/bundled_layouts/monocle.janet`, and the layout cases in
`tests/tlayouts.nim` at the recorded baseline. Hagia ports the integer geometry
and semantic ordering into native pure projections; it does not embed Janet or
copy Triad's compositor-wide layout dispatcher. Vertical scroller reuses the
same constrained scroller projection through an audited coordinate transpose.

The general tag-action slice reviews Triad's `src/entities/tag_ops.nim`,
`src/systems/workspaces.nim`, and retained default bindings at the same
baseline. Hagia independently adds nonempty multi-tag view and window
membership transitions through opaque actions; it does not import Triad
entities, commands, or compositor bindings.

The dynamic-workspace slice reuses the authority-neutral lifecycle and test
patterns in Triad's `src/systems/workspaces.nim`,
`src/entities/active_workspace_ops.nim`, and
`tests/tcore_output_sticky_scratchpad.nim` at that baseline. Hagia represents
each workspace with its existing stable `TagId` and output-owned `ViewId`,
reimplements occupied navigation and pruning through centralized mutations,
and keeps reusable numeric slots separate from non-recycled logical identity.

The scratchpad and reduced-transient slice reviews Triad's
`src/entities/scratchpad_ops.nim`, `src/systems/scratchpad.nim`,
`tests/tcore_output_sticky_scratchpad.nim`, and
`tests/tcore_parented_geometry.nim` at the recorded baseline. Hagia reuses the
ordered standard/named scratchpad lifecycle, centralized stale-reference
cleanup, restore-membership, and parent-centered constraint test patterns. It
reimplements them with stable logical IDs, a private non-view scratchpad tag,
bounded typed relations, and Sophia's metadata-free surface kind and transient
owner facts. Popup surfaces retain logical identity for cleanup but remain
outside WM policy projection.

The current bootstrap reducer extends that independent model with output
focus, column consume/expel, bounded history, floating geometry, and
fullscreen/maximize/minimize state. The checkpoint and Sophia adapter are new
Hagia code derived from Sophia's public contract, not ports of Triad runtime
state or serialization. The retained profile intentionally has one scroller
and nine fixed views; dynamic workspace and scratchpad actions now have an
unbound reducer lifecycle, while configured workspace names, additional
layouts, shell behavior, metadata rules, and Janet remain reviewed but
incomplete ports.
They are tracked in `docs/triad-port-ledger.md` and block revision-3 stability
unless explicitly excluded with an architectural or product rationale.

The semantic migration command was exercised against the recorded baseline's
`config.default.kdl`, whose blob is unchanged at the recorded revision. Every
physical binding records the shortcut authority that owns matching, the
distinct authority that owns the resulting behavior, its context,
disposition, and a nonempty semantic result; none are unowned. Compact
fixtures retain the exact 137-binding default inventory (132 key and 5
pointer bindings) and the daily-driver input/output/session/workspace subset,
so ordinary Hagia tests do not acquire a Triad checkout dependency.

The command was also exercised read-only against the current daily-driver
profile. It produced 368 explicit report rows, including all 174 physical
bindings, with every row assigned to an authority and result. The generated
Hagia profile passed Hagia's structural `config check` and Sophia's complete
typed candidate check with digest
`82c476d0b3727683fb2c7efe914a74c6792b5eb12fdfb133697b4954cea5ec0d`;
migration wrote only to its explicit temporary output directory and did not
read or overwrite active Hagia configuration.

No River/Wayland adapter, generated protocol module, shell implementation,
metadata rule, or Triad project history is imported. Hagia reuses the shared
`nimkdl` parser dependency and the bounded include algorithm, not Triad's full
configuration model or live-reload runtime. Future source-level ports must
retain the applicable Triad MIT notice and name the source files and baseline
here.

The edge-maximization repair reviews Triad's `src/systems/presentation_policy.nim`,
`src/systems/layout_projection.nim`, `src/systems/window_state.nim`,
`src/entities/column_ops.nim`, and `tests/tcore_presentation_overview.nim` at
`fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9`. Hagia adopts focused-family edge
presentation and its distinction from full column width in scrolling layouts.
Its independent regressions cover navigation, dialog owners, both scroll axes,
F/M transitions, committed scene echoes, rejection, and checkpoint migration.
The snapshot echo handling is Hagia-specific; no River presentation state or
protocol code is imported.

The edge-gap follow-up also adopts Triad's replacement of tiled render
instructions while edge expansion is active, before adding floating windows.
Hagia keeps hidden windows in canonical policy state but omits their placements
and translation membership. Its tests cover dialog visibility, both scrolling
axes, output isolation, and restoration through F/M and navigation. Sophia's
independent translation regression checks that hidden members return without
sweeping across the newly exposed gap.


The uniform-gap model reviews niri baseline
`9e72e4917ca31baf4010496bf7f4aaf78d34d236`, specifically
`resources/default-config.kdl` (gaps and struts) and
`src/layout/scrolling.rs` (`compute_working_area`, `compute_new_view_offset`,
and configuration updates). Hagia independently implements bounded integer
struts, single along-axis camera padding, and transposed vertical geometry.
Its tests use synthetic output sizes and retain the fit rule that leaves an
already-visible column still, including when gaps shrink during a reload.
No niri implementation, runtime, or dependency is copied.


The column and row size vocabulary reviews the same niri baseline,
specifically `niri-config/src/layout.rs` (`PresetSize`, `DefaultPresetSize`,
`Struts`, and the `Layout` defaults) and `src/layout/scrolling.rs`
(`resolve_preset_size`, `resolve_column_width`, and the preset cycle's
comparison of resolved widths), alongside `src/layout/workspace.rs` for the
absence of a global default window height. Hagia independently implements a
flat extent record carrying a Q16.16 proportion or whole pixels, its own
bounds, its own checkpoint migration from the percentages it replaces, and
the negative struts niri permits. It does not port niri's per-column preset
index, and refuses the empty `default-column-width` niri accepts, because
Hagia's projection cannot learn a width from a committed frame. No niri
implementation, runtime, or dependency is copied.

Overview policy reviews Triad's `docs/triad-overview-navigation.md` and
`src/systems/overview_geometry.nim` at
`fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9`. Hagia independently implements
the per-output vertical strip, active or occupied workspace previews, spatial
navigation and selection without changing ordinary focus until confirmation.
The original zoomed workspace arrangement traces to niri. No compositor,
buffer, animation, shell or physical-input implementation is imported.
