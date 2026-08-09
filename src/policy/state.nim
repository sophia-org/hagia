import std/[options, sequtils, sets, tables]

import ./entity_store
import ./types

type PolicyStateError* = object of CatchableError

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyStateError, message)

proc nextRaw(counter: var uint32, kind: string): uint32 =
  ## Ported from Triad's centralized nonzero logical-ID generator. Keeping the
  ## exhaustion check before increment makes wraparound terminal and testable.
  if counter == high(uint32):
    fail(kind & " identity space is exhausted")
  inc counter
  if counter == 0:
    fail(kind & " identity counter wrapped to zero")
  counter

proc initPolicyModel*(): PolicyModel =
  PolicyModel(settings: defaultPolicySettings)

proc clone*(model: PolicyModel): PolicyModel =
  result.settings = model.settings
  result.activeOutput = model.activeOutput
  result.counters = model.counters
  for id in model.windowOrder:
    result.windowOrder.add(id)
    result.windows[id] = model.windows[id]
  for id in model.minimizedOrder:
    result.minimizedOrder.add(id)
  for id in model.columnOrder:
    var column = model.columns[id]
    column.windows = @[]
    for windowId in model.columns[id].windows:
      column.windows.add(windowId)
    result.columnOrder.add(id)
    result.columns[id] = column
  for id, view in model.views.pairs:
    result.views[id] = view
  for id, tag in model.tags.pairs:
    result.tags[id] = tag
  for id, tags in model.windowTags.pairs:
    result.windowTags[id] = @tags
  for id, tags in model.viewTags.pairs:
    result.viewTags[id] = @tags
  for id in model.outputOrder:
    var output = model.outputs[id]
    output.views = @[]
    output.focusHistory = @[]
    for viewId in model.outputs[id].views:
      output.views.add(viewId)
    for windowId in model.outputs[id].focusHistory:
      output.focusHistory.add(windowId)
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

proc nextTagSlot*(model: PolicyModel): uint32 =
  model.counters.tags

proc intersects*(left, right: openArray[TagId]): bool =
  for leftTag in left:
    if leftTag in right:
      return true
  false

proc unionTags(left, right: openArray[TagId]): seq[TagId] =
  result = @left
  for tag in right:
    if tag notin result:
      result.add(tag)

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

proc windowTagIds*(model: PolicyModel, id: WindowId): seq[TagId] =
  if id in model.windowTags:
    model.windowTags[id]
  else:
    @[]

proc viewTagIds*(model: PolicyModel, id: ViewId): seq[TagId] =
  if id in model.viewTags:
    model.viewTags[id]
  else:
    @[]

proc tagsToMask(model: PolicyModel, tags: openArray[TagId]): TagMask =
  var bits = 0'u64
  for tagId in tags:
    if tagId notin model.tags:
      fail("tag membership names an unknown tag")
    let slot = model.tags[tagId].slot
    if slot == 0 or slot > maxTagBits:
      fail("tag slot is outside Hagia's bounded range")
    bits = bits or uint64(tagForSlot(slot))
  TagMask(bits)

proc windowTagMask*(model: PolicyModel, id: WindowId): TagMask =
  model.tagsToMask(model.windowTagIds(id))

proc viewTagMask*(model: PolicyModel, id: ViewId): TagMask =
  model.tagsToMask(model.viewTagIds(id))

proc allocateOutputId(model: var PolicyModel): OutputId =
  OutputId(nextRaw(model.counters.outputs, "output"))

proc allocateViewId(model: var PolicyModel): ViewId =
  ViewId(nextRaw(model.counters.views, "view"))

proc profileTag(model: var PolicyModel, slot: uint32): TagId =
  if slot == 0 or slot > maxTagBits:
    fail("tag slot is outside Hagia's bounded range")
  for tagId, tag in model.tags.pairs:
    if tag.slot == slot:
      return tagId
  while model.counters.tags < slot:
    let tagId = TagId(nextRaw(model.counters.tags, "tag"))
    model.tags[tagId] = TagData(id: tagId, slot: uint32(tagId))
  TagId(slot)

proc tagIdsForMask(model: var PolicyModel, mask: TagMask): seq[TagId] =
  if mask == emptyTagMask:
    fail("tag membership must be nonempty")
  for slot in 1'u32 .. maxTagBits:
    if (uint64(mask) and uint64(tagForSlot(slot))) != 0:
      result.add(model.profileTag(slot))

proc allocateWindowId(model: var PolicyModel): WindowId =
  WindowId(nextRaw(model.counters.windows, "window"))

