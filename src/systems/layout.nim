import ../policy/entity_store
import ../types/[core, model]
import ../state/values
import ../entities/window_ops
import ../entities/tab_tree_ops

## Layout cycling and column and window sizing.

proc cycleLayout*(model: var PolicyModel, outputId: OutputId, delta = 1) =
  if outputId notin model.outputs or model.settings.layoutCycle.len == 0:
    fail("layout cycle target is invalid")
  let viewId = model.outputs[outputId].activeView
  let current = model.settings.layoutCycle.find(model.views[viewId].layout)
  let index =
    if current < 0:
      0
    else:
      wrappedIndex(current, delta, model.settings.layoutCycle.len)
  model.views[viewId].layout = model.settings.layoutCycle[index]

proc setLayout*(model: var PolicyModel, outputId: OutputId, layout: LayoutMode) =
  ## Select a layout outright. Cycling reaches every mode eventually; a direct
  ## binding reaches one now, which is what a user with a key per layout wants.
  if outputId notin model.outputs:
    fail("layout target output does not exist")
  model.views[model.outputs[outputId].activeView].layout = layout
  model.syncTabTrees()

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

proc adjustMasterCount*(model: var PolicyModel, delta: int) =
  ## How many windows share the master area. Bounded, and clamped rather than
  ## wrapped: asking for fewer than one master is asking for no layout.
  model.settings.masterCount =
    max(1, min(maxMasterCount, model.settings.masterCount + delta))

proc adjustMasterRatio*(model: var PolicyModel, delta: int) =
  ## How much width the master area takes. The step is the same fifth-of-a-
  ## twentieth used for column and window scaling, so every size key in Hagia
  ## moves by the same amount.
  let adjusted = adjustedScale(model.settings.masterRatio, delta)
  model.settings.masterRatio =
    if uint32(adjusted) < uint32(minMasterRatio):
      minMasterRatio
    elif uint32(adjusted) > uint32(maxMasterRatio):
      maxMasterRatio
    else:
      adjusted

proc adjustGaps*(model: var PolicyModel, delta: int) =
  ## Widen or narrow both gaps together by the configured step. Adjusting gaps
  ## turns them back on, because asking for wider gaps while they are hidden
  ## otherwise does nothing visible.
  let step = int64(model.settings.gapStep) * int64(delta)
  let outer = int64(model.settings.outerGap) + step
  let inner = int64(model.settings.innerGap) + step
  model.settings.outerGap = int32(max(0'i64, min(int64(maxGap), outer)))
  model.settings.innerGap = int32(max(0'i64, min(int64(maxGap), inner)))
  model.settings.gapsEnabled = true

proc toggleGaps*(model: var PolicyModel) =
  ## Hide the configured gaps without forgetting them.
  model.settings.gapsEnabled = not model.settings.gapsEnabled

proc toggleColumnMaximized*(model: var PolicyModel, outputId: OutputId) =
  ## Give the focused column the whole width, or hand it back to the share a
  ## layout would choose. This is a decision about a column; `toggleMaximized`
  ## is a decision about one window, and the two are not the same key.
  if outputId notin model.outputs:
    fail("column maximize output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let columnId = model.windows[windowId].column
  model.setColumnWidthScale(
    columnId,
    if model.columns[columnId].widthScale == scaleOne: autoScale else: scaleOne,
  )
