import ../types/[core, model]
import ../state/[queries, values]
import std/options

proc clearOverview*(model: var PolicyModel) =
  model.overview = OverviewState()

proc setOverviewSelection*(model: var PolicyModel, selection: OverviewSelection) =
  let output = model.output(selection.output)
  if output.isNone or selection.view notin output.get().views:
    fail("overview selection has no current workspace")
  if selection.window != nullWindowId:
    let window = model.window(selection.window)
    if window.isNone or window.get().homeOutput != selection.output or
        window.get().minimized or not window.get().capabilities.focusable or
        not model.windowTagIds(selection.window).intersects(
          model.viewTagIds(selection.view)
        ):
      fail("overview selection has no eligible window")
  model.overview = OverviewState(active: true, selection: selection)
