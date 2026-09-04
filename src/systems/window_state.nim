import std/sequtils

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ../entities/[column_ops, focus_ops, window_ops]

import ./focus

## Focused-window state toggles: fullscreen, maximize, minimize, floating, and
## the column consume and expel pair.

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
  ## Lift the focused window out of its stack into a column of its own, placed
  ## immediately to the right of the stack it left. Appending to the far end
  ## would throw the window across the whole scroller, and would disagree with
  ## `moveToAdjacentColumn`, which opens a column in place at the edge.
  let outputId = model.activeOutput
  if outputId notin model.outputs:
    fail("expel output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let source = model.windows[windowId].column
  if model.columns[source].windows.len == 1:
    return
  let created =
    model.insertColumnAt(outputId, model.visibleColumnIds(outputId).find(source) + 1)
  model.moveWindowToColumnAt(windowId, created, 0)

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
