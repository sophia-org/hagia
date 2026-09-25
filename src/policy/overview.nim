import std/options

import ../types/[core, model, overview]
import ../state/[model, queries]
import ../systems/[focus, workspaces]
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
      if candidate.output(outputId).get().focusedWindow == nullWindowId:
        candidate.focusRelative(outputId, 1)
      let projected = candidate.projectLayout(
        [outputId],
        outerGap,
        innerGap,
        candidate.settings.viewportOffset,
        physicalBounds,
      )[0]
      result.add(
        OverviewWorkspace(
          output: outputId,
          view: viewId,
          bounds: output.bounds,
          active: viewId == output.activeView,
          focus: projected.focus,
          placements: projected.placements,
        )
      )
