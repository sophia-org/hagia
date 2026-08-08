import std/[options, sequtils, sets, tables]

import ./types

type PolicyStateError* = object of CatchableError

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyStateError, message)

proc initPolicyModel*(): PolicyModel =
  PolicyModel()

proc clone*(model: PolicyModel): PolicyModel =
  result.nextWindowId = model.nextWindowId
  result.nextColumnId = model.nextColumnId
  result.nextViewId = model.nextViewId
  result.nextOutputId = model.nextOutputId
  result.nextTagSlot = model.nextTagSlot
  result.nextDisconnectOrder = model.nextDisconnectOrder
  for id in model.windowOrder:
    result.windowOrder.add(id)
    result.windows[id] = model.windows[id]
  for id in model.columnOrder:
    var column = model.columns[id]
    column.windows = @[]
    for windowId in model.columns[id].windows:
      column.windows.add(windowId)
    result.columnOrder.add(id)
    result.columns[id] = column
  for id, view in model.views.pairs:
    result.views[id] = view
  for id in model.outputOrder:
    var output = model.outputs[id]
    output.views = @[]
    for viewId in model.outputs[id].views:
      output.views.add(viewId)
    result.outputOrder.add(id)
    result.outputs[id] = output
  for id in model.affinityOrder:
    var affinity = model.affinities[id]
    affinity.views = @[]
    for viewId in model.affinities[id].views:
      affinity.views.add(viewId)
    result.affinityOrder.add(id)
    result.affinities[id] = affinity

proc tagForSlot*(slot: uint32): TagMask =
  if slot == 0 or slot > maxTagBits:
    fail("tag slot is outside Hagia's bounded mask")
  TagMask(1'u64 shl (slot - 1))

proc scaleFromRatio*(numerator, denominator: uint32): Scale =
  if denominator == 0:
    fail("scale denominator must be nonzero")
  let raw = uint64(numerator) * uint64(uint32(scaleOne)) div uint64(denominator)
  if raw < uint64(uint32(minimumScale)):
    return minimumScale
  if raw > uint64(high(uint32)):
    return Scale(high(uint32))
  Scale(uint32(raw))

proc intersects*(left, right: TagMask): bool =
  (uint64(left) and uint64(right)) != 0

proc union(left, right: TagMask): TagMask =
  TagMask(uint64(left) or uint64(right))

proc outputIds*(model: PolicyModel): seq[OutputId] =
  model.outputOrder

proc windowIds*(model: PolicyModel): seq[WindowId] =
  model.windowOrder

proc output*(model: PolicyModel, id: OutputId): Option[OutputData] =
  if id in model.outputs:
    some(model.outputs[id])
  else:
    none(OutputData)

proc window*(model: PolicyModel, id: WindowId): Option[WindowData] =
  if id in model.windows:
    some(model.windows[id])
  else:
    none(WindowData)

proc view*(model: PolicyModel, id: ViewId): Option[ViewData] =
  if id in model.views:
    some(model.views[id])
  else:
    none(ViewData)

proc affinity*(model: PolicyModel, id: OutputId): Option[OutputAffinity] =
  if id in model.affinities:
    some(model.affinities[id])
  else:
    none(OutputAffinity)

proc allocateOutputId(model: var PolicyModel): OutputId =
  inc model.nextOutputId
  if model.nextOutputId == 0:
    fail("output identity space is exhausted")
  OutputId(model.nextOutputId)

proc allocateViewId(model: var PolicyModel): ViewId =
  inc model.nextViewId
  if model.nextViewId == 0:
    fail("view identity space is exhausted")
  ViewId(model.nextViewId)

proc allocateTag(model: var PolicyModel): TagMask =
  inc model.nextTagSlot
  if model.nextTagSlot == 0 or model.nextTagSlot > maxTagBits:
    fail("tag identity space is exhausted")
  tagForSlot(model.nextTagSlot)

proc allocateWindowId(model: var PolicyModel): WindowId =
  inc model.nextWindowId
  if model.nextWindowId == 0:
    fail("window identity space is exhausted")
  WindowId(model.nextWindowId)

proc allocateColumnId(model: var PolicyModel): ColumnId =
  inc model.nextColumnId
  if model.nextColumnId == 0:
    fail("column identity space is exhausted")
  ColumnId(model.nextColumnId)

proc addColumn(model: var PolicyModel, outputId: OutputId): ColumnId =
  result = model.allocateColumnId()
  model.columns[result] =
    ColumnData(id: result, homeOutput: outputId, preferredOutput: outputId)
  model.columnOrder.add(result)

proc addView*(model: var PolicyModel, outputId: OutputId, tags: TagMask): ViewId =
  if tags == emptyTagMask:
    fail("a view must select at least one tag")
  if outputId notin model.outputs:
    fail("view output does not exist")
  result = model.allocateViewId()
  model.views[result] =
    ViewData(id: result, preferredOutput: outputId, selectedTags: tags)
  model.outputs[outputId].views.add(result)

proc addOutput*(model: var PolicyModel, bounds: Rect): OutputId =
  if bounds.width <= 0 or bounds.height <= 0:
    fail("output bounds must be positive")
  result = model.allocateOutputId()
  model.outputs[result] = OutputData(id: result, bounds: bounds)
  model.outputOrder.add(result)
  let viewId = model.addView(result, model.allocateTag())
  model.outputs[result].activeView = viewId

proc updateOutput*(model: var PolicyModel, id: OutputId, bounds: Rect) =
  if bounds.width <= 0 or bounds.height <= 0:
    fail("output bounds must be positive")
  if id notin model.outputs:
    fail("output does not exist")
  model.outputs[id].bounds = bounds

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
    tags: activeView.get().selectedTags,
    heightScale: scaleOne,
    capabilities: capabilities,
    constraints: constraints,
  )
  model.windowOrder.add(result)
  model.columns[column].windows.add(result)

