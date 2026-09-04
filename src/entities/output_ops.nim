import std/[options, sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, queries, values]

import ./[tag_ops, view_ops]

## Output lifecycle, focus assignment, and reconnect affinity.

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
    model.views[viewId] =
      ViewData(id: viewId, preferredOutput: id, layout: model.settings.layoutCycle[0])
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
