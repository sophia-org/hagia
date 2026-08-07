# Hagia

Hagia is a standalone spatial-policy project for the Sophia display server.
It is not a Triad fork, plugin, compatibility layer, or River client. Triad,
niri, and river remain architectural references; Hagia imports none of their
runtime machinery or project history.

The first retained slice independently implements Sophia's `sophia_wm_v1`
wire in Nim. Its proof client negotiates a private session socket, strictly
assembles a complete snapshot, answers the exact affected-output request with
a complete projection, and requires an explicit committed outcome. It links
only Nim's standard library.

Run its cross-repository conformance gate against a Sophia checkout:

```sh
SOPHIA_STACK_ROOT=~/dev/sophia-stack nimble test
```

The gate checks the same valid, malformed, and fixed-record corpus used by
Sophia's generated Rust and C99 codecs, then runs the independently compiled
Hagia client through Sophia's authenticated transport and canonical Engine
reducer.

Hagia's tags, views, focus history, scrolling model, layouts, and checkpoint
state will remain private policy. Sophia owns scene truth, input authority,
validation, atomic commit, rendering, and scanout.
