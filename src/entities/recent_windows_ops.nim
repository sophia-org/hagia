import std/sequtils

import ../types/[core, model]
import ../policy/entity_store

## The global recent-focus order and the switcher's transient state. The order
## records the effective focus -- the active output's focused window -- after
## reconciliation and after each cause settles, never on `setFocus` itself; a
## repeat is idempotent. Reconciliation restores every output's
## remembered focus in Sophia's output order, and closing a window refocuses
## its heir on outputs the operator is not using. It is recorded at once
## (niri with `debounce-ms 0`): Hagia has no clock, and a debounce without one
## could drop a window the operator used for minutes.

proc clearRecentWindows*(model: var PolicyModel) =
  ## The scope outlives one use of the switcher, as niri's previous scope does.
  model.recentWindows = RecentWindowsState(scope: model.recentWindows.scope)

proc touchRecentFocus(model: var PolicyModel, windowId: WindowId) =
  if windowId == nullWindowId or windowId notin model.windows:
    return
  model.recentFocus.keepItIf(it != windowId)
  model.recentFocus.add(windowId)
  if model.recentFocus.len > maxRecentFocus:
    model.recentFocus.delete(0)

proc noteRecentFocus*(model: var PolicyModel) =
  ## Called once a cause has settled, so only the focus it ends on counts.
  if model.activeOutput in model.outputs:
    model.touchRecentFocus(model.outputs[model.activeOutput].focusedWindow)

proc forgetRecentWindow*(model: var PolicyModel, windowId: WindowId) =
  ## A closed window leaves the order. If the switcher offered it, selection
  ## stays on the same window or moves to the one before it, as in niri.
  model.recentFocus.keepItIf(it != windowId)
  if not model.recentWindows.active:
    return
  let index = model.recentWindows.candidates.find(windowId)
  if index < 0:
    return
  model.recentWindows.candidates.delete(index)
  if model.recentWindows.candidates.len == 0:
    model.clearRecentWindows()
    return
  if index < model.recentWindows.selected or
      (index == model.recentWindows.selected and index > 0):
    dec model.recentWindows.selected
  model.recentWindows.selected =
    min(model.recentWindows.selected, model.recentWindows.candidates.high)
