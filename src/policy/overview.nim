import std/options

import ../types/[core, model, overview, projection]
import ../state/[model, queries, values]
import ../systems/[focus, workspaces]
import ../entities/[focus_ops, window_ops]
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
      let layout = candidate.view(viewId).get().layout
      # Only the preview camera follows selection. The committed workspace and
      # client focus remain unchanged until confirmation.
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
        layout: layout,
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
        var navigation = projected.placements
        if layout in {LayoutMode.scroller, LayoutMode.verticalScroller}:
          # Expanded windows are output-anchored and can share a center with
          # the selected column. Navigate their underlying strip positions.
          var ordinary = candidate.clone()
          var expanded = false
          for windowId in candidate.eligibleWindows(outputId):
            let window = candidate.window(windowId).get()
            if not window.floating and (window.fullscreen or window.maximized):
              ordinary.setWindowPresentation(windowId, false, false, window.minimized)
              expanded = true
          if expanded:
            navigation =
              ordinary.projectLayout(
                [outputId],
                outerGap,
                innerGap,
                ordinary.settings.viewportOffset,
                physicalBounds,
              )[0].placements
        for placement in navigation:
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
    # Niri scales the viewport by a fixed zoom, never by the number of windows.
    # The selected workspace is centered, with a tenth-preview-height gap.
    let width = max(1'i32, int32(int64(bounds.width) div overviewZoomDivisor))
    let height = max(1'i32, int32(int64(bounds.height) div overviewZoomDivisor))
    let gap = max(1'i32, height div overviewGapDivisor)
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
      # A horizontal strip may extend beyond its workspace frame, as in niri,
      # but never across an output or into the neighboring workspace row.
      let row = Rect(x: bounds.x, y: geometry.y, width: bounds.width, height: height)
      var preview = OverviewPreview(
        workspace: workspace, geometry: geometry, clip: row.clipped(bounds)
      )
      for placement in workspace.placements:
        let source = placement.geometry
        var placed = placement
        placed.geometry = Rect(
          x: int32(
            int64(geometry.x) + (int64(source.x) - bounds.x) div overviewZoomDivisor
          ),
          y: int32(
            int64(geometry.y) + (int64(source.y) - bounds.y) div overviewZoomDivisor
          ),
          width: max(1'i32, int32(int64(source.width) div overviewZoomDivisor)),
          height: max(1'i32, int32(int64(source.height) div overviewZoomDivisor)),
        )
        if placed.geometry.clipped(preview.clip).width > 0:
          preview.placements.add(placed)
      if model.overview.selection.output == outputId and
          model.overview.selection.view == workspace.view:
        # Selection must remain visible over an output-anchored fullscreen
        # neighbor. This is preview stacking, not ordinary client stacking.
        for index, placement in preview.placements:
          if placement.window == model.overview.selection.window:
            preview.placements.delete(index)
            preview.placements.add(placement)
            break
      result.add(preview)
