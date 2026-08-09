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
screen-buffer advice, and Triad's concrete dense entity manager are not copied
as requirements where Hagia has no such authority or measurement evidence.

The first slice carries forward design concepts rather than source files:

- typed logical window, view, output, and tag identities;
- nonzero tag masks and tag-intersection visibility;
- ordered stable entities independent of compositor handles;
- centralized state mutation and pure layout projection; and
- output-loss migration as an explicit state transition.

The scrolling-column slice reviews Triad's `src/layouts/scroller.nim` and
`tests/tlayouts.nim` at the same baseline. Hagia reimplements the behavior with
bounded Q16.16 scales, integer target geometry, and its own tests; it does not
copy Triad's float-based implementation or runtime interpolation.

The general tag-action slice reviews Triad's `src/entities/tag_ops.nim`,
`src/systems/workspaces.nim`, and retained default bindings at the same
baseline. Hagia independently adds nonempty multi-tag view and window
membership transitions through opaque actions; it does not import Triad
entities, commands, or compositor bindings.

The current bootstrap reducer extends that independent model with output
focus, column consume/expel, bounded history, floating geometry, and
fullscreen/maximize/minimize state. The checkpoint and Sophia adapter are new
Hagia code derived from Sophia's public contract, not ports of Triad runtime
state or serialization. The retained profile intentionally has one scroller
and nine fixed views; dynamic workspaces, scratchpads, additional layouts,
configuration, and Janet remain reviewed but incomplete ports. They are tracked
in `docs/triad-port-ledger.md` and block revision-1 stability unless explicitly
excluded with an architectural or product rationale.

No River/Wayland adapter, generated protocol module, configuration parser,
shell implementation, metadata rule, or Triad project history is imported.
Future source-level ports must retain the applicable Triad MIT notice and name
the source files and baseline here.
