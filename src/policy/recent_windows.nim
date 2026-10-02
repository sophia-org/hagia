import std/[options, tables]

import ../types/[core, model, overview, recent_windows]
import ../state/queries
import ./overview

## Pure switcher layout: one horizontal strip of previews on the active output,
## sized as niri sizes them (Triad's port has the same arithmetic). Each window
## keeps its aspect; the strip centres when it fits and otherwise scrolls so the
## selection stays clear of the edges.

proc windowSizes(
    model: PolicyModel, physicalBounds: openArray[(OutputId, Rect)]
): Table[WindowId, Rect] =
  ## The size each window has on its workspace. The active workspace wins
  ## because that is the size the operator last saw.
  for workspace in model.overviewWorkspaces(physicalBounds):
    for placement in workspace.placements:
      if workspace.active or placement.window notin result:
        result[placement.window] = placement.geometry

proc previewSize(source: Rect, maxWidth, maxHeight: int64): (int32, int32) =
  ## The smallest of three scales, kept as fractions: fit the width bound, fit
  ## the height bound, and never more than half size.
  var width = int64(source.width)
  var height = int64(source.height)
  if width <= recentWindowsTinySize or height <= recentWindowsTinySize:
    width = recentWindowsFallbackWidth
    height = recentWindowsFallbackHeight
  var numerator = 1'i64
  var denominator = recentWindowsMaxScaleDivisor
  if maxWidth * denominator < numerator * width:
    numerator = maxWidth
    denominator = width
  if maxHeight * denominator < numerator * height:
    numerator = maxHeight
    denominator = height
  (
    int32(max(1'i64, width * numerator div denominator)),
    int32(max(1'i64, height * numerator div denominator)),
  )

proc clipped(rect, bounds: Rect): Rect =
  let left = max(int64(rect.x), int64(bounds.x))
  let top = max(int64(rect.y), int64(bounds.y))
  let right = min(int64(rect.x) + rect.width, int64(bounds.x) + bounds.width)
  let bottom = min(int64(rect.y) + rect.height, int64(bounds.y) + bounds.height)
  if right > left and bottom > top:
    Rect(
      x: int32(left),
      y: int32(top),
      width: int32(right - left),
      height: int32(bottom - top),
    )
  else:
    Rect()

proc recentWindowStrip*(
    model: PolicyModel, physicalBounds: openArray[(OutputId, Rect)] = []
): Option[RecentWindowStrip] =
  let switcher = model.recentWindows
  if not switcher.active or not switcher.visible:
    return none(RecentWindowStrip)
  let output = model.output(model.activeOutput)
  if output.isNone:
    return none(RecentWindowStrip)
  var bounds = output.get().bounds
  for (physicalOutput, physical) in physicalBounds:
    if physicalOutput == model.activeOutput:
      bounds = physical
      break
  if bounds.width <= 0 or bounds.height <= 0:
    return none(RecentWindowStrip)
  let sizes = model.windowSizes(physicalBounds)
  let maxHeight = min(
    int64(recentWindowsMaxHeight), int64(bounds.height) div recentWindowsMaxScaleDivisor
  )
  let maxWidth = maxHeight * bounds.width div bounds.height
  let gap = 2'i64 * (recentWindowsPadding + 2) + 16
  var sized: seq[(WindowId, int32, int32)]
  var total = 0'i64
  for windowId in switcher.candidates:
    let source = sizes.getOrDefault(windowId, Rect())
    let (width, height) = previewSize(source, maxWidth, maxHeight)
    if sized.len > 0:
      total += gap
    total += width
    sized.add((windowId, width, height))
  var start: int64
  if total <= int64(bounds.width) - 2 * recentWindowsStrut:
    start = int64(bounds.x) + (int64(bounds.width) - total) div 2
  else:
    # Centre the selection, then keep both strip ends at least a strut inside.
    var offset = 0'i64
    for index in 0 ..< switcher.selected:
      offset += int64(sized[index][1]) + gap
    let selectedCentre = offset + int64(sized[switcher.selected][1]) div 2
    start = int64(bounds.x) + int64(bounds.width) div 2 - selectedCentre
    start = min(start, int64(bounds.x) + recentWindowsStrut)
    start = max(start, int64(bounds.x) + bounds.width - recentWindowsStrut - total)
  var strip = RecentWindowStrip(output: model.activeOutput, bounds: bounds)
  var x = start
  for index, (windowId, width, height) in sized:
    let geometry = Rect(
      x: int32(x),
      y: int32(int64(bounds.y) + (int64(bounds.height) - height) div 2),
      width: width,
      height: height,
    )
    strip.previews.add(RecentWindowPreview(window: windowId, geometry: geometry))
    if index == switcher.selected:
      strip.highlight = Rect(
        x: geometry.x - recentWindowsPadding,
        y: geometry.y - recentWindowsPadding,
        width: geometry.width + 2 * recentWindowsPadding,
        height: geometry.height + 2 * recentWindowsPadding,
      ).clipped(bounds)
    x += int64(width) + gap
  some(strip)
