import std/[math, options, sequtils, tables]

import ../types/[core, model, projection]
import ./[entity_store, state]
import ./tab_tree_projection
import ../entities/tab_tree_ops

proc clamp(value, minimum, maximum: int32): int32 =
  result = value
  if minimum > 0:
    result = max(result, minimum)
  if maximum > 0:
    result = min(result, maximum)

proc scrollerViewOffset*(
    currentOffset, viewWidth, columnX, columnWidth, gap: int32
): int32 =
  ## Where the camera goes so a column is on screen, following niri's rule
  ## rather than centring on every move.
  ##
  ## Three cases, in order. A column wider than the screen is left-aligned,
  ## because no offset shows all of it and its left edge is the useful one. A
  ## column already fully visible leaves the camera exactly where it is --
  ## this is the case that makes the view feel still, and centring on every
  ## focus change is what loses it. Otherwise the camera moves the shorter of
  ## the two distances that would reveal the column, so focus travel scrolls
  ## by a column rather than jumping half a screen.
  if viewWidth <= columnWidth:
    return columnX
  let padding = max(0'i32, min(gap, (viewWidth - columnWidth) div 2))
  let wantLeft = int64(columnX) - int64(padding)
  let wantRight = int64(columnX) + int64(columnWidth) + int64(padding)
  let viewLeft = int64(currentOffset)
  let viewRight = viewLeft + int64(viewWidth)
  if viewLeft <= wantLeft and wantRight <= viewRight:
    return currentOffset
  let distanceLeft = abs(viewLeft - wantLeft)
  let distanceRight = abs(viewRight - wantRight)
  let target =
    if distanceLeft <= distanceRight:
      wantLeft
    else:
      int64(columnX) + int64(columnWidth) + int64(padding) - int64(viewWidth)
  int32(max(low(int32).int64, min(target, high(int32).int64)))

proc scrollerCenteredOffset*(viewWidth, columnX, columnWidth: int32): int32 =
  ## Where the camera goes to put a column in the middle. A column at least as
  ## wide as the screen has no middle to find, so it is left-aligned instead.
  if viewWidth <= columnWidth:
    return columnX
  let target = int64(columnX) - (int64(viewWidth) - int64(columnWidth)) div 2
  int32(max(low(int32).int64, min(target, high(int32).int64)))

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
    var previousColumn = -1
    # The strip geometry is computed once, in one place, so an action that
    # reasons about what is on screen and the projection that draws it cannot
    # disagree about where the columns are.
    let strip = model.scrollerStrip(outputId, safeOuterGap, safeInnerGap)
    positions = strip.positions
    widths = strip.widths
    focusedColumn = strip.focused
    for index, item in columns:
      let (_, windows) = item
      # The column focus came from, for the overflow rule below. The most
      # recent entry that is not the focused window is where focus was before
      # this projection.
      if previousColumn < 0:
        for remembered in output.get().focusHistory:
          if remembered != output.get().focusedWindow and remembered in windows:
            previousColumn = index
            break

    # The camera carries over from the last projection rather than restarting
    # at the configured offset, which is what lets the strip stay where it was
    # scrolled to. Without it every projection recomputes from zero and the
    # view springs back the moment the focused column happens to fit.
    # Seeded from the view's own camera, not the configured offset, so the
    # strip resumes where this view left it.
    let activeView = output.get().activeView
    var targetOffset =
      if activeView in model.views:
        model.views[activeView].viewportOffset
      else:
        viewportOffset
    # A stored camera is clamped to the strip that exists now. The strip it
    # was stored against may have shrunk -- columns close, widths change --
    # and an offset pointing past it would place every column off screen and
    # could push a coordinate past what a placement can carry.
    let stripEnd =
      if strip.positions.len > 0:
        int64(strip.positions[^1]) + int64(strip.widths[^1])
      else:
        0'i64
    targetOffset = int32(max(-int64(usableWidth), min(int64(targetOffset), stripEnd)))
    if focusedColumn >= 0:
      let columnX = positions[focusedColumn]
      let columnWidth = widths[focusedColumn]
      # A lone column centres by behaving as though the mode were `always`,
      # which is how niri expresses the same option.
      let centering =
        if model.settings.alwaysCenterSingleColumn and columns.len <= 1:
          CenterFocusedColumn.always
        else:
          model.settings.centerFocusedColumn
      targetOffset =
        case centering
        of CenterFocusedColumn.always:
          scrollerCenteredOffset(usableWidth, columnX, columnWidth)
        of CenterFocusedColumn.never:
          scrollerViewOffset(
            targetOffset, usableWidth, columnX, columnWidth, safeInnerGap
          )
        of CenterFocusedColumn.onOverflow:
          # Centre only when the focused column cannot share the screen with
          # the column on the side focus arrived from, and only on a real move.
          # A projection that is merely redrawing the same focus reveals
          # without centring, which is what stops the view drifting on every
          # cycle. The neighbour is the target's, on the side travelled from —
          # not the column focus left, which is only the same thing for a
          # single step.
          if previousColumn < 0 or previousColumn == focusedColumn:
            scrollerViewOffset(
              targetOffset, usableWidth, columnX, columnWidth, safeInnerGap
            )
          else:
            let neighbour =
              if previousColumn > focusedColumn:
                min(focusedColumn + 1, columns.len - 1)
              else:
                max(focusedColumn - 1, 0)
            let spanLeft = min(columnX, positions[neighbour])
            let spanRight = max(
              int64(columnX) + int64(columnWidth),
              int64(positions[neighbour]) + int64(widths[neighbour]),
            )
            if spanRight - int64(spanLeft) + int64(safeInnerGap) * 2 <=
                int64(usableWidth):
              scrollerViewOffset(
                targetOffset, usableWidth, columnX, columnWidth, safeInnerGap
              )
            else:
              scrollerCenteredOffset(usableWidth, columnX, columnWidth)
    # A camera action asked for a position by name. It is resolved here
    # because this is the only place the strip geometry exists.
    if activeView in model.views:
      case model.views[activeView].cameraIntent
      of CameraIntent.none:
        discard
      of CameraIntent.centerFocused:
        if focusedColumn >= 0:
          targetOffset = scrollerCenteredOffset(
            usableWidth, positions[focusedColumn], widths[focusedColumn]
          )
      of CameraIntent.centerVisible:
        # The run of columns wholly on screen, taken as a block and centred.
        # It has to contain the focused column: centring a group that does not
        # would scroll the window being worked in off the edge.
        if focusedColumn >= 0:
          var leftmost = -1
          var taken = 0'i64
          var holdsFocus = false
          for index, position in positions:
            if int64(position) < int64(targetOffset) + int64(safeInnerGap):
              continue
            if leftmost < 0:
              leftmost = index
            if int64(targetOffset) + int64(usableWidth) <
                int64(position) + int64(widths[index]) + int64(safeInnerGap):
              break
            if index == focusedColumn:
              holdsFocus = true
            taken += int64(widths[index]) + int64(safeInnerGap)
          if holdsFocus and leftmost >= 0:
            let free = int64(usableWidth) - taken + int64(safeInnerGap)
            targetOffset = int32(
              max(
                int64(low(int32)),
                min(int64(high(int32)), int64(positions[leftmost]) - free div 2),
              )
            )
    projection.viewportOffset = targetOffset
    projection.cameraDecided = true

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

proc gridDimensions(count: int, vertical: bool): tuple[columns, rows: int] =
  ## A grid fills rows first and a vertical grid fills columns first, so the
  ## two orientations derive the same pair of dimensions from opposite ends.
  if count <= 0:
    return (0, 0)
  if vertical:
    result.rows = int(ceil(sqrt(float64(count))))
    result.columns = int(ceil(float64(count) / float64(result.rows)))
  else:
    result.columns = int(ceil(sqrt(float64(count))))
    result.rows = int(ceil(float64(count) / float64(result.columns)))

proc focusedFirst(windows: openArray[WindowId], focused: WindowId): seq[WindowId] =
  ## Put the focused window at the front, keeping the rest in their order. A
  ## deck shows one window of its stack, so which one leads is the whole point.
  for windowId in windows:
    if windowId == focused:
      result.add(windowId)
  for windowId in windows:
    if windowId != focused:
      result.add(windowId)

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

proc spiralSplit(area: Rect, side: int, ratio: Scale, gap: int32): (Rect, Rect) =
  ## One turn of the spiral: carve a window's rectangle off `area` on the named
  ## side and hand back what is left. Sides run left, top, right, bottom, so
  ## successive turns wind inward clockwise.
  if side == 0 or side == 2:
    let available = max(1'i32, area.width - gap)
    let first =
      if available <= 1:
        1'i32
      else:
        max(1'i32, min(available - 1, available.scaledExtent(ratio)))
    let second = max(1'i32, available - first)
    if side == 0:
      (
        Rect(x: area.x, y: area.y, width: first, height: area.height),
        Rect(x: area.x + first + gap, y: area.y, width: second, height: area.height),
      )
    else:
      (
        Rect(x: area.x + second + gap, y: area.y, width: first, height: area.height),
        Rect(x: area.x, y: area.y, width: second, height: area.height),
      )
  else:
    let available = max(1'i32, area.height - gap)
    let first =
      if available <= 1:
        1'i32
      else:
        max(1'i32, min(available - 1, available.scaledExtent(ratio)))
    let second = max(1'i32, available - first)
    if side == 1:
      (
        Rect(x: area.x, y: area.y, width: area.width, height: first),
        Rect(x: area.x, y: area.y + first + gap, width: area.width, height: second),
      )
    else:
      (
        Rect(x: area.x, y: area.y + second + gap, width: area.width, height: first),
        Rect(x: area.x, y: area.y, width: area.width, height: second),
      )

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
  # A mixed layout is a rule about which layout to run, not a geometry of its
  # own: a few windows read better as master and stack, more as a grid.
  let resolved =
    if mode == LayoutMode.tgmix:
      if tiled.len <= 3: LayoutMode.tile else: LayoutMode.grid
    else:
      mode
  case resolved
  of LayoutMode.scroller, LayoutMode.verticalScroller:
    raise newException(PolicyStateError, "scrolling layout entered native projection")
  of LayoutMode.frameTree, LayoutMode.notion, LayoutMode.splitTree, LayoutMode.dwindle:
    raise newException(PolicyStateError, "tab tree entered stateless projection")
  of LayoutMode.tgmix:
    raise newException(PolicyStateError, "mixed layout resolved to itself")
  of LayoutMode.spiral:
    # Each window but the last takes a slice off one side, and the remainder
    # winds inward. The first turn uses the master ratio, so the key that
    # widens a tile's master widens the spiral's largest pane too.
    var area = bounds
    for index, windowId in tiled:
      if index == tiled.high:
        model.appendPlacement(windowId, area, result)
        break
      let (taken, rest) = area.spiralSplit(index mod 4, model.settings.masterRatio, gap)
      model.appendPlacement(windowId, taken, result)
      area = rest
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
  of LayoutMode.grid, LayoutMode.verticalGrid:
    let vertical = mode == LayoutMode.verticalGrid
    let dimensions = gridDimensions(tiled.len, vertical)
    if dimensions.columns > 0:
      let horizontalGaps = int64(gap) * int64(dimensions.columns - 1)
      let verticalGaps = int64(gap) * int64(dimensions.rows - 1)
      if horizontalGaps >= int64(bounds.width) or verticalGaps >= int64(bounds.height):
        raise newException(PolicyStateError, "grid gaps consume the viewport")
      let width = int32((int64(bounds.width) - horizontalGaps) div dimensions.columns)
      let height = int32((int64(bounds.height) - verticalGaps) div dimensions.rows)
      for index, windowId in tiled:
        let column =
          if vertical:
            index div dimensions.rows
          else:
            index mod dimensions.columns
        let row =
          if vertical:
            index mod dimensions.rows
          else:
            index div dimensions.columns
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
  of LayoutMode.rightTile:
    # Tile mirrored: the stack takes the left, the master the right.
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
        tiled[masterCount .. ^1],
        Rect(x: bounds.x, y: bounds.y, width: stackWidth, height: bounds.height),
        gap,
        result,
      )
      model.stackColumn(
        tiled[0 ..< masterCount],
        Rect(
          x: bounds.x + stackWidth + gap,
          y: bounds.y,
          width: masterWidth,
          height: bounds.height,
        ),
        gap,
        result,
      )
  of LayoutMode.centerTile:
    # The master sits between two stacks, which the remaining windows join
    # alternately so both sides fill evenly.
    let masterCount = max(1, min(model.settings.masterCount, tiled.len))
    if tiled.len <= masterCount:
      model.stackColumn(tiled, bounds, gap, result)
    elif tiled.len > 0:
      var left, right: seq[WindowId]
      for index in masterCount .. tiled.high:
        if (index - masterCount) mod 2 == 0:
          left.add(tiled[index])
        else:
          right.add(tiled[index])
      let sideGaps = gap * (if right.len > 0: 2'i32 else: 1'i32)
      if sideGaps >= bounds.width:
        raise newException(PolicyStateError, "tile gap consumes the viewport")
      let masterWidth =
        max(1'i32, (bounds.width - sideGaps).scaledExtent(model.settings.masterRatio))
      let sideTotal = bounds.width - sideGaps - masterWidth
      if sideTotal <= 0:
        raise newException(PolicyStateError, "tile master consumes the viewport")
      let leftWidth =
        if right.len > 0:
          sideTotal div 2
        else:
          sideTotal
      let rightWidth = sideTotal - leftWidth
      model.stackColumn(
        left,
        Rect(x: bounds.x, y: bounds.y, width: leftWidth, height: bounds.height),
        gap,
        result,
      )
      let masterX = bounds.x + leftWidth + gap
      model.stackColumn(
        tiled[0 ..< masterCount],
        Rect(x: masterX, y: bounds.y, width: masterWidth, height: bounds.height),
        gap,
        result,
      )
      if right.len > 0:
        model.stackColumn(
          right,
          Rect(
            x: masterX + masterWidth + gap,
            y: bounds.y,
            width: rightWidth,
            height: bounds.height,
          ),
          gap,
          result,
        )
  of LayoutMode.deck:
    # A master area beside one shared rectangle every other window occupies.
    # Placements are ordered bottom to top, so the last window added is the one
    # on show; the focused window leads, which puts it in the master area.
    var ordered = focusedFirst(tiled, output.focusedWindow)
    let masterCount = max(1, min(model.settings.masterCount, ordered.len))
    if ordered.len <= masterCount:
      model.stackColumn(ordered, bounds, gap, result)
    elif ordered.len > 0:
      if gap >= bounds.width:
        raise newException(PolicyStateError, "deck gap consumes the viewport")
      let masterWidth =
        max(1'i32, (bounds.width - gap).scaledExtent(model.settings.masterRatio))
      let stackWidth = bounds.width - gap - masterWidth
      if stackWidth <= 0:
        raise newException(PolicyStateError, "deck master consumes the viewport")
      model.stackColumn(
        ordered[0 ..< masterCount],
        Rect(x: bounds.x, y: bounds.y, width: masterWidth, height: bounds.height),
        gap,
        result,
      )
      let shared = Rect(
        x: bounds.x + masterWidth + gap,
        y: bounds.y,
        width: stackWidth,
        height: bounds.height,
      )
      for index in masterCount .. ordered.high:
        model.appendPlacement(ordered[index], shared, result)
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

proc projectVerticalScroller(
    model: PolicyModel, outputId: OutputId, outerGap, innerGap, viewportOffset: int32
): LogicalOutputProjection =
  let transposed = model.transposedForVerticalScroller(outputId)
  result = transposed.projectScroller([outputId], outerGap, innerGap, viewportOffset)[0]
  for placement in result.placements.mitems:
    placement.geometry = placement.geometry.transpose()
    swap(placement.requestedWidth, placement.requestedHeight)

proc projectTabbed(
    model: PolicyModel, outputId: OutputId, outerGap, innerGap: int32
): LogicalOutputProjection =
  var prepared = model.clone()
  prepared.syncTabTrees()
  let output = prepared.outputs[outputId]
  let tree = prepared.tabTrees[output.activeView]
  let projected = tree.projectTabTree(
    output.activeView,
    output.bounds.usableBounds(outerGap),
    max(0'i32, innerGap),
    output.focusedWindow,
  )
  result.output = outputId
  result.tabGroups = projected.groups
  for placement in projected.placements:
    prepared.appendPlacement(placement.window, placement.geometry, result)
  let eligible =
    prepared.eligibleWindows(outputId).filterIt(not prepared.windows[it].minimized)
  prepared.appendFloating(outputId, eligible, result)
  let visible = result.placements.mapIt(it.window)
  prepared.selectFocus(output, visible, result)

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
    of LayoutMode.frameTree, LayoutMode.notion, LayoutMode.splitTree, LayoutMode.dwindle:
      result.add(model.projectTabbed(outputId, outerGap, innerGap))
    of LayoutMode.scroller:
      result.add(
        model.projectScroller([outputId], outerGap, innerGap, viewportOffset)[0]
      )
    of LayoutMode.verticalScroller:
      result.add(
        model.projectVerticalScroller(outputId, outerGap, innerGap, viewportOffset)
      )
    of LayoutMode.tile, LayoutMode.grid, LayoutMode.monocle, LayoutMode.centerTile,
        LayoutMode.rightTile, LayoutMode.verticalGrid, LayoutMode.deck,
        LayoutMode.spiral, LayoutMode.tgmix:
      result.add(model.projectNative(outputId, mode, outerGap, innerGap))