proc allocateColumnId(model: var PolicyModel): ColumnId =
  ColumnId(nextRaw(model.counters.columns, "column"))

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
  model.views[result] = ViewData(id: result, preferredOutput: outputId)
  model.viewTags[result] = model.tagIdsForMask(tags)
  model.outputs[outputId].views.add(result)

proc addView*(
    model: var PolicyModel, outputId: OutputId, tags: openArray[TagId]
): ViewId =
  if tags.len == 0:
    fail("a view must select at least one tag")
  if outputId notin model.outputs:
    fail("view output does not exist")
  for tagId in tags:
    if tagId notin model.tags:
      fail("view membership names an unknown tag")
  result = model.allocateViewId()
  model.views[result] = ViewData(id: result, preferredOutput: outputId)
  model.viewTags[result] = @tags
  model.outputs[outputId].views.add(result)

proc ensureViewCount*(model: var PolicyModel, outputId: OutputId, count: int) =
  if outputId notin model.outputs or count < 1 or count > 9:
    fail("view profile is outside Hagia's bounded range")
  while model.outputs[outputId].views.len < count:
    let slot = uint32(model.outputs[outputId].views.len + 1)
    discard model.addView(outputId, [model.profileTag(slot)])

proc addOutput*(model: var PolicyModel, bounds: Rect): OutputId =
  if bounds.width <= 0 or bounds.height <= 0:
    fail("output bounds must be positive")
  result = model.allocateOutputId()
  model.outputs[result] = OutputData(id: result, bounds: bounds)
  model.outputOrder.add(result)
  let viewId = model.addView(result, [model.profileTag(1)])
  model.outputs[result].activeView = viewId
  if model.activeOutput == nullOutputId:
    model.activeOutput = result

proc setActiveOutput*(model: var PolicyModel, id: OutputId) =
  if id notin model.outputs:
    fail("active output does not exist")
  model.activeOutput = id

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

proc setFocus*(model: var PolicyModel, outputId: OutputId, windowId: WindowId)

proc contains(bounds, geometry: Rect): bool =
  geometry.width > 0 and geometry.height > 0 and geometry.x >= bounds.x and
    geometry.y >= bounds.y and
    int64(geometry.x) + int64(geometry.width) <= int64(bounds.x) + int64(bounds.width) and
    int64(geometry.y) + int64(geometry.height) <= int64(bounds.y) + int64(bounds.height)

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

proc setWindowTags*(model: var PolicyModel, id: WindowId, tags: TagMask) =
  if tags == emptyTagMask:
    fail("a window must retain at least one tag")
  if id notin model.windows:
    fail("window does not exist")
  model.windowTags[id] = model.tagIdsForMask(tags)
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow != id:
      continue
    let activeView = model.outputs[outputId].activeView
    if not model.windowTagIds(id).intersects(model.viewTagIds(activeView)):
      model.outputs[outputId].focusedWindow = nullWindowId

proc setWindowTagIds*(model: var PolicyModel, id: WindowId, tags: openArray[TagId]) =
  if tags.len == 0 or id notin model.windows:
    fail("a window must retain at least one valid tag")
  var unique: seq[TagId]
  for tagId in tags:
    if tagId notin model.tags:
      fail("window membership names an unknown tag")
    if tagId notin unique:
      unique.add(tagId)
  model.windowTags[id] = unique
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == id and
        not unique.intersects(model.viewTagIds(model.outputs[outputId].activeView)):
      model.outputs[outputId].focusedWindow = nullWindowId

proc setViewTags*(
    model: var PolicyModel, outputId: OutputId, viewId: ViewId, tags: TagMask
) =
  if tags == emptyTagMask:
    fail("a view must retain at least one tag")
  if outputId notin model.outputs or viewId notin model.outputs[outputId].views:
    fail("view does not belong to the output")
  model.viewTags[viewId] = model.tagIdsForMask(tags)
  if model.outputs[outputId].activeView != viewId:
    return
  let focus = model.outputs[outputId].focusedWindow
  if focus != nullWindowId and
      not model.windowTagIds(focus).intersects(model.viewTagIds(viewId)):
    model.outputs[outputId].focusedWindow = nullWindowId

proc setViewTagIds*(
    model: var PolicyModel, outputId: OutputId, viewId: ViewId, tags: openArray[TagId]
) =
  if tags.len == 0 or outputId notin model.outputs or
      viewId notin model.outputs[outputId].views:
    fail("a view must retain at least one valid tag")
  var unique: seq[TagId]
  for tagId in tags:
    if tagId notin model.tags:
      fail("view membership names an unknown tag")
    if tagId notin unique:
      unique.add(tagId)
  model.viewTags[viewId] = unique
  if model.outputs[outputId].activeView == viewId:
    let focus = model.outputs[outputId].focusedWindow
    if focus != nullWindowId and not model.windowTagIds(focus).intersects(unique):
      model.outputs[outputId].focusedWindow = nullWindowId

