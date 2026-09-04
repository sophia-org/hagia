import std/[options, sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, queries, values]

import ./[focus_ops, group_ops, tag_ops]

## Window and column lifecycle. Closing a window touches arrays, tags, columns,
## and histories, so every one of those updates happens here in one pass.

proc addColumn*(model: var PolicyModel, outputId: OutputId): ColumnId =
  result = model.allocateColumnId()
  model.columns[result] =
    ColumnData(id: result, homeOutput: outputId, preferredOutput: outputId)
  model.columnOrder.add(result)

proc addWindow*(
    model: var PolicyModel,
    homeOutput: OutputId,
    capabilities: WindowCapabilities,
    constraints: SizeConstraints,
): WindowId =
  let output = model.output(homeOutput)
  if output.isNone:
    fail("window home output does not exist")
  let activeView = model.view(output.get().activeView)
  if activeView.isNone:
    fail("window home output has no active view")
  result = model.allocateWindowId()
  let column = model.addColumn(homeOutput)
  model.windows[result] = WindowData(
    id: result,
    homeOutput: homeOutput,
    preferredOutput: homeOutput,
    column: column,
    heightScale: scaleOne,
    capabilities: capabilities,
    constraints: constraints,
  )
  model.windowTags[result] = model.viewTagIds(activeView.get().id)
  model.windowOrder.add(result)
  model.columns[column].windows.add(result)

proc removeWindow*(model: var PolicyModel, id: WindowId) =
  if id notin model.windows:
    return
  let column = model.windows[id].column
  model.scratchpadOrder.keepItIf(it != id)
  model.scratchpadRestore.del(id)
  if model.visibleScratchpad == id:
    model.visibleScratchpad = nullWindowId
  var removedSlots: seq[ScratchpadSlotId]
  for slot, windowId in model.namedScratchpads.pairs:
    if windowId == id:
      removedSlots.add(slot)
  for slot in removedSlots:
    model.namedScratchpads.del(slot)
  model.forgetGroupMembership(id)
  for windowId in model.windowOrder:
    if windowId != id and model.windows[windowId].parent == id:
      model.windows[windowId].parent = nullWindowId
  model.windows.del(id)
  model.windowTags.del(id)
  model.windowOrder.keepItIf(it != id)
  model.minimizedOrder.keepItIf(it != id)
  if column in model.columns:
    model.columns[column].windows.keepItIf(it != id)
    if model.columns[column].windows.len == 0:
      model.columns.del(column)
      model.columnOrder.keepItIf(it != column)
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == id:
      model.outputs[outputId].focusedWindow = nullWindowId
    model.outputs[outputId].focusHistory.keepItIf(it != id)
  for outputId in model.affinityOrder:
    if model.affinities[outputId].focusedWindow == id:
      model.affinities[outputId].focusedWindow = nullWindowId
  discard model.pruneDynamicWorkspaces()

proc updateWindowFacts*(
    model: var PolicyModel,
    id: WindowId,
    capabilities: WindowCapabilities,
    constraints: SizeConstraints,
) =
  if id notin model.windows:
    fail("window does not exist")
  model.windows[id].capabilities = capabilities
  model.windows[id].constraints = constraints

proc setWindowRelation*(
    model: var PolicyModel, id: WindowId, kind: WindowKind, parent: WindowId
) =
  if id notin model.windows or parent == id or
      (parent != nullWindowId and parent notin model.windows):
    fail("window relation is invalid")
  var ancestor = parent
  while ancestor != nullWindowId:
    if ancestor == id:
      fail("window parent relation is cyclic")
    ancestor = model.windows[ancestor].parent
  model.windows[id].kind = kind
  model.windows[id].parent = parent

proc setWindowPresentation*(
    model: var PolicyModel, id: WindowId, fullscreen, maximized, minimized: bool
) =
  if id notin model.windows or (fullscreen and maximized) or
      (minimized and (fullscreen or maximized)):
    fail("window presentation state is invalid")
  if fullscreen and not model.windows[id].capabilities.fullscreenable:
    fail("window lacks fullscreen capability")
  let wasMinimized = model.windows[id].minimized
  model.windows[id].fullscreen = fullscreen
  model.windows[id].maximized = maximized
  model.windows[id].minimized = minimized
  if minimized != wasMinimized:
    model.minimizedOrder.keepItIf(it != id)
    if minimized:
      model.minimizedOrder.add(id)
      if model.minimizedOrder.len > maxMinimizedHistory:
        model.minimizedOrder.delete(0)
  if minimized:
    for outputId in model.outputOrder:
      if model.outputs[outputId].focusedWindow == id:
        model.outputs[outputId].focusedWindow = nullWindowId

