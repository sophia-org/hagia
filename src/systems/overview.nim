import std/options

import ../types/[core, model, overview]
import ../state/[model, queries, values]
import ../entities/[focus_ops, output_ops, tab_tree_ops]
import ./[focus, workspaces]

proc selectOverview*(model: var PolicyModel, selection: OverviewSelection) =
  ## Selection is atomic even if a window or view disappeared while the
  ## overview was visible. Transport validates the publication generation.
  let output = model.output(selection.output)
  if output.isNone or selection.view notin output.get().views:
    fail("overview workspace no longer belongs to the output")
  var candidate = model.clone()
  candidate.activateView(selection.output, selection.view)
  candidate.setActiveOutput(selection.output)
  if selection.window == nullWindowId:
    if candidate.output(selection.output).get().focusedWindow == nullWindowId:
      candidate.focusRelative(selection.output, 1)
  else:
    candidate.setFocus(selection.output, selection.window)
    candidate.focusTabWindow(selection.output, selection.window)
  candidate.validate()
  model = candidate
