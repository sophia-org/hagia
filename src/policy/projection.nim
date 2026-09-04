import std/[math, options, sequtils]

import ../types/[core, model, projection]
import ./[entity_store, state]

proc clamp(value, minimum, maximum: int32): int32 =
  result = value
  if minimum > 0:
    result = max(result, minimum)
  if maximum > 0:
    result = min(result, maximum)

proc scaledExtent(base: int32, scale: Scale): int32 =
  if base <= 0:
    return 0
  let scaled = int64(base) * int64(uint32(scale)) div int64(uint32(scaleOne))
  if scaled > int64(high(int32)):
    return high(int32)
  int32(scaled)

proc automaticScale(columnCount: int): Scale =
  scaleFromRatio(1, uint32(max(1, columnCount)))

proc insetExtent(extent, gap: int32): int32 =
  let value = int64(extent) - int64(max(0'i32, gap)) * 2
  if value <= 0:
    return 0
  if value > int64(high(int32)):
    return high(int32)
  int32(value)

proc appendFloating(
    model: PolicyModel,
    outputId: OutputId,
    eligible: openArray[WindowId],
    projection: var LogicalOutputProjection,
) =
  for windowId in eligible:
    let window = model.windows[windowId]
    if not window.floating:
      continue
    projection.placements.add(
      LogicalPlacement(
        window: windowId,
        geometry: window.floatingGeometry,
        requestedWidth: window.floatingGeometry.width.clamp(
          window.constraints.minWidth, window.constraints.maxWidth
        ),
        requestedHeight: window.floatingGeometry.height.clamp(
          window.constraints.minHeight, window.constraints.maxHeight
        ),
      )
    )

proc selectFocus(
    model: PolicyModel,
    output: OutputData,
    eligible: openArray[WindowId],
    projection: var LogicalOutputProjection,
) =
  if output.focusedWindow in eligible and
      model.windows[output.focusedWindow].capabilities.focusable:
    projection.focus = output.focusedWindow
  else:
    for windowId in eligible:
      if model.windows[windowId].capabilities.focusable:
        projection.focus = windowId
        break

proc projectScroller*(
    model: PolicyModel,
    affectedOutputs: openArray[OutputId],
    outerGap: int32 = 0,
    innerGap: int32 = 0,
    viewportOffset: int32 = 0,
): seq[LogicalOutputProjection] =
  model.validate()
  let safeOuterGap = max(0'i32, outerGap)
  let safeInnerGap = max(0'i32, innerGap)
  for outputId in affectedOutputs:
    let output = model.output(outputId)
    if output.isNone:
      raise newException(PolicyStateError, "projection output does not exist")
    let eligible =
      model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
    var columns: seq[(ColumnData, seq[WindowId])]
    for columnId in model.tiledColumnIds(outputId):
      let windows = model.columnWindows(columnId, eligible)
      if windows.len > 0:
        columns.add((model.columns[columnId], windows))

    var projection = LogicalOutputProjection(output: outputId)
    if columns.len == 0:
      model.appendFloating(outputId, eligible, projection)
      model.selectFocus(output.get(), eligible, projection)
      result.add(projection)
      continue
    let bounds = output.get().bounds
    let usableWidth = bounds.width.insetExtent(safeOuterGap)
    let usableHeight = bounds.height.insetExtent(safeOuterGap)
    if usableWidth == 0 or usableHeight == 0:
      raise newException(PolicyStateError, "output gaps consume the viewport")

    var positions: seq[int32]
    var widths: seq[int32]
    var virtualX = 0'i64
    var focusedColumn = -1
    var allAutomatic = true
    for item in columns:
      if item[0].widthScale != autoScale:
        allAutomatic = false
        break
    let horizontalGaps = int64(safeInnerGap) * int64(columns.len - 1)
    let automaticWidth =
      if allAutomatic and horizontalGaps < int64(usableWidth):
        int32((int64(usableWidth) - horizontalGaps) div int64(columns.len))
      else:
        0'i32
    for index, item in columns:
      let (column, windows) = item
      let width =
        if allAutomatic:
          if automaticWidth <= 0:
            raise newException(PolicyStateError, "column gaps consume the viewport")
          if index + 1 == columns.len:
            int32(int64(usableWidth) - virtualX)
          else:
            automaticWidth
        else:
          let scale =
            if column.widthScale == autoScale:
              automaticScale(columns.len)
            else:
              column.widthScale
          max(1'i32, usableWidth.scaledExtent(scale))
      if virtualX > int64(high(int32)):
        raise newException(PolicyStateError, "scroller extent is excessive")
      positions.add(int32(virtualX))
      widths.add(width)
      virtualX += int64(width) + int64(safeInnerGap)
      if output.get().focusedWindow in windows:
        focusedColumn = index

    var targetOffset = max(0'i32, viewportOffset)
    if focusedColumn >= 0:
      let left = positions[focusedColumn] - targetOffset
      let right = int64(left) + int64(widths[focusedColumn])
      if left < 0 or right > int64(usableWidth):
        let center =
          int64(positions[focusedColumn]) + int64(widths[focusedColumn]) div 2
        let target = max(0'i64, center - int64(usableWidth) div 2)
        targetOffset = int32(min(target, int64(high(int32))))
    projection.viewportOffset = targetOffset

    for index, item in columns:
      let (_, windows) = item
      let x64 =
        int64(bounds.x) + int64(safeOuterGap) + int64(positions[index]) -
        int64(targetOffset)
      if x64 < int64(low(int32)) or x64 > int64(high(int32)):
        raise newException(PolicyStateError, "scroller position is excessive")
      let x = int32(x64)
      let totalGaps = int64(windows.len - 1) * int64(safeInnerGap)
      if totalGaps >= int64(usableHeight):
        raise newException(PolicyStateError, "window gaps consume the column")
      let stackHeight = int32(int64(usableHeight) - totalGaps)
      if stackHeight < int32(windows.len):
        raise newException(PolicyStateError, "output is too short for the column")
      var totalScale = 0'u64
      for windowId in windows:
        totalScale += uint64(uint32(model.windows[windowId].heightScale))
      var y = int64(bounds.y) + int64(safeOuterGap)
      for windowIndex, windowId in windows:
        let window = model.windows[windowId]
        let height =
          if windowIndex + 1 == windows.len:
            int32(int64(bounds.y) + int64(safeOuterGap) + int64(usableHeight) - y)
          else:
            int32(
              int64(stackHeight) * int64(uint32(window.heightScale)) div
                int64(totalScale)
            )
        let width = widths[index]
        projection.placements.add(
          LogicalPlacement(
            window: windowId,
            geometry: Rect(x: x, y: int32(y), width: width, height: height),
            requestedWidth:
              width.clamp(window.constraints.minWidth, window.constraints.maxWidth),
            requestedHeight:
              height.clamp(window.constraints.minHeight, window.constraints.maxHeight),
          )
        )
        y += int64(height) + int64(safeInnerGap)
    model.appendFloating(outputId, eligible, projection)
    model.selectFocus(output.get(), eligible, projection)
    result.add(projection)

proc tiledWindows(
    model: PolicyModel, outputId: OutputId, eligible: openArray[WindowId]
): seq[WindowId] =
  for columnId in model.columnOrder:
    let column = model.columns[columnId]
    if column.homeOutput != outputId:
      continue
    for windowId in column.windows:
      if windowId in eligible and not model.windows[windowId].floating:
        result.add(windowId)

proc appendPlacement(
    model: PolicyModel,
    windowId: WindowId,
    geometry: Rect,
    projection: var LogicalOutputProjection,
) =
  let window = model.windows[windowId]
  projection.placements.add(
    LogicalPlacement(
      window: windowId,
      geometry: geometry,
      requestedWidth:
        geometry.width.clamp(window.constraints.minWidth, window.constraints.maxWidth),
      requestedHeight: geometry.height.clamp(
        window.constraints.minHeight, window.constraints.maxHeight
      ),
    )
  )

proc usableBounds(bounds: Rect, outerGap: int32): Rect =
  let gap = max(0'i32, outerGap)
  result = Rect(
    x: bounds.x + gap,
    y: bounds.y + gap,
    width: bounds.width.insetExtent(gap),
    height: bounds.height.insetExtent(gap),
  )
  if result.width <= 0 or result.height <= 0:
    raise newException(PolicyStateError, "output gaps consume the viewport")

proc gridDimensions(count: int): tuple[columns, rows: int] =
  if count <= 0:
    return (0, 0)
  result.columns = int(ceil(sqrt(float64(count))))
  result.rows = int(ceil(float64(count) / float64(result.columns)))

proc stackColumn(
    model: PolicyModel,
    windows: openArray[WindowId],
    area: Rect,
    gap: int32,
    projection: var LogicalOutputProjection,
) =
  ## Share one rectangle vertically between windows, giving the last the
  ## remainder so rounding never leaves a gap the layout did not ask for.
  if windows.len == 0:
    return
  let gaps = int64(gap) * int64(windows.len - 1)
  if gaps >= int64(area.height):
    raise newException(PolicyStateError, "tile gaps consume the stack")
  let baseHeight = int32((int64(area.height) - gaps) div windows.len)
  if baseHeight <= 0:
    raise newException(PolicyStateError, "tile stack is too short for its windows")
  var y = area.y
  for index, windowId in windows:
    let height =
      if index == windows.high:
        area.y + area.height - y
      else:
        baseHeight
    model.appendPlacement(
      windowId, Rect(x: area.x, y: y, width: area.width, height: height), projection
    )
    y += height + gap

proc projectNative(
    model: PolicyModel, outputId: OutputId, mode: LayoutMode, outerGap, innerGap: int32
): LogicalOutputProjection =
  let output = model.outputs[outputId]
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
  let tiled = model.tiledWindows(outputId, eligible)
  let bounds = output.bounds.usableBounds(outerGap)
  let gap = max(0'i32, innerGap)
  result.output = outputId
  case mode
  of LayoutMode.scroller, LayoutMode.verticalScroller:
    raise newException(PolicyStateError, "scrolling layout entered native projection")
  of LayoutMode.tile:
    let masterCount = max(1, min(model.settings.masterCount, tiled.len))
    if tiled.len <= masterCount:
      model.stackColumn(tiled, bounds, gap, result)
    elif tiled.len > 0:
      if gap >= bounds.width:
        raise newException(PolicyStateError, "tile gap consumes the viewport")
      let masterWidth =
        max(1'i32, (bounds.width - gap).scaledExtent(model.settings.masterRatio))
      let stackWidth = bounds.width - gap - masterWidth
      if stackWidth <= 0:
        raise newException(PolicyStateError, "tile master consumes the viewport")
      model.stackColumn(
        tiled[0 ..< masterCount],
        Rect(x: bounds.x, y: bounds.y, width: masterWidth, height: bounds.height),
        gap,
        result,
      )
      model.stackColumn(
        tiled[masterCount .. ^1],
        Rect(
          x: bounds.x + masterWidth + gap,
          y: bounds.y,
          width: stackWidth,
          height: bounds.height,
        ),
        gap,
        result,
      )
  of LayoutMode.grid:
    let dimensions = gridDimensions(tiled.len)
    if dimensions.columns > 0:
      let horizontalGaps = int64(gap) * int64(dimensions.columns - 1)
      let verticalGaps = int64(gap) * int64(dimensions.rows - 1)
      if horizontalGaps >= int64(bounds.width) or verticalGaps >= int64(bounds.height):
        raise newException(PolicyStateError, "grid gaps consume the viewport")
      let width = int32((int64(bounds.width) - horizontalGaps) div dimensions.columns)
      let height = int32((int64(bounds.height) - verticalGaps) div dimensions.rows)
      for index, windowId in tiled:
        let column = index mod dimensions.columns
        let row = index div dimensions.columns
        let cellWidth =
          if column + 1 == dimensions.columns:
            bounds.width - int32(column) * (width + gap)
          else:
            width
        let cellHeight =
          if row + 1 == dimensions.rows:
            bounds.height - int32(row) * (height + gap)
          else:
            height
        model.appendPlacement(
          windowId,
          Rect(
            x: bounds.x + int32(column) * (width + gap),
            y: bounds.y + int32(row) * (height + gap),
            width: cellWidth,
            height: cellHeight,
          ),
          result,
        )
  of LayoutMode.monocle:
    if tiled.len > 0:
      let selected =
        if output.focusedWindow in tiled:
          output.focusedWindow
        else:
          tiled[0]
      model.appendPlacement(selected, bounds, result)
  model.appendFloating(outputId, eligible, result)
  var visible: seq[WindowId]
  for placement in result.placements:
    visible.add(placement.window)
  model.selectFocus(output, visible, result)

proc transpose(rect: Rect): Rect =
  Rect(x: rect.y, y: rect.x, width: rect.height, height: rect.width)

proc projectVerticalScroller(
    model: PolicyModel, outputId: OutputId, outerGap, innerGap, viewportOffset: int32
): LogicalOutputProjection =
  var transposed = model.clone()
  transposed.outputs[outputId].bounds = transposed.outputs[outputId].bounds.transpose()
  for windowId in transposed.windowOrder:
    if transposed.windows[windowId].homeOutput != outputId:
      continue
    let constraints = transposed.windows[windowId].constraints
    transposed.windows[windowId].constraints = SizeConstraints(
      minWidth: constraints.minHeight,
      minHeight: constraints.minWidth,
      maxWidth: constraints.maxHeight,
      maxHeight: constraints.maxWidth,
    )
    transposed.windows[windowId].floatingGeometry =
      transposed.windows[windowId].floatingGeometry.transpose()
  result = transposed.projectScroller([outputId], outerGap, innerGap, viewportOffset)[0]
  for placement in result.placements.mitems:
    placement.geometry = placement.geometry.transpose()
    swap(placement.requestedWidth, placement.requestedHeight)

proc projectLayout*(
    model: PolicyModel,
    affectedOutputs: openArray[OutputId],
    outerGap: int32 = 0,
    innerGap: int32 = 0,
    viewportOffset: int32 = 0,
): seq[LogicalOutputProjection] =
  model.validate()
  for outputId in affectedOutputs:
    if outputId notin model.outputs:
      raise newException(PolicyStateError, "projection output does not exist")
    let mode = model.views[model.outputs[outputId].activeView].layout
    case mode
    of LayoutMode.scroller:
      result.add(
        model.projectScroller([outputId], outerGap, innerGap, viewportOffset)[0]
      )
    of LayoutMode.verticalScroller:
      result.add(
        model.projectVerticalScroller(outputId, outerGap, innerGap, viewportOffset)
      )
    of LayoutMode.tile, LayoutMode.grid, LayoutMode.monocle:
      result.add(model.projectNative(outputId, mode, outerGap, innerGap))