proc setColumnWidthScale*(model: var PolicyModel, id: ColumnId, scale: Scale) =
  if id notin model.columns:
    fail("column does not exist")
  if scale != autoScale and uint32(scale) < uint32(minimumScale):
    fail("column scale is too small")
  model.columns[id].widthScale = scale

proc setWindowHeightScale*(model: var PolicyModel, id: WindowId, scale: Scale) =
  if id notin model.windows:
    fail("window does not exist")
  if uint32(scale) < uint32(minimumScale):
    fail("window scale is too small")
  model.windows[id].heightScale = scale

proc setFloatingGeometry*(
    model: var PolicyModel, outputId: OutputId, windowId: WindowId, geometry: Rect
) =
  if outputId notin model.outputs or windowId notin model.windows:
    fail("floating interaction target does not exist")
  if model.windows[windowId].homeOutput != outputId or
      not model.outputs[outputId].bounds.contains(geometry):
    fail("floating interaction geometry is outside its output")
  if not model.windows[windowId].capabilities.movable and
      not model.windows[windowId].capabilities.resizable:
    fail("floating interaction target is immutable")
  model.windows[windowId].floating = true
  model.windows[windowId].floatingGeometry = geometry
  if model.windows[windowId].capabilities.focusable:
    model.setFocus(outputId, windowId)

proc moveWindowToColumn*(
    model: var PolicyModel, windowId: WindowId, columnId: ColumnId
) =
  if windowId notin model.windows or columnId notin model.columns:
    fail("window or column does not exist")
  let source = model.windows[windowId].column
  if source == columnId:
    return
  if model.windows[windowId].homeOutput != model.columns[columnId].homeOutput:
    fail("column belongs to a different output")
  model.columns[source].windows.keepItIf(it != windowId)
  model.columns[columnId].windows.add(windowId)
  model.windows[windowId].column = columnId
  if model.columns[source].windows.len == 0:
    model.columns.del(source)
    model.columnOrder.keepItIf(it != source)

proc moveWindowToScratchpad*(model: var PolicyModel, windowId: WindowId) =
  if windowId notin model.windows:
    fail("scratchpad window does not exist")
  if windowId notin model.scratchpadRestore:
    if model.scratchpadOrder.len >= maxScratchpads:
      fail("scratchpad capacity is exhausted")
    let window = model.windows[windowId]
    model.scratchpadRestore[windowId] = ScratchpadRestoreData(
      tags: model.windowTagIds(windowId),
      output: window.homeOutput,
      floating: window.floating,
      floatingGeometry: window.floatingGeometry,
      fullscreen: window.fullscreen,
      maximized: window.maximized,
      minimized: window.minimized,
    )
    model.scratchpadOrder.add(windowId)
  let tagId = model.ensureScratchpadTag()
  model.windowTags[windowId] = @[tagId]
  model.minimizedOrder.keepItIf(it != windowId)
  model.windows[windowId].fullscreen = false
  model.windows[windowId].maximized = false
  model.windows[windowId].minimized = false
  model.windows[windowId].floating = true
  let bounds = model.outputs[model.windows[windowId].homeOutput].bounds
  model.windows[windowId].floatingGeometry = centeredGeometry(
    bounds,
    model.windows[windowId].constraints,
    max(1'i32, int32(int64(bounds.width) * 7 div 10)),
    max(1'i32, int32(int64(bounds.height) * 6 div 10)),
  )
  if model.visibleScratchpad == windowId:
    model.visibleScratchpad = nullWindowId
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == windowId:
      model.outputs[outputId].focusedWindow = nullWindowId

proc assignNamedScratchpad*(
    model: var PolicyModel, slot: ScratchpadSlotId, windowId: WindowId
) =
  if slot == nullScratchpadSlotId or windowId notin model.scratchpadRestore:
    fail("named scratchpad relation is invalid")
  model.namedScratchpads[slot] = windowId
