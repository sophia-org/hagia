import std/options

import ../policy/entity_store
import ../types/[core, model]
import ../state/[model, queries, values]
import ../entities/settings_ops
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

proc alongAxisGeometry(
    model: PolicyModel, outputId: OutputId
): tuple[strip: ScrollerStrip, proportionBase, innerGap: int32, vertical: bool] =
  ## The strip the operator is actually looking at, plus the base a proportion
  ## is taken of.
  ##
  ## A vertical scroller is the same machine turned on its side, so this reads
  ## the strip through the same transpose the projection lays out. Reading the
  ## untransposed model would measure widths on a view that scrolls by height,
  ## and every caller here would then reason about space that is not there.
  let (outerGap, innerGap) = model.effectiveGaps()
  let vertical = model.scrollsVertically(outputId)
  let viewed =
    if vertical:
      model.transposedForVerticalScroller(outputId)
    else:
      model
  let strip = viewed.scrollerStrip(outputId, outerGap, innerGap)
  (strip, max(1'i32, strip.usableWidth - innerGap), innerGap, vertical)

proc adjustFocusedColumn*(model: var PolicyModel, outputId: OutputId, delta: int) =
  if outputId notin model.outputs:
    fail("column output does not exist")
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  let column = model.windows[window].column
  # A step is proportional, so a column holding fixed pixels converts on the
  # first press. Either way the step
  # starts from what the column is showing: reading an unset width as 1.0
  # instead once jumped a half-width column past the whole viewport. Setting a
  # width also stops the column being full width; the two are separate facts
  # and this one is now explicit.
  let resolved =
    if model.columns[column].fullWidth:
      proportionExtent(scaleOne)
    elif model.columns[column].width.kind == LayoutExtentKind.automatic:
      model.alongAxisDefaultExtent(outputId)
    else:
      model.columns[column].width
  let current =
    if resolved.kind == LayoutExtentKind.proportion:
      # Already a proportion, so step it as one. Resolving to pixels and back
      # would round the width the column has to the nearest one the strip can
      # state, and a key held down would drift.
      resolved.scale
    else:
      let geometry = model.alongAxisGeometry(outputId)
      scaleForWidth(
        geometry.proportionBase,
        geometry.innerGap,
        resolved.extentPixels(geometry.proportionBase, geometry.innerGap),
      )
  model.setColumnWidthScale(column, adjustedScale(current, delta, current))
  model.setColumnFullWidth(column, false)

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
  ## Change ordinary spacing by the configured step, preserving struts. Adjusting gaps
  ## turns them back on, because asking for wider gaps while they are hidden
  ## otherwise does nothing visible.
  let step = int64(model.settings.gapStep) * int64(delta)
  model.adjustGapSizes(step)

proc toggleGaps*(model: var PolicyModel) =
  ## Hide the configured gaps without forgetting them.
  model.setGapsEnabled(not model.settings.gapsEnabled)

proc toggleColumnMaximized*(model: var PolicyModel, outputId: OutputId) =
  let output = model.output(outputId)
  if output.isNone:
    fail("column maximize output does not exist")
  let window = model.window(output.get().focusedWindow)
  if window.isNone:
    return
  let column = model.column(window.get().column)
  if column.isNone:
    fail("column maximize column does not exist")
  model.setColumnFullWidth(column.get().id, not column.get().fullWidth)

proc cycleColumnWidthPreset*(model: var PolicyModel, outputId: OutputId, delta: int) =
  ## Step the focused column through the configured width presets.
  ##
  ## A column sitting on none of them is placed by width rather than by
  ## lookup: forwards goes to the first preset wider than what it is showing,
  ## backwards to the last one narrower. Matching by equality instead meant a
  ## column that had been grown, shrunk, maximised, or simply never given a
  ## width matched nothing and restarted from the end of the list, which is
  ## the one place the key should feel continuous. No presets configured
  ## means no key to press.
  if outputId notin model.outputs:
    fail("column preset output does not exist")
  if model.alongAxisPresets(outputId).len == 0:
    return
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let columnId = model.windows[windowId].column
  let geometry = model.alongAxisGeometry(outputId)
  let presets = model.alongAxisPresets(outputId)
  var resolved: seq[int32]
  for preset in presets:
    resolved.add(preset.extentPixels(geometry.proportionBase, geometry.innerGap))
  # Pixels rather than scales, because a proportion and a fixed extent share
  # no common scale to compare in.
  let showing = columnRequestedWidth(
    model.columns[columnId],
    model.alongAxisDefaultExtent(outputId),
    geometry.proportionBase,
    geometry.innerGap,
  )
  let current = resolved.find(showing)
  var target: int
  if current >= 0:
    target = wrappedIndex(current, delta, resolved.len)
  elif delta >= 0:
    target = 0
    for index, width in resolved:
      if width > showing:
        target = index
        break
  else:
    target = resolved.high
    for index in countdown(resolved.high, 0):
      if resolved[index] < showing:
        target = index
        break
  # Stored as written, so a fixed preset stays fixed.
  model.setColumnWidthExtent(columnId, presets[target])
  model.setColumnFullWidth(columnId, false)

proc expandFocusedColumn*(model: var PolicyModel, outputId: OutputId) =
  ## Grow the focused column into the space its neighbours are not using.
  ##
  ## Only the columns wholly on screen count, and the focused one must be
  ## among them: widening a column that cannot be seen would move the strip
  ## under the operator for no visible reason. A column already at full width
  ## has nothing to expand into, and one with nothing beside it toggles full
  ## width instead, so the key always does something and always has a way
  ## back.
  if outputId notin model.outputs:
    fail("column expand output does not exist")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let columnId = model.windows[windowId].column
  if model.columns[columnId].fullWidth:
    return
  let geometry = model.alongAxisGeometry(outputId)
  let strip = geometry.strip
  let innerGap = geometry.innerGap
  if strip.focused < 0:
    return
  let activeView = model.outputs[outputId].activeView
  let offset =
    if geometry.vertical:
      model.views[activeView].viewportOffsetY
    else:
      model.views[activeView].viewportOffset
  var taken = 0'i64
  var holdsFocus = false
  var neighbours = 0
  for index, position in strip.positions:
    if int64(position) < int64(offset) + int64(innerGap):
      continue
    if int64(offset) + int64(strip.usableWidth) <
        int64(position) + int64(strip.widths[index]) + int64(innerGap):
      break
    if index == strip.focused:
      holdsFocus = true
    else:
      inc neighbours
    taken += int64(strip.widths[index]) + int64(innerGap)
  if not holdsFocus:
    return
  if neighbours == 0:
    model.columns[columnId].fullWidth = true
    return
  let available = int64(strip.usableWidth) - int64(innerGap) - taken
  if available <= 0:
    return
  let grown = int64(strip.widths[strip.focused]) + available
  # Recorded as pixels. A column expanded into its
  # neighbours' space was given a width in pixels; rounding that through a
  # proportion only to resolve it back loses exactly the width that was asked
  # for, and makes the column rescale on an output change it had no part in.
  model.setColumnWidthExtent(
    columnId, fixedExtent(int32(max(1'i64, min(int64(maxFixedExtent), grown))))
  )
