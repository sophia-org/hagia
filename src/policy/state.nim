import std/[options, sequtils, tables]

import ../types/[core, model]
import ./entity_store
import ../state/[id_gen, model as state_model, queries, values]
import ../entities/[focus_ops, output_ops, tag_ops, view_ops, window_ops]

export id_gen, state_model, queries, values
export focus_ops, output_ops, tag_ops, view_ops, window_ops

proc activateView*(model: var PolicyModel, outputId: OutputId, viewId: ViewId)
proc adoptWindowOutput*(model: var PolicyModel, windowId: WindowId, outputId: OutputId)
proc focusOccupiedWorkspaceRelative*(
    model: var PolicyModel, outputId: OutputId, delta: int
) =
  if outputId notin model.outputs:
    fail("occupied workspace output does not exist")
  var occupied: seq[TagId]
  for slot in 1'u32 .. maxWorkspaceTagSlot:
    let tagId = model.tagIdForSlot(slot)
    if tagId != nullTagId and model.workspaceOccupied(tagId):
      occupied.add(tagId)
  if occupied.len == 0:
    return
  let activeTags = model.viewTagIds(model.outputs[outputId].activeView)
  var current = -1
  for index, tagId in occupied:
    if tagId in activeTags:
      current = index
      break
  let targetIndex =
    if current < 0:
      if delta < 0: occupied.high else: 0
    else:
      wrappedIndex(current, delta, occupied.len)
  let target = occupied[targetIndex]
  var targetOutput = nullOutputId
  var targetView = nullViewId
  for candidateOutput in model.outputOrder:
    for viewId in model.outputs[candidateOutput].views:
      if target in model.viewTagIds(viewId) and
          (targetOutput == nullOutputId or candidateOutput == outputId):
        targetOutput = candidateOutput
        targetView = viewId
  if targetOutput == nullOutputId:
    fail("occupied workspace has no live view")
  model.setActiveOutput(targetOutput)
  model.activateView(targetOutput, targetView)

proc cycleLayout*(model: var PolicyModel, outputId: OutputId, delta = 1) =
  if outputId notin model.outputs or model.settings.layoutCycle.len == 0:
    fail("layout cycle target is invalid")
  let viewId = model.outputs[outputId].activeView
  let current = model.settings.layoutCycle.find(model.views[viewId].layout)
  let index =
    if current < 0:
      0
    else:
      wrappedIndex(current, delta, model.settings.layoutCycle.len)
  model.views[viewId].layout = model.settings.layoutCycle[index]

proc reconcilePolicySettings*(model: var PolicyModel) =
  ## Prepare a configuration candidate against stable logical state. Existing
  ## native layout selections survive when the new cycle still admits them;
  ## removed fixed profile views never recycle identity or discard window tags.
  if model.settings.viewCount < 1 or model.settings.viewCount > 9 or
      model.settings.layoutCycle.len == 0:
    fail("policy settings candidate is invalid")
  for viewId in model.views.ids:
    if model.views[viewId].layout notin model.settings.layoutCycle:
      model.views[viewId].layout = model.settings.layoutCycle[0]
  let outputs = model.outputOrder
  for outputId in outputs:
    for slot in 1'u32 .. uint32(model.settings.viewCount):
      if model.profileViewForSlot(outputId, slot) == nullViewId:
        discard model.addView(outputId, [model.profileTag(slot)])
    var removed: seq[ViewId]
    for viewId in model.outputs[outputId].views:
      let tags = model.viewTagIds(viewId)
      if tags.len == 1 and model.tags[tags[0]].kind == TagKind.profile and
          model.tags[tags[0]].slot > uint32(model.settings.viewCount):
        removed.add(viewId)
    if model.outputs[outputId].activeView in removed:
      model.activateView(outputId, model.profileViewForSlot(outputId, 1))
    for viewId in removed:
      model.removeView(viewId)
    var ordered: seq[ViewId]
    for slot in 1'u32 .. uint32(model.settings.viewCount):
      let viewId = model.profileViewForSlot(outputId, slot)
      if viewId != nullViewId:
        ordered.add(viewId)
    for viewId in model.outputs[outputId].views:
      if viewId notin ordered:
        ordered.add(viewId)
    model.outputs[outputId].views = ordered

