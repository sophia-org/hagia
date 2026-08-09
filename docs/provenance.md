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

The current critical-path reducer extends that independent model with output
focus, column consume/expel, bounded history, floating geometry, and
fullscreen/maximize/minimize state. The checkpoint and Sophia adapter are new
Hagia code derived from Sophia's public contract, not ports of Triad runtime
state or serialization. The retained profile intentionally has one scroller
and nine fixed views; general tag mutation, scratchpads, and additional layouts
remain separately reviewable future ports.

No River/Wayland adapter, generated protocol module, configuration parser,
shell implementation, metadata rule, or Triad project history is imported.
Future source-level ports must retain the applicable Triad MIT notice and name
the source files and baseline here.
