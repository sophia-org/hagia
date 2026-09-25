import std/options

import ../types/[core, model, overview, projection]
import ../state/[model, queries, values]
import ../systems/[focus, workspaces]
import ../entities/focus_ops
import ./projection

proc overviewWorkspaces*(
    model: PolicyModel, physicalBounds: openArray[(OutputId, Rect)] = []
): seq[OverviewWorkspace] =
  ## Each view is projected on a private candidate. Workspace activation may
  ## prune dynamic views and restore focus, but previewing must spend neither
  ## the committed camera nor the operator's current focus.
  model.validate()
  let (outerGap, innerGap) = model.effectiveGaps()
  for outputId in model.outputIds():
    let output = model.output(outputId).get()
    for viewId in output.views:
      var candidate = model.clone()
      candidate.activateView(outputId, viewId)
      if model.overview.active and model.overview.selection.output == outputId and
          model.overview.selection.view == viewId and
          model.overview.selection.window != nullWindowId:
        candidate.setFocus(outputId, model.overview.selection.window)
      if candidate.output(outputId).get().focusedWindow == nullWindowId:
        candidate.focusRelative(outputId, 1)
      let projected = candidate.projectLayout(
        [outputId],
        outerGap,
        innerGap,
        candidate.settings.viewportOffset,
        physicalBounds,
      )[0]
      var workspace = OverviewWorkspace(
        output: outputId,
        view: viewId,
        bounds: output.bounds,
        active: viewId == output.activeView,
        focus: projected.focus,
        placements: projected.placements,
        layout: candidate.view(viewId).get().layout,
      )
      if workspace.layout == LayoutMode.monocle:
        workspace.navigation.setLen(0)
        for windowId in candidate.eligibleWindows(outputId):
          let window = candidate.window(windowId).get()
          if not window.minimized and window.capabilities.focusable:
            workspace.navigation.add(
              LogicalPlacement(window: windowId, geometry: output.bounds)
            )
      else:
        workspace.navigation.setLen(0)
        for placement in workspace.placements:
          if candidate.window(placement.window).get().capabilities.focusable:
            workspace.navigation.add(placement)
      result.add(workspace)

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

proc overviewPreviews*(
    model: PolicyModel, physicalBounds: openArray[(OutputId, Rect)] = []
): seq[OverviewPreview] =
  if not model.overview.active:
    return
  let allWorkspaces = model.overviewWorkspaces(physicalBounds)
  for outputId in model.outputIds():
    var bounds = model.output(outputId).get().bounds
    for (physicalOutput, physical) in physicalBounds:
      if physicalOutput == outputId:
        bounds = physical
        break
    var workspaces: seq[OverviewWorkspace]
    var center = 0
    for workspace in allWorkspaces:
      if workspace.output == outputId and
          (workspace.active or workspace.placements.len != 0):
        if workspace.active:
          center = workspaces.len
        workspaces.add(workspace)
    if model.overview.selection.output == outputId:
      for index, workspace in workspaces:
        if workspace.view == model.overview.selection.view:
          center = index
          break
    # Triad's vertical workspace strip: the selected workspace is centered,
    # adjacent previews remain clipped to their own output. Fixed-point sizing
    # makes repeated projections independent of floating-point rounding.
    let width = max(1'i32, int32(int64(bounds.width) * 3 div 5))
    let height = max(1'i32, int32(int64(bounds.height) * 3 div 5))
    let gap = max(1'i32, int32(int64(bounds.height) * 3 div 50))
    for index, workspace in workspaces:
      let top =
        int64(bounds.y) + (int64(bounds.height) - height) div 2 +
        int64(index - center) * (int64(height) + gap)
      if top >= int64(bounds.y) + bounds.height or top + height <= int64(bounds.y):
        continue
      if top < int64(low(int32)) or top + height > int64(high(int32)):
        raise newException(PolicyStateError, "overview preview position is excessive")
      let geometry = Rect(
        x: bounds.x + (bounds.width - width) div 2,
        y: int32(top),
        width: width,
        height: height,
      )
      var preview = OverviewPreview(
        workspace: workspace, geometry: geometry, clip: geometry.clipped(bounds)
      )
      var left = int64(workspace.bounds.x)
      var topSource = int64(workspace.bounds.y)
      var right = left + workspace.bounds.width
      var bottom = topSource + workspace.bounds.height
      for placement in workspace.placements:
        left = min(left, int64(placement.geometry.x))
        topSource = min(topSource, int64(placement.geometry.y))
        right = max(right, int64(placement.geometry.x) + placement.geometry.width)
        bottom = max(bottom, int64(placement.geometry.y) + placement.geometry.height)
      let sourceWidth = max(1'i64, right - left)
      let sourceHeight = max(1'i64, bottom - topSource)
      let fitWidth = min(int64(width), int64(height) * sourceWidth div sourceHeight)
      let fitHeight = min(int64(height), int64(width) * sourceHeight div sourceWidth)
      let originX = int64(geometry.x) + (width - fitWidth) div 2
      let originY = int64(geometry.y) + (height - fitHeight) div 2
      for placement in workspace.placements:
        let source = placement.geometry
        var placed = placement
        placed.geometry = Rect(
          x: int32(originX + (int64(source.x) - left) * fitWidth div sourceWidth),
          y: int32(originY + (int64(source.y) - topSource) * fitHeight div sourceHeight),
          width: max(1'i32, int32(int64(source.width) * fitWidth div sourceWidth)),
          height: max(1'i32, int32(int64(source.height) * fitHeight div sourceHeight)),
        )
        if placed.geometry.clipped(preview.clip).width > 0:
          preview.placements.add(placed)
      result.add(preview)
