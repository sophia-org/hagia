import std/[sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ../entities/[focus_ops, tag_ops, window_ops]

import ./placement

## Scratchpad policy. Hiding and showing a scratchpad window is a decision
## about visibility; the tag and geometry changes it needs are entity work.

proc moveFocusedToScratchpad*(model: var PolicyModel, outputId: OutputId) =
  if outputId notin model.outputs:
    fail("scratchpad output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId != nullWindowId:
    model.moveWindowToScratchpad(windowId)

proc hideScratchpad*(model: var PolicyModel) =
  let windowId = model.visibleScratchpad
  if windowId == nullWindowId:
    return
  model.visibleScratchpad = nullWindowId
  model.scratchpadOrder.keepItIf(it != windowId)
  model.scratchpadOrder.add(windowId)
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == windowId:
      model.outputs[outputId].focusedWindow = nullWindowId

proc showScratchpad*(model: var PolicyModel, outputId: OutputId, windowId: WindowId) =
  if outputId notin model.outputs or windowId notin model.scratchpadRestore or
      windowId notin model.windows:
    fail("scratchpad show target is invalid")
  model.adoptWindowOutput(windowId, outputId)
  model.windowTags[windowId] = @[model.ensureScratchpadTag()]
  let bounds = model.outputs[outputId].bounds
  model.windows[windowId].floating = true
  let (scratchWidth, scratchHeight) = bounds.placementSize(
    model.settings.scratchpadWidthPercent, model.settings.scratchpadHeightPercent
  )
  model.windows[windowId].floatingGeometry = centeredGeometry(
    bounds, model.windows[windowId].constraints, scratchWidth, scratchHeight
  )
  model.visibleScratchpad = windowId
  if model.windows[windowId].capabilities.focusable:
    model.setFocus(outputId, windowId)

proc toggleScratchpad*(model: var PolicyModel, outputId: OutputId) =
  if model.visibleScratchpad != nullWindowId:
    model.hideScratchpad()
    return
  if model.scratchpadOrder.len > 0:
    model.showScratchpad(outputId, model.scratchpadOrder[0])

proc restoreScratchpad*(model: var PolicyModel, windowId: WindowId) =
  if windowId notin model.scratchpadRestore or windowId notin model.windows:
    return
  let restore = model.scratchpadRestore[windowId]
  let wasVisible = model.visibleScratchpad == windowId
  model.scratchpadRestore.del(windowId)
  model.scratchpadOrder.keepItIf(it != windowId)
  if wasVisible:
    model.visibleScratchpad = nullWindowId
  var removedSlots: seq[ScratchpadSlotId]
  for slot, id in model.namedScratchpads.pairs:
    if id == windowId:
      removedSlots.add(slot)
  for slot in removedSlots:
    model.namedScratchpads.del(slot)
  let outputId =
    if restore.output in model.outputs:
      restore.output
    else:
      model.windows[windowId].homeOutput
  model.adoptWindowOutput(windowId, outputId)
  model.windowTags[windowId] = restore.tags
  model.windows[windowId].floating = restore.floating
  model.windows[windowId].floatingGeometry = restore.floatingGeometry
  model.windows[windowId].fullscreen = restore.fullscreen
  model.windows[windowId].maximized = restore.maximized
  model.windows[windowId].minimized = restore.minimized
  if restore.minimized:
    model.minimizedOrder.keepItIf(it != windowId)
    model.minimizedOrder.add(windowId)
  elif wasVisible and model.windows[windowId].capabilities.focusable and
      model.windowTagIds(windowId).intersects(
        model.viewTagIds(model.outputs[outputId].activeView)
      ):
    model.setFocus(outputId, windowId)
  discard model.pruneDynamicWorkspaces()

proc restoreVisibleScratchpad*(model: var PolicyModel) =
  let windowId =
    if model.visibleScratchpad != nullWindowId:
      model.visibleScratchpad
    elif model.scratchpadOrder.len > 0:
      model.scratchpadOrder[0]
    else:
      nullWindowId
  model.restoreScratchpad(windowId)

proc toggleNamedScratchpad*(
    model: var PolicyModel, outputId: OutputId, slot: ScratchpadSlotId
) =
  if slot notin model.namedScratchpads:
    return
  let windowId = model.namedScratchpads[slot]
  if model.visibleScratchpad == windowId:
    model.hideScratchpad()
  else:
    model.showScratchpad(outputId, windowId)

proc moveFocusedToNamedScratchpad*(
    model: var PolicyModel, outputId: OutputId, slot: ScratchpadSlotId
) =
  ## Send the focused window to a named slot. A slot holds one window, so
  ## naming an occupied slot replaces what was there; the displaced window
  ## stays a scratchpad and remains reachable through the unnamed rotation.
  if outputId notin model.outputs:
    fail("scratchpad output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  model.moveWindowToScratchpad(windowId)
  model.assignNamedScratchpad(slot, windowId)
