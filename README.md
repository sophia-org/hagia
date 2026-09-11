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
affinity, scratchpads, window groups, optional focus-follows-mouse, and
reduced pointer move/resize. Fifteen
native layouts ship — the scroller pair, the tile family, grid and vertical
grid, monocle, deck, spiral, mixed, and the tree family (frame-tree, Notion,
i3, dwindle) — with a five-layout cycle across nine views by default, and
wire revision 3 is frozen. The full row-by-row record lives in
[the port ledger](docs/triad-port-ledger.md); signed physical archives back
the claims that need hardware to prove.

The freeze locked the transport, not the vocabulary. Actions travel as opaque
tokens Sophia never interprets, so Hagia keeps adding spatial commands without
touching the wire — the goal being every Triad command whose authority is
spatial policy. [The action vocabulary](docs/action-vocabulary.md) states the
rules; `hagia config migrate-triad` is the scoreboard, and it is settled: 107
of the 137 bindings in Triad's recorded default carry over, up from 40 at the
freeze, and every remaining exclusion names a structural fact of a flat
profile — a chord already spent, a shell-mode scope, a pointer chord crossing
authorities — rather than a missing capability.

The product goal is a complete, niri-class daily driver. What a window
manager can't own — clipboard, screenshots, capture, notifications — arrives
through Sophia's portals and session, triggered from Hagia keybindings as
opaque session-operation slots: Hagia asks for slot N, the session decides
what slot N does, and a portal decision sits behind anything that moves data.
Terminal, browser, close, and logout already work this way; lock, screenshot,
wallpaper, and audio are queued to ride the same pattern. The desktop gets
fuller without Hagia's authority growing.

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

Hagia owns policy-setting names, layouts, value ranges, and identities such as
workspace slots. `config check` builds the policy candidate as runtime does;
Sophia's paired check validates the session envelope and reports policy
validation as delegated. On startup, Hagia builds the policy model before
acknowledging profile activation, so a bad value cannot open Sophia's graphical
gate. Sophia passes only the staged Policy fragment to the running WM.

### Focus follows the pointer

Off by default, the way niri has it: crossing a window on the way to somewhere
else should not take focus with it.

```kdl
policy {
  focus-follows-mouse #true
}
```

Turned on, focus follows the pointer between windows and onto a monitor holding
no window at all — the empty monitor becomes the active one, so the next window
opens there and the shortcut helper and launcher appear there, while each output
goes on remembering which window it had focused.

Hagia never sees pointer motion. Sophia hit-tests the pixels it has actually
presented and reports which output the pointer settled on and, when there is
one, which window; Hagia decides whether that may take focus and refuses a
target that is not focusable, is minimized, or is not on the output named. A
window moving under a stationary pointer — a layout animation, a reload — is not
motion and does not move focus.

The setting is read at startup, so turning it on or off takes effect when the
profile is reloaded and the window manager restarts; the session's windows,
widths, focus, and camera survive that as they always do. Because it asks
Sophia for observations it would otherwise never send, a `#true` profile against
a Sophia too old to send them fails at startup with a message naming the
setting, rather than starting a session that quietly ignores it. Leaving it off
asks for nothing and works against any supported Sophia.

### Application commands

Ordinary launch commands live in the same profile as the bindings that use
them. A command is either named once and referenced, or written inline at the
binding:

```kdl
session {
  application "browser" { exec "brave-origin" "--flag"; }
  application "work" { use-core "advanced"; }
  browser "browser"
}
shortcut {
  profile "desktop"
  bind "Super+b" { launch "browser"; }
  bind "Super+e" { exec "thunar"; }
  bind "Super+q" "session:close-window"
}
```

`exec` takes an executable followed by literal argv. Nothing is split on
whitespace and no shell is interposed, so a word containing spaces or `&` is one
argument and never a second command. The executable is either a bare name found
on `PATH` or an absolute path; a relative path such as `./program` is refused,
because it would resolve against whatever directory the session happened to
start in. Each named application states exactly one `exec` or one `use-core` —
two bodies would have to be merged, and a merge is the thing an operator cannot
see. `use-core` names an advanced definition kept in Sophia's own configuration
and referenced explicitly; advanced options never merge into a profile by
matching names.

A `launch` names an application this profile declares. It never falls back to
Sophia's core registry, so a binding cannot reach a definition the profile does
not state.

Bounds are 32 applications, 32 arguments after the executable, and 4096 bytes
per argument. The 32 applications are a joint registry: the ones written here
and the ones Sophia mints for inline commands share it. Names beginning
`__shortcut_` are reserved for exactly those generated entries, so a profile can
neither declare nor reference one.

Older string bindings (`bind "Super+b" "session:spawn-browser"`) and role
references (`browser "browser"`) keep working unchanged.

Hagia validates this grammar and never executes any of it. Commands belong to
the session and shortcut sections; the Policy fragment the running WM receives
carries no command and no argv, so the window manager cannot learn or launch a
program. Migration preserves a `spawn` of a single executable as an inline
`exec` and refuses a longer command line by name rather than guessing where its
arguments divide.

`examples/config/default.kdl` is the default and the exact compiled fallback;
`hagia config init` seeds it into `~/.config/hagia/config.kdl` once and never
overwrites an existing profile. Personal profiles stay user-owned; migration never overwrites an
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

[Native tabbed layouts](docs/tabbed-layouts.md) add frame-tree, Notion and i3
with persistent policy state and Sophia/Narthex descriptor bars.

The default `Super+?` (`Super+Shift+/`) binding opens the native shell shortcut
helper. Sophia publishes the active key/pointer catalog; Narthex supplies the
UI and Sophia renders it in the shared JetBrains Mono default. Hagia remains
the WM. Optional `label="..."` and `group="..."` properties on `bind` and
`pointer-bind` customize catalog text and grouping. Startup help is configured
privately in `~/.config/narthex/config.kdl`, not in Hagia's policy section.
