import std/options

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

proc clamp(value, minimum, maximum: int32): int32 =
  result = value
  if minimum > 0:
    result = max(result, minimum)
  if maximum > 0:
    result = min(result, maximum)

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
