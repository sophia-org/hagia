import std/options

import ../types/[core, model, overview]
import ../state/[model, queries, values]
import ../entities/[focus_ops, output_ops, tab_tree_ops]
import ../entities/overview_ops
import ../policy/overview
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

proc openOverview*(model: var PolicyModel, outputId: OutputId) =
  let output = model.output(outputId)
  if output.isNone:
    fail("overview output is unavailable")
  for workspace in model.overviewWorkspaces():
    if workspace.output == outputId and workspace.view == output.get().activeView:
      model.setOverviewSelection(
        OverviewSelection(
          output: outputId, view: workspace.view, window: workspace.focus
        )
      )
      return
  fail("overview has no active workspace")

proc confirmOverview*(model: var PolicyModel) =
  if not model.overview.active:
    return
  model.selectOverview(model.overview.selection)
  model.clearOverview()

proc entryWindow(workspace: OverviewWorkspace, direction: OverviewDirection): WindowId =
  if workspace.navigation.len == 0:
    return nullWindowId
  if workspace.layout in {LayoutMode.monocle, LayoutMode.deck}:
    let index = if direction == OverviewDirection.up: workspace.navigation.high else: 0
    return workspace.navigation[index].window
  var best = 0
  for index in 1 ..< workspace.navigation.len:
    let rect = workspace.navigation[index].geometry
    let previous = workspace.navigation[best].geometry
    let y = int64(rect.y) * 2 + rect.height
    let previousY = int64(previous.y) * 2 + previous.height
    if (direction == OverviewDirection.up and y > previousY) or
        (direction != OverviewDirection.up and y < previousY) or
        (y == previousY and rect.x < previous.x):
      best = index
  workspace.navigation[best].window

proc navigateOverview*(
    model: var PolicyModel, direction: OverviewDirection, workspaceOnly = false
) =
  if not model.overview.active:
    return
  let selection = model.overview.selection
  var workspaces: seq[OverviewWorkspace]
  var current = -1
  for workspace in model.overviewWorkspaces():
    if workspace.output == selection.output and
        (workspace.active or workspace.navigation.len != 0):
      if workspace.view == selection.view:
        current = workspaces.len
      workspaces.add(workspace)
  if current < 0:
    model.clearOverview()
    return
  let workspace = workspaces[current]
  if not workspaceOnly:
    var selected = -1
    for index, target in workspace.navigation:
      if target.window == selection.window:
        selected = index
        break
    var next = -1
    if selected >= 0:
      let origin = workspace.navigation[selected].geometry
      let horizontal = direction in {OverviewDirection.left, OverviewDirection.right}
      let backwards = direction in {OverviewDirection.left, OverviewDirection.up}
      if workspace.layout == LayoutMode.monocle:
        let offset = selected + (if backwards: -1 else: 1)
        if offset >= 0 and offset < workspace.navigation.len:
          next = offset
      else:
        # Deck-like stacks share geometry. Walk their stable placement order
        # before considering a different spatial neighbor.
        let offset = selected + (if backwards: -1 else: 1)
        if offset >= 0 and offset < workspace.navigation.len and
            workspace.navigation[offset].geometry == origin:
          model.setOverviewSelection(
            OverviewSelection(
              output: selection.output,
              view: selection.view,
              window: workspace.navigation[offset].window,
            )
          )
          return
        var best = (high(int64), high(int64))
        for index, target in workspace.navigation:
          if index == selected:
            continue
          let rect = target.geometry
          let dx = int64(rect.x) * 2 + rect.width - int64(origin.x) * 2 - origin.width
          let dy = int64(rect.y) * 2 + rect.height - int64(origin.y) * 2 - origin.height
          let primary = (if horizontal: dx else: dy) * (if backwards: -1 else: 1)
          if primary <= 0:
            continue
          let score = (abs(if horizontal: dy else: dx), primary)
          if score < best:
            best = score
            next = index
    if next >= 0:
      model.setOverviewSelection(
        OverviewSelection(
          output: selection.output,
          view: selection.view,
          window: workspace.navigation[next].window,
        )
      )
      return
  if direction in {OverviewDirection.up, OverviewDirection.down}:
    let offset = if direction == OverviewDirection.up: -1 else: 1
    let next = workspaces[(current + offset + workspaces.len) mod workspaces.len]
    model.setOverviewSelection(
      OverviewSelection(
        output: next.output, view: next.view, window: next.entryWindow(direction)
      )
    )
