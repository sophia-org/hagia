---
id: i93f3gl7
date: 2026-09-20
kind: investigation
status: investigating
tags: [investigation, policy, adapter]
---
# A maximized window loses its maximize when its workspace is hidden

## Question

niltempus maximized Brave on workspace 2, switched to workspace 1 and switched
back. The window was no longer maximized. A column maximized with the other
binding survives the same round trip. Why do the two differ, and which of
them is wrong?

## Evidence

Reported from ordinary use on 2026-09-20, against the installed release. The
two bindings in `~/.config/sophia/desktop.kdl` are not what their names
suggest and the distinction matters:

| binding | action | where the state lives |
| --- | --- | --- |
| `Super+f` | `policy:toggle-maximized` | the window record's `maximized` |
| `Super+m` | `policy:maximize-column` | the column record's `fullWidth` |
| `Super+Shift+f` | `policy:toggle-fullscreen` | the window record's `fullscreen` |

So the report is about window maximize, not fullscreen. Only the window's
state is round-tripped through Sophia: `fullWidth` is a column fact that
nothing outside the policy model ever writes, which is the whole reason the
second binding survives.

This is a source-level reading, not a reproduction under instrumentation. It
explains both halves of what was observed and predicts that `Super+Shift+f`
survives the same round trip; if fullscreen also fails, this reading is wrong
somewhere and the session events log is the next evidence to take.

## Finding and resolution

`src/sophia/policy_adapter.nim` keeps `presentedMaximized`, the maximized bit
it last projected for each window, and consults it when a snapshot arrives:

```nim
let presented = (surface.currentStateBits and 2) != 0
var intentBits = surface.currentStateBits
if presented == adapter.presentedMaximized[window] and
    (surface.currentStateBits and 5) == 0:
  let retained = adapter.model.window(window).get().maximized
  intentBits = (intentBits and not 2'u16) or (if retained: 2'u16 else: 0'u16)
adapter.model.applyPresentation(window, intentBits)
```

The model's own `maximized` is retained only while the compositor's reported
bit is unchanged. A window whose view is not the active one receives no
placement, so the bit Sophia reports for it falls away while the value the
adapter remembers projecting stays true. The two then disagree, the retention
is skipped, and the raw snapshot bits are applied, which clears `maximized`
through `applyPresentation` and `setWindowPresentation`.

The guard cannot tell *the compositor stopped presenting this maximized
because its view is hidden* from *something unmaximized it*, and treats the
first as the second. The boundary at fault is the adapter's, not the model's:
the model held the right value and the adapter overwrote it with an inference
about a window that was not on screen to have an opinion about.

A repair has to distinguish those two causes rather than widen the retention,
because a window that a client really does unmaximize while off-view must
still come back unmaximized. The projection already knows which windows it
placed; a window it did not place has no presented state to compare against
and its model state should simply stand.

## Validation and remaining work

- [ ] Reproduce with the events log, confirming the maximized bit falls away
      on the switch rather than on the return.
- [ ] Confirm `Super+Shift+f` fullscreen survives the same round trip, which
      this reading predicts and which would localize the defect to the
      maximized path.
- [ ] Repair the adapter so an unplaced window keeps its model state, and
      cover it offline: maximize, switch away, switch back, still maximized;
      and a client unmaximizing while off-view still coming back unmaximized.

Open work is tracked as h001 in `todo.md`.

## Connections

- [Architecture](../../architecture.md) states the adapter boundary this
  finding is about: the adapter translates snapshots and projections and owns
  no policy, which is exactly what the retention guard quietly does.
