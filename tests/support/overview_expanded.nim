suite "persistent overview expanded columns":
  test "maximized and fullscreen footprints persist across selection on both axes":
    for vertical in [false, true]:
      for fullscreen in [false, true]:
        var model = initPolicyModel()
        let output = model.addOutput(Rect(x: -1600, y: 32, width: 1600, height: 968))
        let physical = [(output, Rect(x: -1600, width: 1600, height: 1000))]
        var capable = capabilities()
        capable.fullscreenable = true
        let expanded = model.addWindow(output, capable, SizeConstraints())
        let neighbor = model.addWindow(output, capable, SizeConstraints())
        model.setWindowPresentation(expanded, fullscreen, not fullscreen, false)
        model.setFocus(output, expanded)
        model.applyAction(
          output,
          if vertical:
            PolicyAction.selectVerticalScrollerLayout
          else:
            PolicyAction.selectScrollerLayout,
        )
        let ordinary = model.projectLayout([output], physicalBounds = physical)
        let before = model.clone()
        model.openOverview(output)
        for selected in [expanded, neighbor, expanded]:
          check model.overview.selection.window == selected
          let workspace = model.overviewWorkspaces(physical)[0]
          let large = workspace.placements.filterIt(it.window == expanded)
          let normal = workspace.placements.filterIt(it.window == neighbor)
          require large.len == 1
          require normal.len == 1
          check large[0].geometry.width == 1600
          check large[0].geometry.height == (if fullscreen: 1000 else: 968)
          if vertical:
            check normal[0].geometry.y == large[0].geometry.y + large[0].geometry.height
            check normal[0].geometry.height == 484
          else:
            check normal[0].geometry.x == large[0].geometry.x + large[0].geometry.width
            check normal[0].geometry.width == 800
          let preview = model.overviewPreviews(physical)[0]
          let target = preview.placements.filterIt(it.window == selected)
          require target.len == 1
          if selected == expanded:
            check target[0].geometry.width == 800
            check target[0].geometry.height == (if fullscreen: 500 else: 484)
            check target[0].geometry.x >= preview.clip.x
            check target[0].geometry.y >= preview.clip.y
            check target[0].geometry.x + target[0].geometry.width <=
              preview.clip.x + preview.clip.width
            check target[0].geometry.y + target[0].geometry.height <=
              preview.clip.y + preview.clip.height
          check model.projectLayout([output], physicalBounds = physical) == ordinary
          model.navigateOverview(
            if selected == expanded:
              (if vertical: OverviewDirection.down else: OverviewDirection.right)
            else:
              (if vertical: OverviewDirection.up else: OverviewDirection.left)
          )
        model.applyAction(output, PolicyAction.closeOverview)
        check model == before

  test "multiple expanded columns keep sizes gaps and navigation order":
    for vertical in [false, true]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      var capable = capabilities()
      capable.fullscreenable = true
      var windows: seq[WindowId]
      for index in 0 .. 4:
        windows.add(model.addWindow(output, capable, SizeConstraints()))
      model.setWindowPresentation(windows[1], false, true, false)
      model.setWindowPresentation(windows[2], true, false, false)
      model.setWindowPresentation(windows[3], false, true, false)
      model.applyAction(
        output,
        if vertical:
          PolicyAction.selectVerticalScrollerLayout
        else:
          PolicyAction.selectScrollerLayout,
      )
      model.adjustGapSizes(12)
      model.setFocus(output, windows[0])
      let ordinary = model.projectLayout([output])
      model.openOverview(output)
      for selected in windows:
        check model.overview.selection.window == selected
        let workspace = model.overviewWorkspaces()[0]
        check workspace.placements.len == windows.len
        var previousEnd = 0'i32
        for index, window in windows:
          var geometry = workspace.placements.filterIt(it.window == window)[0].geometry
          if vertical:
            geometry = geometry.transpose()
          if index > 0:
            check geometry.x == previousEnd + 12
          if index in 1 .. 3:
            check geometry.width == (if vertical: 1000 else: 1600)
            check geometry.height == (if vertical: 1600 else: 1000)
          previousEnd = geometry.x + geometry.width
        check model.overviewPreviews()[0].placements.anyIt(it.window == selected)
        check model.projectLayout([output]) == ordinary
        if selected != windows[^1]:
          model.navigateOverview(
            if vertical: OverviewDirection.down else: OverviewDirection.right
          )

  test "shared-column expansion is virtual and confirmation uses original identities":
    for vertical in [false, true]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      let sibling = model.addWindow(output, capabilities(), SizeConstraints())
      let expanded = model.addWindow(output, capabilities(), SizeConstraints())
      let neighbor = model.addWindow(output, capabilities(), SizeConstraints())
      let column = model.window(sibling).get().column
      model.moveWindowToColumn(expanded, column)
      model.setWindowPresentation(expanded, false, true, false)
      model.applyAction(
        output,
        if vertical:
          PolicyAction.selectVerticalScrollerLayout
        else:
          PolicyAction.selectScrollerLayout,
      )
      model.setFocus(output, sibling)
      let ordinary = model.projectLayout([output])
      let before = model.clone()
      model.openOverview(output)
      let workspace = model.overviewWorkspaces()[0]
      var positions: seq[Rect]
      for window in [sibling, expanded, neighbor]:
        let rect = workspace.placements.filterIt(it.window == window)[0].geometry
        positions.add(
          if vertical:
            rect.transpose()
          else:
            rect
        )
      check positions[1].x == positions[0].x + positions[0].width
      check positions[2].x == positions[1].x + positions[1].width
      check positions[0].height == (if vertical: 1600 else: 1000)
      model.navigateOverview(
        if vertical: OverviewDirection.down else: OverviewDirection.right
      )
      check model.overview.selection.window == expanded
      check model.window(expanded).get().column == column
      check model.projectLayout([output]) == ordinary
      model.confirmOverview()
      check model.output(output).get().focusedWindow == expanded
      check model.window(expanded).get().column == column
      check model.tiledColumnIds(output) == before.tiledColumnIds(output)
      check not model.overview.active

  test "floating sizes stay ordinary and a dialog follows the expanded preview parent":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, capabilities(), SizeConstraints())
    discard model.addWindow(output, capabilities(), SizeConstraints())
    let floating = model.addWindow(output, capabilities(), SizeConstraints())
    model.setFloatingGeometry(
      output, floating, Rect(x: 80, y: 50, width: 640, height: 400)
    )
    let dialog = model.addWindow(output, capabilities(), SizeConstraints())
    model.setWindowRelation(dialog, WindowKind.dialog, parent)
    model.placeTransient(dialog, parent, 300, 200, Rect())
    model.setWindowPresentation(parent, false, true, false)
    model.setFocus(output, parent)
    let ordinary = model.projectLayout([output])
    model.openOverview(output)
    let preview = model.overviewPreviews()[0]
    let parentRect = preview.placements.filterIt(it.window == parent)[0].geometry
    let childRect = preview.placements.filterIt(it.window == dialog)[0].geometry
    let floatRect = preview.placements.filterIt(it.window == floating)[0].geometry
    check floatRect.width == 320
    check floatRect.height == 200
    check childRect.width == 150
    check childRect.height == 100
    check childRect.x == parentRect.x + (parentRect.width - childRect.width) div 2
    check childRect.y == parentRect.y + (parentRect.height - childRect.height) div 2
    check preview.placements.mapIt(it.window).find(dialog) >
      preview.placements.mapIt(it.window).find(parent)
    check model.projectLayout([output]) == ordinary

  test "preview camera translates a centered ordinary baseline after expansion":
    for vertical in [false, true]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      var windows: seq[WindowId]
      for _ in 0 .. 3:
        windows.add(model.addWindow(output, capabilities(), SizeConstraints()))
      model.applyAction(
        output,
        if vertical:
          PolicyAction.selectVerticalScrollerLayout
        else:
          PolicyAction.selectScrollerLayout,
      )
      model.settings.centerFocusedColumn = CenterFocusedColumn.onOverflow
      for window in windows:
        model.setColumnWidthExtent(
          model.window(window).get().column, fixedExtent(if vertical: 600 else: 900)
        )
      model.adjustGapSizes(12)
      model.setFocus(output, windows[0])
      let settled = model.projectLayout([output], 12, 12)[0]
      model.rememberViewportOffset(output, settled.viewportOffset, settled.camera)
      model.setWindowPresentation(windows[0], false, true, false)
      let ordinary = model.projectLayout([output], 12, 12)
      model.openOverview(output)
      var previousOffset = low(int32)
      for index in 0 .. 3:
        check model.overview.selection.window == windows[index]
        let workspace = model.overviewWorkspaces()[0]
        var expanded =
          workspace.placements.filterIt(it.window == windows[0])[0].geometry
        var selected =
          workspace.placements.filterIt(it.window == windows[index])[0].geometry
        if vertical:
          expanded = expanded.transpose()
          selected = selected.transpose()
        let offset = -expanded.x
        check offset >= previousOffset
        previousOffset = offset
        let extent = (if vertical: 1000'i32 else: 1600'i32)
        check selected.x >= 0
        check selected.x + selected.width <= extent
        if index >= 2:
          # The ordinary on-overflow camera centers this column. Translating
          # the camera preserves that position despite the expanded prefix.
          check selected.x == (extent - selected.width) div 2
        if index < 3:
          model.navigateOverview(
            if vertical: OverviewDirection.down else: OverviewDirection.right
          )
      for index in countdown(2, 0):
        model.navigateOverview(
          if vertical: OverviewDirection.up else: OverviewDirection.left
        )
        check model.overview.selection.window == windows[index]
        let workspace = model.overviewWorkspaces()[0]
        var expanded =
          workspace.placements.filterIt(it.window == windows[0])[0].geometry
        var selected =
          workspace.placements.filterIt(it.window == windows[index])[0].geometry
        if vertical:
          expanded = expanded.transpose()
          selected = selected.transpose()
        let offset = -expanded.x
        check offset <= previousOffset
        check offset >= 0
        previousOffset = offset
        check selected.x >= 0
        check selected.x + selected.width <= (if vertical: 1000 else: 1600)
      check model.projectLayout([output], 12, 12) == ordinary

  test "maximization outranks full width in previews even with gaps":
    for vertical in [false, true]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      let expanded = model.addWindow(output, capabilities(), SizeConstraints())
      discard model.addWindow(output, capabilities(), SizeConstraints())
      model.applyAction(
        output,
        if vertical:
          PolicyAction.selectVerticalScrollerLayout
        else:
          PolicyAction.selectScrollerLayout,
      )
      model.setColumnFullWidth(model.window(expanded).get().column, true)
      model.setWindowPresentation(expanded, false, true, false)
      model.adjustGapSizes(12)
      model.setFocus(output, expanded)
      let ordinary = model.projectLayout([output], 12, 12)
      model.openOverview(output)
      let preview = model.overviewPreviews()[0]
      let selected = preview.placements.filterIt(it.window == expanded)[0].geometry
      check selected.width == 800
      check selected.height == 500
      check model.projectLayout([output], 12, 12) == ordinary
