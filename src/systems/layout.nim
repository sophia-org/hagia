import ../policy/entity_store
import ../types/[core, model]
import ../state/[queries, values]
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
  # A column that never chose a width is showing the configured default, so
  # that is where the first step starts from. Setting a width also stops the
  # column being full width; the two are separate facts and this one is now
  # explicit.
  model.setColumnWidthScale(
    column,
    adjustedScale(model.columns[column].widthScale, delta, model.defaultColumnScale()),
  )
  model.columns[column].fullWidth = false

proc adjustFocusedWindow*(model: var PolicyModel, outputId: OutputId, delta: int) =
  if outputId notin model.outputs:
    fail("window output does not exist")
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  model.setWindowHeightScale(
    window, adjustedScale(model.windows[window].heightScale, delta, scaleOne)
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
  let adjusted = adjustedScale(model.settings.masterRatio, delta, scaleOne)
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
  # A flag, not a width. Overwriting the width made maximising a one-way door:
  # it could only be undone by pressing the same key on the same column before
  # focus moved, and nothing else ever returned a column to its own width.
  model.columns[columnId].fullWidth = not model.columns[columnId].fullWidth

proc cycleColumnWidthPreset*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Step the focused column through the configured width presets.
  ##
  ## A column sitting on none of them is placed by width rather than by
  ## lookup: forwards goes to the first preset wider than what it is showing,
  ## backwards to the last one narrower. Matching by equality instead meant a
  ## column that had been grown, shrunk, maximised, or simply never given a
  ## width matched nothing and restarted from the end of the list, which is
  ## the one place the key should feel continuous. niri resolves it the same
  ## way. No presets configured means no key to press.
  if outputId notin model.outputs:
    fail("column preset output does not exist")
  if model.settings.columnWidthPresets.len == 0:
    return
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let columnId = model.windows[windowId].column
  var scales: seq[Scale]
  for percent in model.settings.columnWidthPresets:
    scales.add(scaleFromRatio(uint32(percent), 100))
  let showing =
    if model.columns[columnId].fullWidth:
      scaleOne
    elif model.columns[columnId].widthScale == autoScale:
      model.defaultColumnScale()
    else:
      model.columns[columnId].widthScale
  let current = scales.find(showing)
  var target: int
  if current >= 0:
    target = wrappedIndex(current, delta, scales.len)
  elif delta >= 0:
    target = 0
    for index, scale in scales:
      if uint32(scale) > uint32(showing):
        target = index
        break
  else:
    target = scales.high
    for index in countdown(scales.high, 0):
      if uint32(scales[index]) < uint32(showing):
        target = index
        break
  model.setColumnWidthScale(columnId, scales[target])
  model.columns[columnId].fullWidth = false
