import std/[options, sequtils, tables]

import ../types/[core, model, projection]
import ../state/[model, queries, values]
import ../entities/[column_ops, window_ops]
import ./projection

proc overviewCoordinate(value: int64): int32 =
  if value < low(int32).int64 or value > high(int32).int64:
    raise newException(PolicyStateError, "overview strip position is excessive")
  int32(value)

proc projectExpandedStrip(
    model: PolicyModel, outputId: OutputId, outerGap, innerGap: int32, physical: Rect
): LogicalOutputProjection =
  let output = model.output(outputId).get()
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.window(it).get().minimized)
  let workArea = model.layoutWorkArea(outputId)
  let fullArea =
    if physical.width > 0 and physical.height > 0: physical else: output.bounds
  var expanded = initTable[WindowId, Rect]()
  var candidate = model.clone()
  for columnId in model.tiledColumnIds(outputId):
    let windows = model.columnWindows(columnId, eligible)
    var after = columnId
    for windowId in windows:
      let window = model.window(windowId).get()
      if not window.fullscreen and not window.maximized:
        continue
      expanded[windowId] = if window.fullscreen: fullArea else: workArea
      # Niri expels an expanded tile to the right of a shared column. These
      # columns exist only in the preview clone; confirmation still names the
      # original window, and ordinary layout never sees the extraction.
      if windows.len > 1:
        let index = candidate.tiledColumnIds(outputId).find(after)
        let separate = candidate.insertColumnAt(outputId, index + 1)
        candidate.moveWindowToColumnAt(windowId, separate, 0)
        after = separate
      candidate.setWindowPresentation(windowId, false, false, false)
  if expanded.len == 0:
    return model.projectScroller(
      [outputId], outerGap, innerGap, model.settings.viewportOffset, physical
    )[0]

  result = candidate.projectScroller(
    [outputId], outerGap, innerGap, candidate.settings.viewportOffset, physical
  )[0]
  var ordinary = initTable[WindowId, LogicalPlacement]()
  for placement in result.placements:
    if not model.window(placement.window).get().floating:
      ordinary[placement.window] = placement
  result.placements.setLen(0)
  let gap = max(0'i32, innerGap)
  let outer = model.scrollerOuterGap(outerGap)
  let viewWidth = (int64(workArea.width) - int64(outer) * 2).overviewCoordinate()
  let origin = int64(workArea.x) + outer
  let ordinaryOffset = result.viewportOffset
  var cameraMapped = false
  var ordinaryEnd = 0'i64
  var translatedOffset = int64(ordinaryOffset)
  var position = origin
  for columnId in candidate.tiledColumnIds(outputId):
    let windows = candidate.columnWindows(columnId, eligible)
    if windows.len == 0:
      continue
    let first = windows[0]
    let ordinaryRect = ordinary[first].geometry
    let ordinaryX = int64(ordinaryRect.x) + ordinaryOffset - origin
    ordinaryEnd = ordinaryX + ordinaryRect.width
    if not cameraMapped:
      # The camera is a point in the ordinary strip. Translate at the column
      # containing it before comparing it with any expanded-strip geometry.
      translatedOffset = int64(ordinaryOffset) + position - origin - ordinaryX
      cameraMapped = int64(ordinaryOffset) < ordinaryEnd
    let expansion = expanded.getOrDefault(first)
    let width =
      if expansion.width > 0:
        expansion.width
      else:
        ordinary[first].geometry.width
    for windowId in windows:
      var placement = ordinary[windowId]
      if expansion.width > 0:
        placement.geometry = expansion
        placement.maximized = model.window(windowId).get().maximized
      placement.geometry.x = position.overviewCoordinate()
      result.placements.add(placement)
    position += int64(width) + gap
    discard position.overviewCoordinate()
  if not cameraMapped:
    translatedOffset = int64(ordinaryOffset) + position - origin - gap - ordinaryEnd

  # Reveal against the expanded strip, never the narrower ordinary camera.
  # Fullscreen includes reserved edges; maximized aligns to the work area.
  let focused = model.presentationFocusRoot(output, eligible)
  var offset = translatedOffset.overviewCoordinate()
  for placement in result.placements:
    if placement.window != focused:
      continue
    let columnX = (int64(placement.geometry.x) - origin).overviewCoordinate()
    let expansion = expanded.getOrDefault(focused)
    if expansion.width > 0:
      offset = (int64(placement.geometry.x) - expansion.x).overviewCoordinate()
    elif model.settings.centerFocusedColumn == CenterFocusedColumn.always or
        model.view(output.activeView).get().cameraIntent == CameraIntent.centerFocused:
      offset = scrollerCenteredOffset(viewWidth, columnX, placement.geometry.width)
    else:
      offset =
        scrollerViewOffset(offset, viewWidth, columnX, placement.geometry.width, gap)
    break
  for placement in result.placements.mitems:
    placement.geometry.x = (int64(placement.geometry.x) - offset).overviewCoordinate()
  # Only placements and focus leave this preview pass. Its camera metadata
  # must never be settled into the ordinary workspace.
  result.viewportOffset = offset
  model.appendFloatingPlacements(outputId, eligible, result, physical)
  if result.placements.anyIt(it.window == output.focusedWindow):
    result.focus = output.focusedWindow

proc projectOverviewScroller*(
    model: PolicyModel, outputId: OutputId, outerGap, innerGap: int32, physical: Rect
): LogicalOutputProjection =
  if model.view(model.output(outputId).get().activeView).get().layout ==
      LayoutMode.verticalScroller:
    let transposed = model.transposedForVerticalScroller(outputId)
    result = transposed.projectExpandedStrip(
      outputId, outerGap, innerGap, physical.transpose()
    )
    for placement in result.placements.mitems:
      placement.geometry = placement.geometry.transpose()
      swap(placement.requestedWidth, placement.requestedHeight)
  else:
    result = model.projectExpandedStrip(outputId, outerGap, innerGap, physical)
  model.orderPresentationLayers(result)