proc toggleViewTagSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > int(maxTagBits):
    fail("view tag slot is outside the bounded range")
  let viewId = model.outputs[outputId].activeView
  let current = model.viewTagMask(viewId)
  let next = TagMask(uint64(current) xor uint64(tagForSlot(uint32(slot))))
  if next != emptyTagMask:
    model.setViewTags(outputId, viewId, next)

proc toggleFocusedWindowTagSlot*(
    model: var PolicyModel, outputId: OutputId, slot: int
) =
  if outputId notin model.outputs or slot < 1 or slot > int(maxTagBits):
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
    if window.isNone or window.get().homeOutput != outputId or
        not model.windowTagIds(focus).intersects(tags):
      model.outputs[outputId].focusedWindow = nullWindowId

proc setFocus*(model: var PolicyModel, outputId: OutputId, windowId: WindowId) =
  let output = model.output(outputId)
  let window = model.window(windowId)
  if output.isNone or window.isNone:
    fail("focus target does not exist")
  let view = model.view(output.get().activeView)
  if view.isNone or window.get().homeOutput != outputId or
      not model.windowTagIds(windowId).intersects(model.viewTagIds(view.get().id)) or
      not window.get().capabilities.focusable or window.get().minimized:
    fail("focus target is not visible and focusable")
  model.outputs[outputId].focusedWindow = windowId
  model.outputs[outputId].focusHistory.keepItIf(it != windowId)
  model.outputs[outputId].focusHistory.add(windowId)
  if model.outputs[outputId].focusHistory.len > maxFocusHistory:
    model.outputs[outputId].focusHistory.delete(0)
  model.activeOutput = outputId

proc clearFocus*(model: var PolicyModel, outputId: OutputId) =
  if outputId notin model.outputs:
    fail("focus output does not exist")
  model.outputs[outputId].focusedWindow = nullWindowId

proc wrappedIndex(current, delta, length: int): int =
  if length <= 0:
    fail("cannot wrap an empty policy sequence")
  ((current + delta) mod length + length) mod length

proc focusOutputRelative*(model: var PolicyModel, delta: int) =
  if model.activeOutput notin model.outputs or model.outputOrder.len == 0:
    fail("active output is invalid")
  let current = model.outputOrder.find(model.activeOutput)
  model.activeOutput =
    model.outputOrder[wrappedIndex(current, delta, model.outputOrder.len)]

proc eligibleWindows*(model: PolicyModel, outputId: OutputId): seq[WindowId]

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

proc adjustedScale(current: Scale, delta: int): Scale =
  let base =
    if current == autoScale:
      uint64(uint32(scaleOne))
    else:
      uint64(uint32(current))
  let step = uint64(uint32(scaleOne)) div 20
  if delta > 0:
    return Scale(uint32(min(uint64(high(uint32)), base + step * uint64(delta))))
  let reduction = step * uint64(-delta)
  let reduced =
    if reduction >= base:
      0'u64
    else:
      base - reduction
  Scale(uint32(max(uint64(uint32(minimumScale)), reduced)))

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