proc removeWindow*(model: var PolicyModel, id: WindowId) =
  if id notin model.windows:
    return
  let column = model.windows[id].column
  model.windows.del(id)
  model.windowOrder.keepItIf(it != id)
  if column in model.columns:
    model.columns[column].windows.keepItIf(it != id)
    if model.columns[column].windows.len == 0:
      model.columns.del(column)
      model.columnOrder.keepItIf(it != column)
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == id:
      model.outputs[outputId].focusedWindow = nullWindowId
  for outputId in model.affinityOrder:
    if model.affinities[outputId].focusedWindow == id:
      model.affinities[outputId].focusedWindow = nullWindowId

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
  let activeView = model.outputs[outputId].activeView
  model.windows[windowId].tags =
    model.windows[windowId].tags.union(model.views[activeView].selectedTags)

proc setWindowTags*(model: var PolicyModel, id: WindowId, tags: TagMask) =
  if tags == emptyTagMask:
    fail("a window must retain at least one tag")
  if id notin model.windows:
    fail("window does not exist")
  model.windows[id].tags = tags
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow != id:
      continue
    let activeView = model.outputs[outputId].activeView
    if not tags.intersects(model.views[activeView].selectedTags):
      model.outputs[outputId].focusedWindow = nullWindowId

proc activateView*(model: var PolicyModel, outputId: OutputId, viewId: ViewId) =
  let output = model.output(outputId)
  if output.isNone or viewId notin output.get().views:
    fail("view does not belong to the output")
  model.outputs[outputId].activeView = viewId
  let focus = model.outputs[outputId].focusedWindow
  if focus != nullWindowId:
    let window = model.window(focus)
    let tags = model.views[viewId].selectedTags
    if window.isNone or window.get().homeOutput != outputId or
        not window.get().tags.intersects(tags):
      model.outputs[outputId].focusedWindow = nullWindowId

proc setFocus*(model: var PolicyModel, outputId: OutputId, windowId: WindowId) =
  let output = model.output(outputId)
  let window = model.window(windowId)
  if output.isNone or window.isNone:
    fail("focus target does not exist")
  let view = model.view(output.get().activeView)
  if view.isNone or window.get().homeOutput != outputId or
      not window.get().tags.intersects(view.get().selectedTags) or
      not window.get().capabilities.focusable:
    fail("focus target is not visible and focusable")
  model.outputs[outputId].focusedWindow = windowId

