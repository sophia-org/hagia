import std/[sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ../entities/window_ops

## Transient placement and output adoption. Reads geometry, decides where a
## window belongs, and calls the entity layer to record it.

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
    let width = model.columns[source].width
    model.columns[source].windows.keepItIf(it != windowId)
    let target = model.addColumn(outputId)
    model.setColumnWidthExtent(target, width)
    model.columns[target].windows.add(windowId)
    model.windows[windowId].column = target
  model.windows[windowId].homeOutput = outputId
  model.windows[windowId].preferredOutput = outputId
  model.clearWindowFloating(windowId)
  let activeView = model.outputs[outputId].activeView
  model.windowTags[windowId] =
    model.windowTagIds(windowId).unionTags(model.viewTagIds(activeView))

proc placeLaunchOrigin*(
    model: var PolicyModel, windowId: WindowId, outputId: OutputId, tags: seq[TagId]
) =
  ## Open where the window that launched this one lives, without going there.
  ## Active output, active view, and focus are left exactly as they are: a
  ## launch that moved the operator would be a launch that interrupted them,
  ## and the window is found later rather than thrown in front of them now.
  if windowId notin model.windows or outputId notin model.outputs or tags.len == 0:
    return
  # A token outlives the place it names. A dynamic workspace can be pruned once
  # its last window leaves, so the tags a context was minted against may be
  # gone by the time a child arrives holding it. That is an ordinary placement,
  # not a failure: membership in a tag that no longer exists would not survive
  # validation.
  for tag in tags:
    if tag notin model.tags:
      return
  model.adoptWindowOutput(windowId, outputId)
  model.setWindowOriginTags(windowId, tags)

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
  model.setWindowTransientGeometry(windowId, geometry)