proc placeTransient*(
    model: var PolicyModel,
    windowId, parentId: WindowId,
    desiredWidth, desiredHeight: int32,
    parentGeometry = Rect(),
) =
  if windowId notin model.windows or parentId notin model.windows or windowId == parentId:
    fail("transient placement relation is invalid")
  let outputId = model.windows[parentId].homeOutput
  model.adoptWindowOutput(windowId, outputId)
  model.windowTags[windowId] = model.windowTagIds(parentId)
  model.windows[windowId].floating = true
  var geometry = centeredGeometry(
    model.outputs[outputId].bounds,
    model.windows[windowId].constraints,
    desiredWidth,
    desiredHeight,
  )
  if parentGeometry.width > 0 and parentGeometry.height > 0:
    let bounds = model.outputs[outputId].bounds
    geometry.x = parentGeometry.x + (parentGeometry.width - geometry.width) div 2
    geometry.y = parentGeometry.y + (parentGeometry.height - geometry.height) div 2
    geometry.x = geometry.x.clamp(bounds.x, bounds.x + bounds.width - geometry.width)
    geometry.y = geometry.y.clamp(bounds.y, bounds.y + bounds.height - geometry.height)
  model.windows[windowId].floatingGeometry = geometry

proc adoptWindowOutput*(
    model: var PolicyModel, windowId: WindowId, outputId: OutputId
) =
  if windowId notin model.windows or outputId notin model.outputs:
    fail("window or output does not exist")
  if model.windows[windowId].homeOutput == outputId:
    return
  for currentOutput in model.outputOrder:
    if model.outputs[currentOutput].focusedWindow == windowId:
      model.outputs[currentOutput].focusedWindow = nullWindowId
    model.outputs[currentOutput].focusHistory.keepItIf(it != windowId)
  let source = model.windows[windowId].column
  if model.columns[source].windows.len == 1:
    model.columns[source].homeOutput = outputId
    model.columns[source].preferredOutput = outputId
  else:
    let scale = model.columns[source].widthScale
    model.columns[source].windows.keepItIf(it != windowId)
    let target = model.addColumn(outputId)
    model.columns[target].widthScale = scale
    model.columns[target].windows.add(windowId)
    model.windows[windowId].column = target
  model.windows[windowId].homeOutput = outputId
  model.windows[windowId].preferredOutput = outputId
  model.windows[windowId].floating = false
  model.windows[windowId].floatingGeometry = Rect()
  let activeView = model.outputs[outputId].activeView
  model.windowTags[windowId] =
    model.windowTagIds(windowId).unionTags(model.viewTagIds(activeView))

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
  model.windows[windowId].floatingGeometry = centeredGeometry(
    bounds,
    model.windows[windowId].constraints,
    max(1'i32, int32(int64(bounds.width) * 7 div 10)),
    max(1'i32, int32(int64(bounds.height) * 6 div 10)),
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

proc toggleViewTagSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > int(maxWorkspaceTagSlot):
    fail("view tag slot is outside the bounded range")
  let viewId = model.outputs[outputId].activeView
  let current = model.viewTagMask(viewId)
  let next = TagMask(uint64(current) xor uint64(tagForSlot(uint32(slot))))
  if next != emptyTagMask:
    model.setViewTags(outputId, viewId, next)

proc toggleFocusedWindowTagSlot*(
    model: var PolicyModel, outputId: OutputId, slot: int
) =
  if outputId notin model.outputs or slot < 1 or slot > int(maxWorkspaceTagSlot):
    fail("window tag slot is outside the bounded range")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let current = model.windowTagMask(windowId)
  let next = TagMask(uint64(current) xor uint64(tagForSlot(uint32(slot))))
  if next != emptyTagMask:
    model.setWindowTags(windowId, next)

proc activateView*(model: var PolicyModel, outputId: OutputId, viewId: ViewId) =
  let output = model.output(outputId)
  if output.isNone or viewId notin output.get().views:
    fail("view does not belong to the output")
  model.outputs[outputId].activeView = viewId
  let focus = model.outputs[outputId].focusedWindow
  if focus != nullWindowId:
    let window = model.window(focus)
    let tags = model.viewTagIds(viewId)
    if window.isNone or window.get().homeOutput != outputId or (
      focus != model.visibleScratchpad and not model.windowTagIds(focus).intersects(
        tags
      )
    ):
      model.outputs[outputId].focusedWindow = nullWindowId
  discard model.pruneDynamicWorkspaces()

proc focusOutputRelative*(model: var PolicyModel, delta: int) =
  if model.activeOutput notin model.outputs or model.outputOrder.len == 0:
    fail("active output is invalid")
  let current = model.outputOrder.find(model.activeOutput)
  model.activeOutput =
    model.outputOrder[wrappedIndex(current, delta, model.outputOrder.len)]

proc focusRelative*(model: var PolicyModel, outputId: OutputId, delta: int) =
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
  if eligible.len == 0:
    model.clearFocus(outputId)
    return
  let current = model.outputs[outputId].focusedWindow
  let currentIndex = eligible.find(current)
  if currentIndex < 0:
    var historyIndex = model.outputs[outputId].focusHistory.high
    while historyIndex >= 0:
      let remembered = model.outputs[outputId].focusHistory[historyIndex]
      if remembered in eligible:
        model.setFocus(outputId, remembered)
        return
      dec historyIndex
  let target =
    if currentIndex < 0:
      if delta < 0:
        eligible[^1]
      else:
        eligible[0]
    else:
      eligible[wrappedIndex(currentIndex, delta, eligible.len)]
  model.setFocus(outputId, target)

proc activateViewRelative*(model: var PolicyModel, outputId: OutputId, delta: int) =
  if outputId notin model.outputs:
    fail("view output does not exist")
  let views = model.outputs[outputId].views
  let current = views.find(model.outputs[outputId].activeView)
  if views.len == 0 or current < 0:
    fail("output has no active view")
  model.activateView(outputId, views[wrappedIndex(current, delta, views.len)])

proc activateViewSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > model.outputs[outputId].views.len:
    fail("view slot is outside the active profile")
  model.activateView(outputId, model.outputs[outputId].views[slot - 1])

proc moveFocusedToViewSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > model.outputs[outputId].views.len:
    fail("view slot is outside the active profile")
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  let view = model.outputs[outputId].views[slot - 1]
  model.setWindowTagIds(window, model.viewTagIds(view))
  model.activateView(outputId, view)
  model.setFocus(outputId, window)

proc placeWindowInViewSlot*(
    model: var PolicyModel, windowId: WindowId, outputId: OutputId, slot: int
) =
  ## Policy-local interpretation of an opaque launch class. Placement changes
  ## membership only; it does not switch the user's active view.
  if windowId notin model.windows or outputId notin model.outputs or slot < 1 or
      slot > model.outputs[outputId].views.len:
    fail("launch placement view slot is outside the active profile")
  model.adoptWindowOutput(windowId, outputId)
  let view = model.outputs[outputId].views[slot - 1]
  model.setWindowTagIds(windowId, model.viewTagIds(view))

proc moveFocusedToRelativeOutput*(
    model: var PolicyModel, outputId: OutputId, delta: int
) =
  if outputId notin model.outputs:
    fail("source output does not exist")
  if model.outputOrder.len < 2:
    return
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  let sourceIndex = model.outputOrder.find(outputId)
  let target =
    model.outputOrder[wrappedIndex(sourceIndex, delta, model.outputOrder.len)]
  model.adoptWindowOutput(window, target)
  model.setFocus(target, window)

proc adjustFocusedColumn*(model: var PolicyModel, outputId: OutputId, delta: int) =
  if outputId notin model.outputs:
    fail("column output does not exist")
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  let column = model.windows[window].column
  model.setColumnWidthScale(
    column, adjustedScale(model.columns[column].widthScale, delta)
  )

proc adjustFocusedWindow*(model: var PolicyModel, outputId: OutputId, delta: int) =
  if outputId notin model.outputs:
    fail("window output does not exist")
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  model.setWindowHeightScale(
    window, adjustedScale(model.windows[window].heightScale, delta)
  )

proc toggleFocusedFullscreen*(model: var PolicyModel) =
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("fullscreen output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  if not model.windows[windowId].capabilities.fullscreenable:
    fail("fullscreen target lacks capability")
  let enabled = not model.windows[windowId].fullscreen
  model.windows[windowId].fullscreen = enabled
  if enabled:
    model.windows[windowId].maximized = false
    model.windows[windowId].minimized = false

proc toggleFocusedMaximized*(model: var PolicyModel) =
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("maximize output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let enabled = not model.windows[windowId].maximized
  model.windows[windowId].maximized = enabled
  if enabled:
    model.windows[windowId].fullscreen = false
    model.windows[windowId].minimized = false

proc minimizeFocused*(model: var PolicyModel) =
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("minimize output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  model.windows[windowId].minimized = true
  model.windows[windowId].fullscreen = false
  model.windows[windowId].maximized = false
  model.minimizedOrder.keepItIf(it != windowId)
  model.minimizedOrder.add(windowId)
  if model.minimizedOrder.len > maxMinimizedHistory:
    model.minimizedOrder.delete(0)
  model.clearFocus(outputId)
  model.focusRelative(outputId, 1)

proc restoreLastMinimized*(model: var PolicyModel) =
  let outputId = model.activeOutput
  var index = model.minimizedOrder.high
  while index >= 0:
    let windowId = model.minimizedOrder[index]
    if windowId in model.windows and model.windows[windowId].homeOutput == outputId:
      model.windows[windowId].minimized = false
      model.minimizedOrder.delete(index)
      if model.windows[windowId].capabilities.focusable:
        model.setFocus(outputId, windowId)
      return
    dec index

proc toggleFocusedFloating*(model: var PolicyModel) =
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("floating output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let enabled = not model.windows[windowId].floating
  model.windows[windowId].floating = enabled
  if enabled and model.windows[windowId].floatingGeometry.width <= 0:
    model.windows[windowId].floatingGeometry = model.outputs[outputId].bounds

proc expelFocusedWindow*(model: var PolicyModel) =
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("expel output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let source = model.windows[windowId].column
  if model.columns[source].windows.len == 1:
    return
  model.columns[source].windows.keepItIf(it != windowId)
  let target = model.addColumn(outputId)
  model.columns[target].windows.add(windowId)
  model.windows[windowId].column = target

proc consumeNextColumn*(model: var PolicyModel) =
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("consume output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let source = model.windows[windowId].column
  var candidates: seq[ColumnId]
  for columnId in model.columnOrder:
    if model.columns[columnId].homeOutput == outputId:
      candidates.add(columnId)
  let current = candidates.find(source)
  if candidates.len < 2 or current < 0:
    return
  model.moveWindowToColumn(
    windowId, candidates[wrappedIndex(current, 1, candidates.len)]
  )

proc addDynamicWorkspace*(
    model: var PolicyModel, outputId: OutputId, name = ""
): ViewId =
  if outputId notin model.outputs:
    fail("dynamic workspace output does not exist")
  if name.len > maxWorkspaceNameBytes or '\0' in name:
    fail("workspace name is invalid")
  discard model.pruneDynamicWorkspaces()
  let slot = model.nextDynamicWorkspaceSlot()
  if slot == 0:
    fail("dynamic workspace slots are exhausted")
  let tagId = TagId(nextRaw(model.counters.tags, "tag"))
  model.tags[tagId] = TagData(id: tagId, slot: slot, kind: TagKind.dynamic, name: name)
  result = model.addView(outputId, [tagId])
  model.activateView(outputId, result)
