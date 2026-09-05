import std/[unittest, tables]
import types/[core, model, tab_tree, projection]
import policy/[state, entity_store, projection]
import entities/tab_tree_ops

proc caps(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

suite "Triad tab trees":
  test "frames project only their selected tab and preserve an empty sibling":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    let a = model.addWindow(output, caps(), SizeConstraints())
    let b = model.addWindow(output, caps(), SizeConstraints())
    model.setFocus(output, b)
    model.setLayout(output, LayoutMode.frameTree)
    let projected = model.projectLayout(@[output], 0, 0, 0)
    check projected[0].placements.len == 1
    check projected[0].tabGroups.len == 1
    check projected[0].tabGroups[0].members == @[a, b]
    check projected[0].placements[0].geometry.y == tabStripHeight
    model.tabTreeCommand(output, TabTreeCommand.splitHorizontal)
    check model.projectLayout(@[output], 0, 0, 0)[0].tabGroups.len == 2
    # Splitting a populated tab group moves the active tab to the new cell.
    check model.projectLayout(@[output], 0, 0, 0)[0].placements.len == 2
    model.tabTreeCommand(output, TabTreeCommand.splitHorizontal)
    model.tabTreeCommand(output, TabTreeCommand.focusRight)
    let view = model.outputs[output].activeView
    check model.tabTrees[view].representative(model.tabTrees[view].focused) ==
      nullWindowId
    model.tabTreeCommand(output, TabTreeCommand.unsplit)
    check model.projectLayout(@[output], 0, 0, 0)[0].tabGroups.len == 2

  test "i3 tab and stacking modes share horizontal strips and retain children":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    let a = model.addWindow(output, caps(), SizeConstraints())
    let b = model.addWindow(output, caps(), SizeConstraints())
    model.setFocus(output, b)
    model.setLayout(output, LayoutMode.splitTree)
    check model.projectLayout(@[output], 0, 0, 0)[0].placements.len == 2
    model.tabTreeCommand(output, TabTreeCommand.layoutTabbed)
    let tabbed = model.projectLayout(@[output], 0, 0, 0)[0]
    check tabbed.placements.len == 1
    check tabbed.tabGroups[0].members == @[a, b]
    model.tabTreeCommand(output, TabTreeCommand.previousTab)
    check model.projectLayout(@[output], 0, 0, 0)[0].placements[0].window == a
    model.tabTreeCommand(output, TabTreeCommand.layoutStacking)
    check model.projectLayout(@[output], 0, 0, 0)[0].tabGroups[0].geometry ==
      tabbed.tabGroups[0].geometry
    model.tabTreeCommand(output, TabTreeCommand.focusParent)
    let view = model.outputs[output].activeView
    let focused = model.tabTrees[view].focused
    model.syncTabTrees()
    check model.tabTrees[view].focused == focused
    model.removeWindow(a)
    model.syncTabTrees()
    check model.projectLayout(@[output], 0, 0, 0)[0].placements[0].window == b

  test "clone isolation and malformed topology":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    discard model.addWindow(output, caps(), SizeConstraints())
    model.setLayout(output, LayoutMode.notion)
    var candidate = model.clone()
    candidate.tabTreeCommand(output, TabTreeCommand.splitVertical)
    let view = model.outputs[output].activeView
    check model.tabTrees[view].nodes.len == 1
    check candidate.tabTrees[view].nodes.len == 3
    var tree = candidate.tabTrees[view].cloneTabTree()
    tree.nodes[0].parent = tree.nodes[0].id
    expect PolicyStateError:
      tree.validateTabTree()

  test "frame resize shrinks at the outer edge and empty grouping is harmless":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    let a = model.addWindow(output, caps(), SizeConstraints())
    model.setFocus(output, a)
    model.setLayout(output, LayoutMode.frameTree)
    model.tabTreeCommand(output, TabTreeCommand.splitHorizontal)
    let before = model.projectLayout(@[output], 0, 0, 0)[0].placements[0].geometry.width
    model.tabTreeCommand(output, TabTreeCommand.resizeLeft)
    check model.projectLayout(@[output], 0, 0, 0)[0].placements[0].geometry.width <
      before
    model.tabTreeCommand(output, TabTreeCommand.focusRight)
    model.tabTreeCommand(output, TabTreeCommand.group)
    model.validate()

  test "i3 moves a nested leaf into the matching ancestor":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    discard model.addWindow(output, caps(), SizeConstraints())
    let b = model.addWindow(output, caps(), SizeConstraints())
    discard model.addWindow(output, caps(), SizeConstraints())
    model.setFocus(output, b)
    model.setLayout(output, LayoutMode.splitTree)
    model.tabTreeCommand(output, TabTreeCommand.splitVertical)
    discard model.addWindow(output, caps(), SizeConstraints())
    model.syncTabTrees()
    let view = model.outputs[output].activeView
    let leaf = model.tabTrees[view].leafFor(b)
    let before = model.tabTrees[view].node(leaf).parent
    model.tabTreeCommand(output, TabTreeCommand.moveRight)
    check model.tabTrees[view].node(leaf).parent != before
    check model.projectLayout(@[output], 0, 0, 0)[0].placements.len == 4
    model.validate()

  test "dwindle splits the focused leaf and winds inward by depth":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    var windows: seq[WindowId]
    for _ in 0 ..< 4:
      windows.add(model.addWindow(output, caps(), SizeConstraints()))
    model.setFocus(output, windows[0])
    model.setLayout(output, LayoutMode.dwindle)

    # Each arrival halves what the previous window held: right half, then its
    # bottom half, then that cell's right half.
    let projected = model.projectLayout(@[output], 0, 0, 0)[0]
    check projected.tabGroups.len == 0
    check projected.placements.len == 4
    var geometry = initTable[WindowId, Rect]()
    for placement in projected.placements:
      geometry[placement.window] = placement.geometry
    check geometry[windows[0]] == Rect(width: 400, height: 600)
    check geometry[windows[1]] == Rect(x: 400, y: 0, width: 400, height: 300)
    check geometry[windows[2]] == Rect(x: 400, y: 300, width: 200, height: 300)
    check geometry[windows[3]] == Rect(x: 600, y: 300, width: 200, height: 300)
    model.validate()

  test "a preselect aims one insert and repeating it takes the aim off":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    let first = model.addWindow(output, caps(), SizeConstraints())
    model.setFocus(output, first)
    model.setLayout(output, LayoutMode.dwindle)
    discard model.projectLayout(@[output], 0, 0, 0)

    # Aim up: the next window lands above instead of beside.
    model.tabTreeCommand(output, TabTreeCommand.preselectUp)
    let second = model.addWindow(output, caps(), SizeConstraints())
    var projected = model.projectLayout(@[output], 0, 0, 0)[0]
    var geometry = initTable[WindowId, Rect]()
    for placement in projected.placements:
      geometry[placement.window] = placement.geometry
    check geometry[second] == Rect(width: 800, height: 300)
    check geometry[first] == Rect(x: 0, y: 300, width: 800, height: 300)

    # The aim was spent: a third window falls back to the depth rule, and at
    # depth one that rule says vertical, carving the aimed cell in two.
    model.setFocus(output, second)
    let third = model.addWindow(output, caps(), SizeConstraints())
    projected = model.projectLayout(@[output], 0, 0, 0)[0]
    geometry.clear()
    for placement in projected.placements:
      geometry[placement.window] = placement.geometry
    check geometry[second] == Rect(width: 800, height: 150)
    check geometry[third] == Rect(x: 0, y: 150, width: 800, height: 150)

    # Aiming and re-aiming the same way cancels: the model keeps no preselect.
    model.tabTreeCommand(output, TabTreeCommand.preselectLeft)
    model.tabTreeCommand(output, TabTreeCommand.preselectLeft)
    let view = model.outputs[output].activeView
    for node in model.tabTrees[view].nodes:
      check node.preselect == TabTreePreselect.none
    model.validate()
