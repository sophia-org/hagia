# Hagia

Hagia is a standalone spatial-policy project for the Sophia display server.
It is the planned Sophia-native port of Triad's useful policy and desktop
experience, not a Triad plugin, compatibility branch, or River client. Hagia
imports none of Triad's runtime machinery or project history.

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

For now, Hagia remains this narrow development client. Porting Triad's tags,
views, scrolling model, layouts, configuration, and shell experience is
deferred until Sophia needs them to prove a stable public boundary. Those
features will remain private Hagia policy; Sophia owns scene truth, input
authority, validation, atomic commit, rendering, and scanout.
