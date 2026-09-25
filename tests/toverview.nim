import std/[options, sequtils, tables, unittest]

import policy/[actions, overview, projection, state]
import systems/overview
import entities/settings_ops
import types/[actions, core, model, overview]

proc capabilities(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

include support/overview_expanded

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

  test "niri zoom stays fixed and clips a wide strip to its output":
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
    check previews[0].placements.len > 0
    check previews[0].placements.len < 9
    for preview in previews:
      let bounds = model.output(preview.workspace.output).get().bounds
      check preview.geometry.width == bounds.width div 2
      check preview.geometry.height == bounds.height div 2
      check preview.clip.x == bounds.x
      check preview.clip.width == bounds.width
      check preview.clip.x >= bounds.x
      check preview.clip.y >= bounds.y
      check preview.clip.x + preview.clip.width <= bounds.x + bounds.width
      check preview.clip.y + preview.clip.height <= bounds.y + bounds.height
      for placement in preview.placements:
        let source =
          preview.workspace.placements.filterIt(it.window == placement.window)[0]
        check placement.geometry.width == source.geometry.width div 2
        check placement.geometry.height == source.geometry.height div 2
    check previews[^1].workspace.output == right
    check previews[^1].placements.len == 0
    check model == before

  test "niri camera reveals every selected window without shrinking populated workspaces":
    for layout in [
      PolicyAction.selectScrollerLayout, PolicyAction.selectVerticalScrollerLayout
    ]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      var windows: seq[WindowId]
      for index in 0 .. 8:
        windows.add(model.addWindow(output, capabilities(), SizeConstraints()))
      model.setFocus(output, windows[0])
      model.applyAction(output, layout)
      let before = model.clone()
      let ordinary = model.projectLayout([output])
      model.openOverview(output)
      for window in windows:
        check model.overview.selection.window == window
        let preview = model.overviewPreviews()[0]
        let selected = preview.placements.filterIt(it.window == window)
        require selected.len == 1
        let source = preview.workspace.placements.filterIt(it.window == window)[0]
        check selected[0].geometry.width == source.geometry.width div 2
        check selected[0].geometry.height == source.geometry.height div 2
        check selected[0].geometry.x < preview.clip.x + preview.clip.width
        check selected[0].geometry.x + selected[0].geometry.width > preview.clip.x
        check selected[0].geometry.y < preview.clip.y + preview.clip.height
        check selected[0].geometry.y + selected[0].geometry.height > preview.clip.y
        check model.projectLayout([output]) == ordinary
        if window != windows[^1]:
          model.navigateOverview(
            if layout == PolicyAction.selectScrollerLayout:
              OverviewDirection.right
            else:
              OverviewDirection.down
          )
      model.applyAction(output, PolicyAction.closeOverview)
      check model == before

  test "workspace navigation uses one thumbnail scale across differently populated strips":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    model.ensureViewCount(output, 2)
    let views = model.output(output).get().views
    let first = model.addWindow(output, capabilities(), SizeConstraints())
    discard model.addWindow(output, capabilities(), SizeConstraints())
    discard model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, first)
    model.activateView(output, views[1])
    let other = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFocus(output, other)
    model.activateView(output, views[0])
    let before = model.clone()
    model.openOverview(output)
    let previews = model.overviewPreviews()
    let wide = previews.filterIt(it.workspace.view == views[0])[0]
    let narrow = previews.filterIt(it.workspace.view == views[1])[0]
    check wide.placements.len == 3
    check narrow.placements.len == 1
    check wide.placements[0].geometry.width == narrow.placements[0].geometry.width
    check wide.placements[0].geometry.height == narrow.placements[0].geometry.height
    for preview in [wide, narrow]:
      for placement in preview.placements:
        let source =
          preview.workspace.placements.filterIt(it.window == placement.window)[0]
        check placement.geometry.width == source.geometry.width div 2
        check placement.geometry.height == source.geometry.height div 2
    model.navigateOverview(OverviewDirection.down, workspaceOnly = true)
    check model.overview.selection.view == views[1]
    let moved = model.overviewPreviews()
    for preview in previews:
      let matching = moved.filterIt(it.workspace.view == preview.workspace.view)[0]
      check matching.geometry.width == preview.geometry.width
      check matching.geometry.height == preview.geometry.height
      for placement in preview.placements:
        let matched = matching.placements.filterIt(it.window == placement.window)[0]
        check matched.geometry.width == placement.geometry.width
        check matched.geometry.height == placement.geometry.height
    model.applyAction(output, PolicyAction.closeOverview)
    check model == before

  test "selection does not resize a strip with a full-width or fullscreen neighbor":
    for layout in [
      PolicyAction.selectScrollerLayout, PolicyAction.selectVerticalScrollerLayout
    ]:
      for fullscreen in [false, true]:
        var model = initPolicyModel()
        let output = model.addOutput(Rect(x: -1600, y: 32, width: 1600, height: 968))
        let physical = [(output, Rect(x: -1600, width: 1600, height: 1000))]
        var capable = capabilities()
        capable.fullscreenable = true
        let first = model.addWindow(output, capable, SizeConstraints())
        let second = model.addWindow(output, capable, SizeConstraints())
        model.setColumnFullWidth(model.window(first).get().column, true)
        model.setWindowPresentation(first, fullscreen, false, false)
        model.setFocus(output, first)
        model.applyAction(output, layout)
        let settled = model.projectLayout([output], physicalBounds = physical)[0]
        model.rememberViewportOffset(output, settled.viewportOffset, settled.camera)
        let ordinary = model.projectLayout([output], physicalBounds = physical)
        let before = model.clone()
        model.openOverview(output)
        let opened = model.overviewPreviews(physical)[0]
        check opened.placements.anyIt(it.window == first)
        model.navigateOverview(
          if layout == PolicyAction.selectScrollerLayout:
            OverviewDirection.right
          else:
            OverviewDirection.down
        )
        check model.overview.selection.window == second
        let moved = model.overviewPreviews(physical)[0]
        check moved.geometry == opened.geometry
        check moved.clip == opened.clip
        for placement in opened.placements:
          let matched = moved.placements.filterIt(it.window == placement.window)
          if matched.len != 0:
            check matched[0].geometry.width == placement.geometry.width
            check matched[0].geometry.height == placement.geometry.height
        check moved.placements.anyIt(it.window == second)
        check moved.placements[^1].window == second
        check model.projectLayout([output], physicalBounds = physical) == ordinary
        model.navigateOverview(
          if layout == PolicyAction.selectScrollerLayout:
            OverviewDirection.left
          else:
            OverviewDirection.up
        )
        check model.overview.selection.window == first
        check model.overviewPreviews(physical)[0].placements == opened.placements
        model.applyAction(output, PolicyAction.closeOverview)
        check model == before

  test "entering a cyclic workspace follows the direction of travel":
    for action in [PolicyAction.selectMonocleLayout, PolicyAction.selectDeckLayout]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1200, height: 900))
      model.ensureViewCount(output, 2)
      let views = model.output(output).get().views
      let origin = model.addWindow(output, capabilities(), SizeConstraints())
      model.setFocus(output, origin)
      model.activateView(output, views[1])
      let first = model.addWindow(output, capabilities(), SizeConstraints())
      discard model.addWindow(output, capabilities(), SizeConstraints())
      let last = model.addWindow(output, capabilities(), SizeConstraints())
      model.setFocus(output, first)
      model.applyAction(output, action)
      model.activateView(output, views[0])
      model.openOverview(output)
      model.navigateOverview(OverviewDirection.up, workspaceOnly = true)
      check model.overview.selection.window == last
      model.navigateOverview(OverviewDirection.down, workspaceOnly = true)
      check model.overview.selection.window == origin
      model.navigateOverview(OverviewDirection.down, workspaceOnly = true)
      check model.overview.selection.window == first
