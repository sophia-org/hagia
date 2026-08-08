import std/[options, sequtils, sets, tables]

import ./types

type PolicyStateError* = object of CatchableError

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyStateError, message)

proc initPolicyModel*(): PolicyModel =
  PolicyModel()

proc tagForSlot*(slot: uint32): TagMask =
  if slot == 0 or slot > maxTagBits:
    fail("tag slot is outside Hagia's bounded mask")
  TagMask(1'u64 shl (slot - 1))

proc intersects*(left, right: TagMask): bool =
  (uint64(left) and uint64(right)) != 0

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

proc addView*(model: var PolicyModel, outputId: OutputId, tags: TagMask): ViewId =
  if tags == emptyTagMask:
    fail("a view must select at least one tag")
  if outputId notin model.outputs:
    fail("view output does not exist")
  result = model.allocateViewId()
  model.views[result] = ViewData(id: result, selectedTags: tags)
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
  model.windows[result] = WindowData(
    id: result,
    homeOutput: homeOutput,
    tags: activeView.get().selectedTags,
    capabilities: capabilities,
    constraints: constraints,
  )
  model.windowOrder.add(result)

proc removeWindow*(model: var PolicyModel, id: WindowId) =
  if id notin model.windows:
    return
  model.windows.del(id)
  model.windowOrder.keepItIf(it != id)
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == id:
      model.outputs[outputId].focusedWindow = nullWindowId

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

proc setWindowTags*(model: var PolicyModel, id: WindowId, tags: TagMask) =
  if tags == emptyTagMask:
    fail("a window must retain at least one tag")
  if id notin model.windows:
    fail("window does not exist")
  model.windows[id].tags = tags

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

proc removeOutput*(model: var PolicyModel, id, fallback: OutputId) =
  if id == fallback or id notin model.outputs or fallback notin model.outputs:
    fail("output migration is invalid")
  let removed = model.outputs[id]
  for viewId in removed.views:
    model.outputs[fallback].views.add(viewId)
  for windowId in model.windowOrder:
    if model.windows[windowId].homeOutput == id:
      model.windows[windowId].homeOutput = fallback
  if model.outputs[fallback].focusedWindow == nullWindowId and
      removed.focusedWindow != nullWindowId:
    model.outputs[fallback].focusedWindow = removed.focusedWindow
  model.outputs.del(id)
  model.outputOrder.keepItIf(it != id)

proc validate*(model: PolicyModel) =
  if model.outputOrder.len != model.outputs.len or
      model.windowOrder.len != model.windows.len:
    fail("policy indexes and ordered identities diverged")
  var seenViews = initHashSet[ViewId]()
  for outputId in model.outputOrder:
    let output = model.outputs[outputId]
    if output.id != outputId or output.bounds.width <= 0 or output.bounds.height <= 0 or
        output.views.len == 0 or output.activeView notin output.views:
      fail("policy output is invalid")
    for viewId in output.views:
      if viewId notin model.views or viewId in seenViews or
          model.views[viewId].selectedTags == emptyTagMask:
        fail("policy view is invalid")
      seenViews.incl(viewId)
  if seenViews.len != model.views.len:
    fail("policy contains a detached view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.id != windowId or window.homeOutput notin model.outputs or
        window.tags == emptyTagMask:
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
