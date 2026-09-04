import std/sequtils

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ../entities/focus_ops

import ./[placement]

## Focus movement across windows and outputs. Order comes from the queries
## layer; the move itself goes through focus_ops.

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

proc focusLast*(model: var PolicyModel, outputId: OutputId) =
  ## Return to the window focused before this one. The history an output keeps
  ## is bounded and may name windows that have since closed or moved away, so
  ## walk back until one is still a candidate here.
  if outputId notin model.outputs:
    fail("focus output does not exist")
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
  if eligible.len == 0:
    return
  let current = model.outputs[outputId].focusedWindow
  var index = model.outputs[outputId].focusHistory.high
  while index >= 0:
    let remembered = model.outputs[outputId].focusHistory[index]
    if remembered != current and remembered in eligible:
      model.setFocus(outputId, remembered)
      return
    dec index

proc focusedPosition(
    columns: openArray[seq[WindowId]], windowId: WindowId
): (int, int) =
  for columnIndex, windows in columns:
    let row = windows.find(windowId)
    if row >= 0:
      return (columnIndex, row)
  (-1, -1)

proc focusColumnRelative*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Move focus to the column beside this one. Columns are what the user sees
  ## as left and right, so this is the spatial counterpart to `focusRelative`,
  ## which walks every window in order regardless of where it sits.
  if outputId notin model.outputs:
    fail("focus output does not exist")
  let columns = model.visibleColumns(outputId)
  if columns.len == 0:
    return
  let (columnIndex, row) =
    columns.focusedPosition(model.outputs[outputId].focusedWindow)
  if columnIndex < 0:
    model.focusRelative(outputId, delta)
    return
  let target = columns[wrappedIndex(columnIndex, delta, columns.len)]
  model.setFocus(outputId, target[min(row, target.high)])

proc focusWithinColumnRelative*(
    model: var PolicyModel, outputId: OutputId, delta: int
) =
  ## Move focus up or down inside the focused column. A column of one window
  ## has nowhere to go, and staying put is the honest answer.
  if outputId notin model.outputs:
    fail("focus output does not exist")
  let columns = model.visibleColumns(outputId)
  if columns.len == 0:
    return
  let (columnIndex, row) =
    columns.focusedPosition(model.outputs[outputId].focusedWindow)
  if columnIndex < 0:
    model.focusRelative(outputId, delta)
    return
  let windows = columns[columnIndex]
  if windows.len < 2:
    return
  model.setFocus(outputId, windows[wrappedIndex(row, delta, windows.len)])
