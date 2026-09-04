import std/tables

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]
import ../entities/[column_ops, focus_ops, tag_ops]

import ./[placement, workspaces]

## Moving what is focused: inside a column, across columns, across views, and
## across outputs. Focus decides where the user looks; this decides what
## travels with them. Every position here is read from the columns a layout
## would actually draw, so a move lands where the user saw the window.

proc focusedPlace(columns: openArray[seq[WindowId]], windowId: WindowId): (int, int) =
  for columnIndex, windows in columns:
    let row = windows.find(windowId)
    if row >= 0:
      return (columnIndex, row)
  (-1, -1)

proc rawIndexFor(
    model: PolicyModel, columnId: ColumnId, visible: openArray[WindowId], position: int
): int =
  ## Translate a position among the windows a user can see into an index in the
  ## column's full membership, which may also hold floating windows no layout
  ## stacks.
  if position >= visible.len:
    model.columns[columnId].windows.len
  else:
    max(0, model.columns[columnId].windows.find(visible[position]))

proc moveWithinColumn*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Move the focused window up or down its own column. A column of one has
  ## nowhere to go.
  if outputId notin model.outputs:
    fail("movement output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused == nullWindowId:
    return
  let columns = model.visibleColumns(outputId)
  let (columnIndex, row) = columns.focusedPlace(focused)
  if columnIndex < 0 or columns[columnIndex].len < 2:
    return
  let windows = columns[columnIndex]
  model.swapWindowsInColumn(focused, windows[wrappedIndex(row, delta, windows.len)])

proc moveToAdjacentColumn*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Carry the focused window into the column beside it at the height it left
  ## from. At the far edge it becomes a new column on that side instead of
  ## wrapping, so a repeated press pushes a window out rather than cycling it
  ## back to where it started.
  if outputId notin model.outputs:
    fail("movement output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused == nullWindowId:
    return
  let columns = model.visibleColumns(outputId)
  let identities = model.visibleColumnIds(outputId)
  let (columnIndex, row) = columns.focusedPlace(focused)
  if columnIndex < 0:
    return
  let target = columnIndex + delta
  if target < 0 or target >= identities.len:
    if columns[columnIndex].len < 2:
      return
    let at =
      if delta < 0:
        columnIndex
      else:
        columnIndex + 1
    let created = model.insertColumnAt(outputId, at)
    model.moveWindowToColumnAt(focused, created, 0)
    return
  let destination = identities[target]
  model.moveWindowToColumnAt(
    focused, destination, model.rawIndexFor(destination, columns[target], row)
  )

proc moveColumnRelative*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Move the focused window's whole column sideways. Columns do not wrap: the
  ## leftmost column is already as far left as it goes.
  if outputId notin model.outputs:
    fail("movement output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused == nullWindowId:
    return
  let identities = model.visibleColumnIds(outputId)
  let current = identities.find(model.windows[focused].column)
  if current < 0:
    return
  model.moveColumnToIndex(identities[current], current + delta)

proc moveColumnToEdge*(model: var PolicyModel, outputId: OutputId, last: bool) =
  if outputId notin model.outputs:
    fail("movement output does not exist")
  let focused = model.outputs[outputId].focusedWindow
  if focused == nullWindowId:
    return
  let identities = model.visibleColumnIds(outputId)
  if identities.len == 0:
    return
  model.moveColumnToIndex(
    model.windows[focused].column, if last: identities.high else: 0
  )

proc focusColumnEdge*(model: var PolicyModel, outputId: OutputId, last: bool) =
  if outputId notin model.outputs:
    fail("focus output does not exist")
  let columns = model.visibleColumns(outputId)
  if columns.len == 0:
    return
  let windows =
    if last:
      columns[^1]
    else:
      columns[0]
  model.setFocus(outputId, windows[0])

proc promoteFocusedColumn*(model: var PolicyModel, outputId: OutputId) =
  ## Triad's zoom. Hagia's master is whatever sits first, so promoting means
  ## moving the focused window's column to the front rather than swapping two
  ## windows between fixed roles.
  model.moveColumnToEdge(outputId, last = false)

proc moveFocusedToViewRelative*(
    model: var PolicyModel, outputId: OutputId, delta: int
) =
  ## Send the focused window to the neighbouring view and follow it, which is
  ## what the numbered move-to-view actions already do.
  if outputId notin model.outputs:
    fail("movement output does not exist")
  let views = model.outputs[outputId].views
  let current = views.find(model.outputs[outputId].activeView)
  if views.len < 2 or current < 0:
    return
  model.moveFocusedToViewSlot(outputId, wrappedIndex(current, delta, views.len) + 1)

proc swapWithViewSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  ## Trade the windows of the active view with those of another slot, so two
  ## workspaces can exchange contents without moving windows one at a time. A
  ## window that belongs to both views counts as being here and travels there.
  if outputId notin model.outputs or slot < 1 or slot > model.outputs[outputId].views.len:
    fail("view slot is outside the active profile")
  let active = model.outputs[outputId].activeView
  let target = model.outputs[outputId].views[slot - 1]
  if target == active:
    return
  let activeTags = model.viewTagIds(active)
  let targetTags = model.viewTagIds(target)
  var here, there: seq[WindowId]
  for windowId in model.windowOrder:
    if model.windows[windowId].homeOutput != outputId or
        windowId in model.scratchpadRestore:
      continue
    let tags = model.windowTagIds(windowId)
    if tags.intersects(activeTags):
      here.add(windowId)
    elif tags.intersects(targetTags):
      there.add(windowId)
  for windowId in here:
    model.setWindowTagIds(windowId, targetTags)
  for windowId in there:
    model.setWindowTagIds(windowId, activeTags)

proc moveViewToOutputRelative*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Send the active view's windows to the next output. Views belong to an
  ## output in Hagia, so what travels is the window population; it lands in the
  ## same slot on the far side and that slot becomes active there.
  if outputId notin model.outputs:
    fail("movement output does not exist")
  if model.outputOrder.len < 2:
    return
  let sourceIndex = model.outputOrder.find(outputId)
  let target =
    model.outputOrder[wrappedIndex(sourceIndex, delta, model.outputOrder.len)]
  let slot = model.outputs[outputId].views.find(model.outputs[outputId].activeView)
  if slot < 0 or slot >= model.outputs[target].views.len:
    return
  let sourceTags = model.viewTagIds(model.outputs[outputId].activeView)
  let targetView = model.outputs[target].views[slot]
  let targetTags = model.viewTagIds(targetView)
  var travelling: seq[WindowId]
  for windowId in model.windowOrder:
    if model.windows[windowId].homeOutput == outputId and
        windowId notin model.scratchpadRestore and
        model.windowTagIds(windowId).intersects(sourceTags):
      travelling.add(windowId)
  if travelling.len == 0:
    return
  model.activateView(target, targetView)
  for windowId in travelling:
    model.adoptWindowOutput(windowId, target)
    model.setWindowTagIds(windowId, targetTags)