proc eligibleWindows*(model: PolicyModel, outputId: OutputId): seq[WindowId] =
  let output = model.output(outputId)
  if output.isNone:
    fail("projection output does not exist")
  let view = model.view(output.get().activeView)
  if view.isNone:
    fail("projection output has no active view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.homeOutput == outputId and
        model.windowTagIds(windowId).intersects(model.viewTagIds(view.get().id)):
      result.add(windowId)

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
  if model.counters.disconnects == high(uint64):
    fail("output disconnect order is exhausted")
  inc model.counters.disconnects
  model.affinities[id] = OutputAffinity(
    output: id,
    views: removed.views,
    activeView: removed.activeView,
    focusedWindow: removed.focusedWindow,
    disconnectedOrder: model.counters.disconnects,
  )
  model.affinityOrder.keepItIf(it != id)
  model.affinityOrder.add(id)
  let fallbackView = model.outputs[fallback].activeView
  model.viewTags[fallbackView] =
    model.viewTagIds(fallbackView).unionTags(model.viewTagIds(removed.activeView))
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
  if model.activeOutput == id:
    model.activeOutput = fallback
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
    model.views[viewId] = ViewData(id: viewId, preferredOutput: id)
    model.viewTags[viewId] = @[model.profileTag(1)]
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
      model.windows[focus].capabilities.focusable and not model.windows[focus].minimized and
      model.windowTagIds(focus).intersects(model.viewTagIds(activeView)):
    model.outputs[id].focusedWindow = focus
  model.affinities.del(id)
  model.affinityOrder.keepItIf(it != id)

proc validate*(model: PolicyModel) =
  if model.settings.viewCount < 1 or model.settings.viewCount > 9 or
      model.settings.outerGap < 0 or model.settings.innerGap < 0 or
      model.settings.viewportOffset < 0:
    fail("policy settings are invalid")
  if not model.windows.validateDense() or not model.columns.validateDense() or
      not model.views.validateDense() or not model.tags.validateDense() or
      not model.outputs.validateDense():
    fail("policy dense entity index is invalid")
  if model.outputOrder.len != model.outputs.len or
      model.windowOrder.len != model.windows.len or
      model.columnOrder.len != model.columns.len:
    fail("policy indexes and ordered identities diverged")
  if model.outputs.len > 0 and model.activeOutput notin model.outputs:
    fail("policy active output is invalid")
  for id in model.windows.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.windows:
      fail("policy window counter is invalid")
  for id in model.columns.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.columns:
      fail("policy column counter is invalid")
  for id in model.views.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.views:
      fail("policy view counter is invalid")
  for id in model.tags.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.tags:
      fail("policy tag counter is invalid")
  for id in model.outputs.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.outputs:
      fail("policy output counter is invalid")
  var seenViews = initHashSet[ViewId]()
  for outputId in model.outputOrder:
    let output = model.outputs[outputId]
    if output.id != outputId or output.bounds.width <= 0 or output.bounds.height <= 0 or
        output.views.len == 0 or output.activeView notin output.views:
      fail("policy output is invalid")
    for viewId in output.views:
      if viewId notin model.views or viewId in seenViews or
          model.viewTagIds(viewId).len == 0 or
          model.views[viewId].preferredOutput == nullOutputId:
        fail("policy view is invalid")
      var seenViewTags = initHashSet[TagId]()
      for tagId in model.viewTagIds(viewId):
        if tagId notin model.tags or tagId in seenViewTags:
          fail("policy view tag membership is invalid")
        seenViewTags.incl(tagId)
      seenViews.incl(viewId)
    if output.focusedWindow != nullWindowId:
      if output.focusedWindow notin model.windows:
        fail("policy output focus is invalid")
      let focus = model.windows[output.focusedWindow]
      if focus.homeOutput != outputId or not focus.capabilities.focusable or
          not model.windowTagIds(focus.id).intersects(
            model.viewTagIds(output.activeView)
          ) or focus.minimized:
        fail("policy output focus is invalid")
    if output.focusHistory.len > maxFocusHistory:
      fail("policy focus history is excessive")
    var seenFocus = initHashSet[WindowId]()
    for windowId in output.focusHistory:
      if windowId notin model.windows or windowId in seenFocus or
          model.windows[windowId].homeOutput != outputId:
        fail("policy focus history is invalid")
      seenFocus.incl(windowId)
  if seenViews.len != model.views.len:
    fail("policy contains a detached view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.id != windowId or window.homeOutput notin model.outputs or
        window.preferredOutput == nullOutputId or window.column notin model.columns or
        model.windowTagIds(windowId).len == 0 or
        uint32(window.heightScale) < uint32(minimumScale):
      fail("policy window is invalid")
    var seenWindowTags = initHashSet[TagId]()
    for tagId in model.windowTagIds(windowId):
      if tagId notin model.tags or tagId in seenWindowTags:
        fail("policy window tag membership is invalid")
      seenWindowTags.incl(tagId)
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
    if window.floating and
        not model.outputs[window.homeOutput].bounds.contains(window.floatingGeometry):
      fail("floating window geometry is invalid")
    if (window.fullscreen and window.maximized) or
        (window.minimized and (window.fullscreen or window.maximized)):
      fail("policy presentation state is invalid")
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
  if model.windowTags.len != model.windows.len or model.viewTags.len != model.views.len:
    fail("policy tag relationship indexes diverged")
  var seenSlots = initHashSet[uint32]()
  for tagId, tag in model.tags.pairs:
    if tag.id != tagId or tag.slot == 0 or tag.slot > maxTagBits or tag.slot in seenSlots:
      fail("policy tag entity is invalid")
    seenSlots.incl(tag.slot)
  if model.minimizedOrder.len > maxMinimizedHistory:
    fail("minimized history is excessive")
  var seenMinimized = initHashSet[WindowId]()
  for windowId in model.minimizedOrder:
    if windowId notin model.windows or windowId in seenMinimized or
        not model.windows[windowId].minimized:
      fail("minimized history is invalid")
    seenMinimized.incl(windowId)
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
  if previousOrder > model.counters.disconnects:
    fail("output disconnect counter is invalid")
