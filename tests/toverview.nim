import std/[options, sequtils, tables, unittest]

import policy/[overview, projection, state]
import systems/overview
import types/[core, model, overview]

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
