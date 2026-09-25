import std/[options, sequtils, tables, unittest]

import policy/[actions, overview, projection, state]
import systems/overview
import types/[actions, core, model, overview]

proc capabilities(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

suite "workspace overview policy":
  test "hidden and empty workspaces are projected without spending state":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    model.ensureViewCount(output, 3)
    let views = model.output(output).get().views
    let first = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, first)
    model.activateView(output, views[1])
    let second = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, second)
    let current = model.projectLayout([output])[0]
    model.rememberViewportOffset(output, current.viewportOffset, current.camera)
    let before = model.clone()
    let previews = model.overviewWorkspaces()
    check previews.len == 3
    check previews[0].placements.mapIt(it.window) == @[first]
    check previews[1].placements.mapIt(it.window) == @[second]
    check previews[2].placements.len == 0
    check previews[1].active
    check not previews[0].active
    check model == before
    check model.overviewWorkspaces() == previews

  test "selection activates the chosen workspace on its owning output":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1200, height: 900))
    let right = model.addOutput(Rect(x: 1200, width: 1600, height: 1000))
    model.ensureViewCount(right, 2)
    let rightViews = model.output(right).get().views
    model.activateView(right, rightViews[1])
    let target = model.addWindow(right, capabilities(), SizeConstraints())
    model.activateView(right, rightViews[0])
    let leftWindow = model.addWindow(left, capabilities(), SizeConstraints())
    model.setFocus(left, leftWindow)
    let leftBefore = model.output(left).get()
    model.selectOverview(
      OverviewSelection(output: right, view: rightViews[1], window: target)
    )
    check model.activeOutput == right
    check model.output(right).get().activeView == rightViews[1]
    check model.output(right).get().focusedWindow == target
    check model.output(left).get() == leftBefore

  test "an empty workspace is a valid destination":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 900))
    model.ensureViewCount(output, 2)
    let window = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, window)
    let empty = model.output(output).get().views[1]
    model.selectOverview(OverviewSelection(output: output, view: empty))
    check model.output(output).get().activeView == empty
    check model.output(output).get().focusedWindow == nullWindowId

  test "stale or foreign selections leave the whole model unchanged":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 900))
    model.ensureViewCount(output, 2)
    let window = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, window)
    let before = model.clone()
    let otherView = model.output(output).get().views[1]
    for target in [window, WindowId(9999)]:
      expect PolicyStateError:
        model.selectOverview(
          OverviewSelection(output: output, view: otherView, window: target)
        )
      check model == before
    expect PolicyStateError:
      model.selectOverview(OverviewSelection(output: output, view: ViewId(9999)))
    check model == before

  test "open, navigation and cancellation preserve ordinary focus and layouts":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 900))
    model.ensureViewCount(output, 3)
    let views = model.output(output).get().views
    model.activateView(output, views[1])
    let second = model.addWindow(output, capabilities(), SizeConstraints())
    model.activateView(output, views[0])
    let first = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, first)
    let before = model.clone()
    let normal = model.projectLayout([output])
    model.applyAction(output, PolicyAction.toggleOverview)
    check model.overview.active
    check model.overview.selection.window == first
    model.applyAction(output, PolicyAction.overviewNextWorkspace)
    check model.overview.selection.window == second
    check model.output(output).get().activeView == views[0]
    check model.output(output).get().focusedWindow == first
    check model.projectLayout([output]) == normal
    model.applyAction(output, PolicyAction.closeOverview)
    check model == before

  test "vertical edges wrap occupied previews and horizontal edges stop":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 900))
    model.ensureViewCount(output, 3)
    let views = model.output(output).get().views
    let first = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, first)
    model.activateView(output, views[2])
    let last = model.addWindow(output, capabilities(), SizeConstraints())
    model.activateView(output, views[0])
    model.openOverview(output)
    model.navigateOverview(OverviewDirection.right)
    check model.overview.selection.window == first
    model.navigateOverview(OverviewDirection.up)
    check model.overview.selection.window == last
    model.navigateOverview(OverviewDirection.down)
    check model.overview.selection.window == first
    model.confirmOverview()
    check not model.overview.active
    check model.output(output).get().focusedWindow == first

  test "monocle navigation reveals the selected thumbnail without focusing the client":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 900))
    let first = model.addWindow(output, capabilities(), SizeConstraints())
    let second = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, first)
    model.applyAction(output, PolicyAction.selectMonocleLayout)
    model.openOverview(output)
    model.navigateOverview(OverviewDirection.down)
    check model.overview.selection.window == second
    check model.output(output).get().focusedWindow == first
    let previews = model.overviewPreviews()
    check previews.len == 1
    check previews[0].placements.mapIt(it.window) == @[second]
    model.confirmOverview()
    check model.output(output).get().focusedWindow == second

  test "preview geometry stays on each output and compresses a wide strip":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(x: -1200, width: 1200, height: 900))
    let right = model.addOutput(Rect(width: 1600, height: 1000))
    model.ensureViewCount(left, 3)
    let views = model.output(left).get().views
    model.activateView(left, views[1])
    discard model.addWindow(left, capabilities(), SizeConstraints())
    model.activateView(left, views[0])
    for index in 0 .. 8:
      discard model.addWindow(left, capabilities(), SizeConstraints())
    model.openOverview(left)
    let before = model.clone()
    let previews = model.overviewPreviews()
    check previews.len == 3
    check previews[0].placements.len == 9
    for preview in previews:
      let bounds = model.output(preview.workspace.output).get().bounds
      check preview.clip.x >= bounds.x
      check preview.clip.y >= bounds.y
      check preview.clip.x + preview.clip.width <= bounds.x + bounds.width
      check preview.clip.y + preview.clip.height <= bounds.y + bounds.height
      for placement in preview.placements:
        check placement.geometry.x >= preview.geometry.x
        check placement.geometry.x + placement.geometry.width <=
          preview.geometry.x + preview.geometry.width
    check previews[^1].workspace.output == right
    check previews[^1].placements.len == 0
    check model == before
