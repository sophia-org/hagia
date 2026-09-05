import std/[sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ../entities/[focus_ops, group_ops]

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
  # Stepping past either end hands focus to the display on that side, when
  # there is one. Wrapping made the other monitor unreachable with the same
  # key that walks the strip, and sent the camera flying back across a strip
  # the operator was walking along. niri hands off the same way, which is
  # where the habit comes from.
  let next = columnIndex + delta
  if next < 0 or next >= columns.len:
    let adjacent = model.adjacentOutput(outputId, delta)
    if adjacent != nullOutputId and adjacent != outputId:
      model.activeOutput = adjacent
      if model.outputs[adjacent].focusedWindow == nullWindowId:
        model.focusRelative(adjacent, 1)
      return
    return
  let target = columns[next]
  # A column remembers its own active window; row matching is only the fallback.
  for index in countdown(model.outputs[outputId].focusHistory.high, 0):
    let remembered = model.outputs[outputId].focusHistory[index]
    if remembered in target:
      model.setFocus(outputId, remembered)
      return
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
  let target = row + delta
  if target >= 0 and target < windows.len:
    model.setFocus(outputId, windows[target])

proc groupFocusedWithNeighbour*(model: var PolicyModel, outputId: OutputId) =
  ## Join the focused window to the one after it in layout order, merging both
  ## windows' existing groups so grouping twice widens a group rather than
  ## splintering it.
  if outputId notin model.outputs:
    fail("group output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused == nullWindowId:
    return
  var visible: seq[WindowId]
  for windows in model.visibleColumns(outputId):
    visible.add(windows)
  let index = visible.find(focused)
  if index < 0 or visible.len < 2:
    return
  let neighbour = visible[wrappedIndex(index, 1, visible.len)]
  var members: seq[WindowId]
  for windowId in [focused, neighbour]:
    if windowId in model.groupOfWindow:
      for member in model.groups[model.groupOfWindow[windowId]].windows:
        if member notin members:
          members.add(member)
    elif windowId notin members:
      members.add(windowId)
  discard model.addGroup(members)
  model.setGroupActiveWindow(focused)

proc ungroupFocused*(model: var PolicyModel, outputId: OutputId) =
  if outputId notin model.outputs:
    fail("group output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused != nullWindowId:
    model.forgetGroupMembership(focused)

proc focusNextInGroup*(model: var PolicyModel, outputId: OutputId) =
  ## Step to the next window of the focused window's group. A window that is
  ## in no group has no group to step through, and staying put says so.
  if outputId notin model.outputs:
    fail("focus output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused == nullWindowId or focused notin model.groupOfWindow:
    return
  let windows = model.groups[model.groupOfWindow[focused]].windows
  let index = windows.find(focused)
  if index < 0 or windows.len < 2:
    return
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
  var step = 1
  while step < windows.len:
    let candidate = windows[wrappedIndex(index, step, windows.len)]
    if candidate in eligible:
      model.setGroupActiveWindow(candidate)
      model.setFocus(outputId, candidate)
      return
    inc step
