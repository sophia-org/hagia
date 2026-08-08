import std/[options, tables]

import ./[state, types]

type
  LogicalPlacement* = object
    window*: WindowId
    geometry*: Rect
    requestedWidth*, requestedHeight*: int32

  LogicalOutputProjection* = object
    output*: OutputId
    placements*: seq[LogicalPlacement]
    focus*: WindowId
    viewportOffset*: int32

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
    let eligible = model.eligibleWindows(outputId)
    var columns: seq[(ColumnData, seq[WindowId])]
    for columnId in model.columnOrder:
      let column = model.columns[columnId]
      if column.homeOutput != outputId:
        continue
      var windows: seq[WindowId]
      for windowId in column.windows:
        if windowId in eligible:
          windows.add(windowId)
      if windows.len > 0:
        columns.add((column, windows))

    var projection = LogicalOutputProjection(output: outputId)
    if columns.len == 0:
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
    let currentFocus = output.get().focusedWindow
    if currentFocus in eligible and model.windows[currentFocus].capabilities.focusable:
      projection.focus = currentFocus
    else:
      for windowId in eligible:
        if model.windows[windowId].capabilities.focusable:
          projection.focus = windowId
          break
    result.add(projection)

proc projectColumns*(
    model: PolicyModel, affectedOutputs: openArray[OutputId]
): seq[LogicalOutputProjection] =
  model.validate()
  for outputId in affectedOutputs:
    let output = model.output(outputId)
    if output.isNone:
      raise newException(PolicyStateError, "projection output does not exist")
    let windows = model.eligibleWindows(outputId)
    var projection = LogicalOutputProjection(output: outputId)
    if windows.len > 0:
      let count = int32(windows.len)
      let columnWidth = output.get().bounds.width div count
      if columnWidth <= 0:
        raise newException(PolicyStateError, "output is too narrow for columns")
      for index, windowId in windows:
        let window = model.window(windowId).get()
        let x = output.get().bounds.x + columnWidth * int32(index)
        let width =
          if index + 1 == windows.len:
            output.get().bounds.x + output.get().bounds.width - x
          else:
            columnWidth
        projection.placements.add(
          LogicalPlacement(
            window: windowId,
            geometry: Rect(
              x: x,
              y: output.get().bounds.y,
              width: width,
              height: output.get().bounds.height,
            ),
            requestedWidth:
              width.clamp(window.constraints.minWidth, window.constraints.maxWidth),
            requestedHeight: output.get().bounds.height.clamp(
                window.constraints.minHeight, window.constraints.maxHeight
              ),
          )
        )
      let currentFocus = output.get().focusedWindow
      if currentFocus in windows and
          model.window(currentFocus).get().capabilities.focusable:
        projection.focus = currentFocus
      else:
        for windowId in windows:
          if model.window(windowId).get().capabilities.focusable:
            projection.focus = windowId
            break
    result.add(projection)
