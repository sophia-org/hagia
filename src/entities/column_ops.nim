import std/sequtils

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, queries, values]

## Column and in-column ordering. `window_ops` creates and destroys columns;
## this module decides where one sits and where a window sits inside it. Order
## is what a user reads as left to right, so it is state to maintain, not a
## detail of how a layout happens to draw.

proc outputColumnPositions(model: PolicyModel, outputId: OutputId): seq[int] =
  ## Where an output's columns sit in the shared order. Outputs interleave in
  ## `columnOrder`, so reordering one output's columns means permuting exactly
  ## these slots and leaving every other slot untouched.
  for index, columnId in model.columnOrder:
    if model.columns[columnId].homeOutput == outputId:
      result.add(index)

proc insertColumnAt*(model: var PolicyModel, outputId: OutputId, index: int): ColumnId =
  ## Create a column at a chosen place among an output's columns. `addColumn`
  ## appends, which is right for a window arriving and wrong for a split that
  ## has to land beside the column it came from.
  if outputId notin model.outputs:
    fail("column output does not exist")
  let positions = model.outputColumnPositions(outputId)
  let bounded = max(0, min(index, positions.len))
  result = model.allocateColumnId()
  model.columns[result] =
    ColumnData(id: result, homeOutput: outputId, preferredOutput: outputId)
  let at =
    if positions.len == 0:
      model.columnOrder.len
    elif bounded == positions.len:
      positions[^1] + 1
    else:
      positions[bounded]
  model.columnOrder.insert(result, at)

proc moveColumnToIndex*(model: var PolicyModel, columnId: ColumnId, index: int) =
  ## Reorder one column among its own output's columns. Every other output
  ## keeps the slots it held, because only this output's slots are rewritten.
  if columnId notin model.columns:
    fail("column does not exist")
  let outputId = model.columns[columnId].homeOutput
  var own = model.tiledColumnIds(outputId)
  let current = own.find(columnId)
  if current < 0:
    fail("column membership disagrees with its recorded output")
  let bounded = max(0, min(index, own.high))
  if bounded == current:
    return
  own.delete(current)
  own.insert(columnId, bounded)
  var next = 0
  for position in model.outputColumnPositions(outputId):
    model.columnOrder[position] = own[next]
    inc next

proc swapWindowsInColumn*(model: var PolicyModel, first, second: WindowId) =
  ## Exchange two windows' places in the column they share. A swap is a
  ## permutation of one sequence, so no index or membership can drift.
  if first notin model.windows or second notin model.windows:
    fail("column swap names a window that does not exist")
  if first == second:
    return
  let columnId = model.windows[first].column
  if model.windows[second].column != columnId:
    fail("column swap crosses two columns")
  let left = model.columns[columnId].windows.find(first)
  let right = model.columns[columnId].windows.find(second)
  if left < 0 or right < 0:
    fail("column membership disagrees with window records")
  model.columns[columnId].windows[left] = second
  model.columns[columnId].windows[right] = first

proc moveWindowToColumnAt*(
    model: var PolicyModel, windowId: WindowId, columnId: ColumnId, index: int
) =
  ## Positional counterpart of `moveWindowToColumn`, which always appends. A
  ## window arriving from the side should land at the height it left from, not
  ## at the bottom of the stack.
  if windowId notin model.windows or columnId notin model.columns:
    fail("window or column does not exist")
  if model.windows[windowId].homeOutput != model.columns[columnId].homeOutput:
    fail("column belongs to a different output")
  let source = model.windows[windowId].column
  model.columns[source].windows.keepItIf(it != windowId)
  let bounded = max(0, min(index, model.columns[columnId].windows.len))
  model.columns[columnId].windows.insert(windowId, bounded)
  model.windows[windowId].column = columnId
  if source != columnId and model.columns[source].windows.len == 0:
    model.columns.del(source)
    model.columnOrder.keepItIf(it != source)