proc clearFocus*(model: var PolicyModel, outputId: OutputId) =
  if outputId notin model.outputs:
    fail("focus output does not exist")
  model.outputs[outputId].focusedWindow = nullWindowId

proc eligibleWindows*(model: PolicyModel, outputId: OutputId): seq[WindowId] =
  let output = model.output(outputId)
  if output.isNone:
    fail("projection output does not exist")
  let view = model.view(output.get().activeView)
  if view.isNone:
    fail("projection output has no active view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.homeOutput == outputId and window.tags.intersects(view.get().selectedTags):
      result.add(windowId)

proc forgetAffinity(model: var PolicyModel, id: OutputId) =
  if id notin model.affinities:
    return
  for viewId in model.affinities[id].views:
    if viewId in model.views and model.views[viewId].preferredOutput == id:
      for outputId in model.outputOrder:
        if viewId in model.outputs[outputId].views:
          model.views[viewId].preferredOutput = outputId
          break
  for windowId in model.windowOrder:
    if model.windows[windowId].preferredOutput == id:
      model.windows[windowId].preferredOutput = model.windows[windowId].homeOutput
  for columnId in model.columnOrder:
    if model.columns[columnId].preferredOutput == id:
      model.columns[columnId].preferredOutput = model.columns[columnId].homeOutput
  model.affinities.del(id)
  model.affinityOrder.keepItIf(it != id)

proc removeOutput*(model: var PolicyModel, id, fallback: OutputId): Option[OutputId] =
  if id == fallback or id notin model.outputs or fallback notin model.outputs:
    fail("output migration is invalid")
  let removed = model.outputs[id]
  inc model.nextDisconnectOrder
  if model.nextDisconnectOrder == 0:
    fail("output disconnect order is exhausted")
  model.affinities[id] = OutputAffinity(
    output: id,
    views: removed.views,
    activeView: removed.activeView,
    focusedWindow: removed.focusedWindow,
    disconnectedOrder: model.nextDisconnectOrder,
  )
  model.affinityOrder.keepItIf(it != id)
  model.affinityOrder.add(id)
  let fallbackView = model.outputs[fallback].activeView
  model.views[fallbackView].selectedTags = model.views[fallbackView].selectedTags.union(
    model.views[removed.activeView].selectedTags
  )
  for viewId in removed.views:
    if viewId notin model.outputs[fallback].views:
      model.outputs[fallback].views.add(viewId)
  for windowId in model.windowOrder:
    if model.windows[windowId].homeOutput == id:
      model.windows[windowId].homeOutput = fallback
  for columnId in model.columnOrder:
    if model.columns[columnId].homeOutput == id:
      model.columns[columnId].homeOutput = fallback
  if model.outputs[fallback].focusedWindow == nullWindowId and
      removed.focusedWindow != nullWindowId:
    model.outputs[fallback].focusedWindow = removed.focusedWindow
  model.outputs.del(id)
  model.outputOrder.keepItIf(it != id)
  if model.affinityOrder.len > maxOutputAffinities:
    result = some(model.affinityOrder[0])
    model.forgetAffinity(result.get())

proc restoreOutput*(model: var PolicyModel, id: OutputId, bounds: Rect) =
  if bounds.width <= 0 or bounds.height <= 0:
    fail("output bounds must be positive")
  if id in model.outputs or id notin model.affinities:
    fail("output affinity cannot be restored")
  let saved = model.affinities[id]
  var views: seq[ViewId]
  for viewId in saved.views:
    if viewId notin model.views or model.views[viewId].preferredOutput != id:
      continue
    for outputId in model.outputOrder:
      model.outputs[outputId].views.keepItIf(it != viewId)
    views.add(viewId)
  if views.len == 0:
    let viewId = model.allocateViewId()
    model.views[viewId] =
      ViewData(id: viewId, preferredOutput: id, selectedTags: model.allocateTag())
    views.add(viewId)
  let activeView =
    if saved.activeView in views:
      saved.activeView
    else:
      views[0]
  model.outputs[id] =
    OutputData(id: id, bounds: bounds, views: views, activeView: activeView)
  model.outputOrder.add(id)
  for windowId in model.windowOrder:
    if model.windows[windowId].preferredOutput == id:
      model.windows[windowId].homeOutput = id
  for columnId in model.columnOrder:
    if model.columns[columnId].preferredOutput == id:
      model.columns[columnId].homeOutput = id
  let focus = saved.focusedWindow
  if focus in model.windows and model.windows[focus].homeOutput == id and
      model.windows[focus].capabilities.focusable and
      model.windows[focus].tags.intersects(model.views[activeView].selectedTags):
    model.outputs[id].focusedWindow = focus
  model.affinities.del(id)
  model.affinityOrder.keepItIf(it != id)

proc validate*(model: PolicyModel) =
  if model.outputOrder.len != model.outputs.len or
      model.windowOrder.len != model.windows.len or
      model.columnOrder.len != model.columns.len:
    fail("policy indexes and ordered identities diverged")
  var seenViews = initHashSet[ViewId]()
  for outputId in model.outputOrder:
    let output = model.outputs[outputId]
    if output.id != outputId or output.bounds.width <= 0 or output.bounds.height <= 0 or
        output.views.len == 0 or output.activeView notin output.views:
      fail("policy output is invalid")
    for viewId in output.views:
      if viewId notin model.views or viewId in seenViews or
          model.views[viewId].selectedTags == emptyTagMask or
          model.views[viewId].preferredOutput == nullOutputId:
        fail("policy view is invalid")
      seenViews.incl(viewId)
    if output.focusedWindow != nullWindowId:
      if output.focusedWindow notin model.windows:
        fail("policy output focus is invalid")
      let focus = model.windows[output.focusedWindow]
      if focus.homeOutput != outputId or not focus.capabilities.focusable or
          not focus.tags.intersects(model.views[output.activeView].selectedTags):
        fail("policy output focus is invalid")
  if seenViews.len != model.views.len:
    fail("policy contains a detached view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.id != windowId or window.homeOutput notin model.outputs or
        window.preferredOutput == nullOutputId or window.column notin model.columns or
        window.tags == emptyTagMask or uint32(window.heightScale) < uint32(minimumScale):
      fail("policy window is invalid")
    if window.constraints.minWidth < 0 or window.constraints.minHeight < 0 or
        window.constraints.maxWidth < 0 or window.constraints.maxHeight < 0 or
        (window.constraints.minWidth == 0) != (window.constraints.minHeight == 0) or
        (window.constraints.maxWidth == 0) != (window.constraints.maxHeight == 0) or (
      window.constraints.minWidth > 0 and window.constraints.maxWidth > 0 and (
        window.constraints.minWidth > window.constraints.maxWidth or
        window.constraints.minHeight > window.constraints.maxHeight
      )
    ):
      fail("policy window constraints are invalid")
  var seenWindows = initHashSet[WindowId]()
  for columnId in model.columnOrder:
    let column = model.columns[columnId]
    if column.id != columnId or column.homeOutput notin model.outputs or
        column.preferredOutput == nullOutputId or column.windows.len == 0 or (
      column.widthScale != autoScale and uint32(column.widthScale) < uint32(
        minimumScale
      )
    ):
      fail("policy column is invalid")
    for windowId in column.windows:
      if windowId notin model.windows or windowId in seenWindows or
          model.windows[windowId].column != columnId or
          model.windows[windowId].homeOutput != column.homeOutput:
        fail("policy column membership is invalid")
      seenWindows.incl(windowId)
  if seenWindows.len != model.windows.len:
    fail("policy contains a detached window")
  if model.affinityOrder.len != model.affinities.len or
      model.affinityOrder.len > maxOutputAffinities:
    fail("output affinities are invalid")
  var seenAffinities = initHashSet[OutputId]()
  var previousOrder = 0'u64
  for outputId in model.affinityOrder:
    if outputId in seenAffinities or outputId in model.outputs or
        outputId notin model.affinities:
      fail("output affinity identity is invalid")
    let affinity = model.affinities[outputId]
    if affinity.output != outputId or affinity.views.len == 0 or
        affinity.disconnectedOrder <= previousOrder:
      fail("output affinity record is invalid")
    for viewId in affinity.views:
      if viewId notin model.views:
        fail("output affinity view is invalid")
    seenAffinities.incl(outputId)
    previousOrder = affinity.disconnectedOrder
