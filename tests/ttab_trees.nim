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
