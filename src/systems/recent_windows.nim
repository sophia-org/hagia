import std/options

import ../types/[core, model]
import ../state/[queries, values]
import ../entities/[overview_ops, recent_windows_ops]
import ./overview

## The recent-windows switcher, after niri's (and Triad's port of it). The
## first action opens it already pointing at the previous window; each further
## action steps on. Sophia's chord lifecycle decides when it is drawn (Held)
## and when it commits (Ended), so this module never waits on time itself.

proc eligibleRecentWindow(model: PolicyModel, windowId: WindowId): bool =
  let window = model.window(windowId)
  if window.isNone:
    return false
  let data = window.get()
  if data.minimized or not data.capabilities.focusable:
    return false
  if windowId == model.visibleScratchpad:
    return true
  let output = model.output(data.homeOutput)
  if output.isNone:
    return false
  for viewId in output.get().views:
    if model.windowTagIds(windowId).intersects(model.viewTagIds(viewId)):
      return true
  false

proc inRecentScope(
    model: PolicyModel, windowId: WindowId, scope: RecentWindowScope
): bool =
  case scope
  of RecentWindowScope.all:
    true
  of RecentWindowScope.output:
    model.window(windowId).get().homeOutput == model.activeOutput
  of RecentWindowScope.workspace:
    let output = model.output(model.activeOutput)
    output.isSome and model.window(windowId).get().homeOutput == model.activeOutput and (
      windowId == model.visibleScratchpad or
      model.windowTagIds(windowId).intersects(model.viewTagIds(output.get().activeView))
    )

proc recentWindowCandidates*(
    model: PolicyModel, scope: RecentWindowScope
): seq[WindowId] =
  ## Most recently focused first; windows never focused follow in window
  ## order, so a window opened in the background is still reachable.
  for index in countdown(model.recentFocus.high, 0):
    let windowId = model.recentFocus[index]
    if model.eligibleRecentWindow(windowId) and model.inRecentScope(windowId, scope):
      result.add(windowId)
  for windowId in model.windowOrder:
    if windowId notin result and model.eligibleRecentWindow(windowId) and
        model.inRecentScope(windowId, scope):
      result.add(windowId)

proc advanceRecentWindows*(model: var PolicyModel, forward: bool) =
  ## Opens on the first press already one step from the current focus, as
  ## niri does; with nothing focused it starts at the first (or last) entry.
  let step = if forward: 1 else: -1
  if model.recentWindows.active:
    let count = model.recentWindows.candidates.len
    model.recentWindows.selected =
      (model.recentWindows.selected + step + count) mod count
    return
  let scope = model.recentWindows.scope
  let candidates = model.recentWindowCandidates(scope)
  if candidates.len == 0:
    return
  model.clearOverview()
  var focused = nullWindowId
  let output = model.output(model.activeOutput)
  if output.isSome:
    focused = output.get().focusedWindow
  let current = candidates.find(focused)
  let selected =
    if current >= 0:
      (current + step + candidates.len) mod candidates.len
    elif forward:
      0
    else:
      candidates.high
  model.recentWindows = RecentWindowsState(
    active: true, scope: scope, candidates: candidates, selected: selected
  )

proc showRecentWindows*(model: var PolicyModel) =
  if model.recentWindows.active:
    model.recentWindows.visible = true

proc selectRecentWindow*(model: var PolicyModel, windowId: WindowId) =
  ## Pointer selection of a drawn preview.
  if not model.recentWindows.active:
    return
  let index = model.recentWindows.candidates.find(windowId)
  if index < 0:
    fail("recent-windows selection is not offered")
  model.recentWindows.selected = index

proc recentWindowView(model: PolicyModel, windowId: WindowId): ViewId =
  ## The view a committed window is shown on: its output's active view when it
  ## is already there, otherwise the first of that output's views holding it.
  let window = model.window(windowId).get()
  let output = model.output(window.homeOutput).get()
  if windowId == model.visibleScratchpad or
      model.windowTagIds(windowId).intersects(model.viewTagIds(output.activeView)):
    return output.activeView
  for viewId in output.views:
    if model.windowTagIds(windowId).intersects(model.viewTagIds(viewId)):
      return viewId
  fail("recent-windows selection has no workspace")

proc commitRecentWindows*(model: var PolicyModel) =
  ## Focus the selection and close. A selection that stopped being eligible
  ## while the switcher was open closes it without moving focus.
  if not model.recentWindows.active:
    return
  let windowId = model.recentWindows.candidates[model.recentWindows.selected]
  if not model.eligibleRecentWindow(windowId):
    model.clearRecentWindows()
    return
  let output = model.window(windowId).get().homeOutput
  let selection = OverviewSelection(
    output: output, view: model.recentWindowView(windowId), window: windowId
  )
  model.selectOverview(selection)
  model.clearRecentWindows()
