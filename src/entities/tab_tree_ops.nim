import std/[tables, sets, sequtils]
import ../types/[core, model, tab_tree]
import ../policy/entity_store
import ../state/[queries, values]
import ./focus_ops

# Triad fb8fb27 frame_ops/split_tree_ops, adapted to Hagia's private views.
# All topology and membership mutation stays in this owner.
proc nodeIndex*(tree: TabTree, id: uint32): int =
  for i, n in tree.nodes:
    if n.id == id:
      return i
  -1

proc node*(tree: TabTree, id: uint32): TabTreeNode =
  let i = tree.nodeIndex(id)
  if i < 0:
    fail("tab tree names a missing node")
  tree.nodes[i]

proc addNode(tree: var TabTree, mode: TabTreeMode, parent = 0'u32): uint32 =
  if tree.nodes.len >= maxTabTreeNodes or tree.nextId == high(uint32):
    fail("tab tree capacity exhausted")
  inc tree.nextId
  result = tree.nextId
  tree.nodes.add(
    TabTreeNode(
      id: result,
      parent: parent,
      mode: mode,
      lastSplit: TabTreeMode.horizontal,
      weight: scaleOne,
    )
  )

proc representative*(tree: TabTree, id: uint32): WindowId =
  var cursor = id
  for _ in 0 ..< maxTabTreeDepth:
    let n = tree.node(cursor)
    if n.mode == TabTreeMode.leaf:
      if n.active in n.windows:
        return n.active
      return (if n.windows.len > 0: n.windows[0] else: nullWindowId)
    if n.children.len == 0:
      return nullWindowId
    cursor =
      if n.selectedChild in n.children:
        n.selectedChild
      else:
        n.children[0]
  fail("tab tree exceeds maximum depth")

proc leafFor*(tree: TabTree, window: WindowId): uint32 =
  for n in tree.nodes:
    if window in n.windows:
      return n.id

proc selectWindow(tree: var TabTree, window: WindowId) =
  var id = tree.leafFor(window)
  if id == 0:
    return
  tree.focused = id
  tree.nodes[tree.nodeIndex(id)].active = window
  while tree.node(id).parent != 0:
    let parent = tree.node(id).parent
    tree.nodes[tree.nodeIndex(parent)].selectedChild = id
    id = parent

proc cloneTabTree*(tree: TabTree): TabTree =
  result = tree
  result.nodes = @[]
  for n in tree.nodes:
    var copy = n
    copy.children = @(n.children)
    copy.windows = @(n.windows)
    result.nodes.add(copy)

proc validateTabTree*(tree: TabTree) =
  if tree.nodes.len == 0 or tree.nodes.len > maxTabTreeNodes or
      tree.nodeIndex(tree.root) < 0 or tree.node(tree.root).parent != 0 or
      tree.nodeIndex(tree.focused) < 0:
    fail("invalid tab tree root or focus")
  var ids = initHashSet[uint32]()
  var windows = initHashSet[WindowId]()
  for n in tree.nodes:
    if uint32(n.weight) == 0 or
        uint32(n.weight) > uint32(scaleOne) * uint32(maxTabTreeNodes) or n.id == 0 or
        n.id in ids or n.id > tree.nextId:
      fail("duplicate tab tree node")
    ids.incl(n.id)
    if n.mode == TabTreeMode.leaf:
      if n.children.len != 0 or (n.windows.len > 0 and n.active notin n.windows):
        fail("invalid tab leaf")
      for w in n.windows:
        if w == nullWindowId or w in windows:
          fail("duplicate tab member")
        windows.incl(w)
    elif n.windows.len != 0 or n.children.len == 0 or n.selectedChild notin n.children:
      fail("invalid tab container")
    if n.lastSplit notin {TabTreeMode.horizontal, TabTreeMode.vertical}:
      fail("invalid remembered split mode")
    if n.mode == TabTreeMode.leaf:
      if n.windows.len == 0 and n.active != nullWindowId:
        fail("empty leaf has an active member")
      if not tree.frameStyle and n.windows.len > 1:
        fail("split leaf has multiple members")
    elif tree.frameStyle and (
      n.children.len != 2 or n.mode notin {TabTreeMode.horizontal, TabTreeMode.vertical}
    ):
      fail("frame split is not binary")
    var children = initHashSet[uint32]()
    for child in n.children:
      if child in children:
        fail("duplicate tab child")
      children.incl(child)
      if tree.node(child).parent != n.id:
        fail("tab parent mismatch")
    var id = n.id
    for depth in 0 .. maxTabTreeDepth:
      if id == tree.root:
        break
      if depth == maxTabTreeDepth:
        fail("tab tree cycle or excessive depth")
      let parent = tree.node(id).parent
      if tree.nodeIndex(parent) < 0 or id notin tree.node(parent).children:
        fail("unreachable tab node")
      id = parent

proc compactTree(tree: var TabTree) =
  if tree.frameStyle:
    return
  var changed = true
  while changed:
    changed = false
    for n in tree.nodes:
      if n.id == tree.root:
        continue
      if (n.mode == TabTreeMode.leaf and n.windows.len == 0) or
          (n.mode != TabTreeMode.leaf and n.children.len == 0):
        let pi = tree.nodeIndex(n.parent)
        tree.nodes[pi].children.keepItIf(it != n.id)
        tree.nodes.keepItIf(it.id != n.id)
        changed = true
        break
      if n.mode != TabTreeMode.leaf and n.children.len == 1 and not n.pendingSplit:
        let child = n.children[0]
        let pi = tree.nodeIndex(n.parent)
        let at = tree.nodes[pi].children.find(n.id)
        tree.nodes[pi].children[at] = child
        tree.nodes[tree.nodeIndex(child)].parent = n.parent
        tree.nodes.keepItIf(it.id != n.id)
        changed = true
        break
  for n in tree.nodes.mitems:
    if n.mode != TabTreeMode.leaf:
      if n.children.len == 0:
        n.mode = TabTreeMode.leaf
      elif n.selectedChild notin n.children:
        n.selectedChild = n.children[0]
  if tree.nodeIndex(tree.focused) < 0:
    tree.focused = tree.root

proc forgetTabWindow*(model: var PolicyModel, window: WindowId) =
  for tree in model.tabTrees.mvalues:
    for n in tree.nodes.mitems:
      n.windows.keepItIf(it != window)
      if n.active == window:
        n.active =
          if n.windows.len > 0:
            n.windows[^1]
          else:
            nullWindowId
    tree.compactTree()

proc insertWindow(tree: var TabTree, window: WindowId) =
  var target = tree.focused
  if tree.nodeIndex(target) < 0:
    target = tree.root
  while tree.node(target).mode != TabTreeMode.leaf:
    target = tree.node(target).selectedChild
  if tree.frameStyle or tree.node(target).windows.len == 0:
    tree.nodes[tree.nodeIndex(target)].windows.add(window)
    tree.nodes[tree.nodeIndex(target)].active = window
  else:
    var parent = tree.node(target).parent
    if parent == 0:
      parent = tree.addNode(TabTreeMode.horizontal)
      tree.nodes[tree.nodeIndex(parent)].children = @[target]
      tree.nodes[tree.nodeIndex(parent)].selectedChild = target
      tree.nodes[tree.nodeIndex(target)].parent = parent
      tree.root = parent
    let id = tree.addNode(TabTreeMode.leaf, parent)
    let pi = tree.nodeIndex(parent)
    let at = tree.nodes[pi].children.find(target)
    tree.nodes[pi].children.insert(id, at + 1)
    tree.nodes[pi].pendingSplit = false
    tree.nodes[tree.nodeIndex(id)].windows = @[window]
    tree.nodes[tree.nodeIndex(id)].active = window
  tree.selectWindow(window)

proc tabLayoutActive*(model: PolicyModel, outputId: OutputId): bool =
  model.outputs[outputId].activeView in model.views and
    model.views[model.outputs[outputId].activeView].layout in
    {LayoutMode.frameTree, LayoutMode.notion, LayoutMode.splitTree}

proc syncTabTrees*(model: var PolicyModel) =
  for outputId in model.outputOrder:
    let output = model.outputs[outputId]
    let view = output.activeView
    let mode = model.views[view].layout
    if mode notin {LayoutMode.frameTree, LayoutMode.notion, LayoutMode.splitTree}:
      continue
    let frameStyle = mode != LayoutMode.splitTree
    if view notin model.tabTrees or model.tabTrees[view].frameStyle != frameStyle:
      var tree = TabTree(frameStyle: frameStyle)
      tree.root = tree.addNode(TabTreeMode.leaf)
      tree.focused = tree.root
      model.tabTrees[view] = tree
    var tree = model.tabTrees[view].cloneTabTree()
    let eligible = model.eligibleWindows(outputId).filterIt(
        not model.windows[it].floating and not model.windows[it].minimized
      )
    for n in tree.nodes.mitems:
      n.windows.keepItIf(it in eligible)
      if n.active notin n.windows:
        n.active =
          if n.windows.len > 0:
            n.windows[^1]
          else:
            nullWindowId
    tree.compactTree()
    for window in eligible:
      if tree.leafFor(window) == 0:
        tree.insertWindow(window)
    if tree.representative(tree.focused) != output.focusedWindow and
        tree.representative(tree.focused) != nullWindowId:
      tree.selectWindow(output.focusedWindow)
    tree.validateTabTree()
    model.tabTrees[view] = tree
  var removed: seq[ViewId]
  for view in model.tabTrees.keys:
    if view notin model.views:
      removed.add(view)
  for view in removed:
    model.tabTrees.del(view)

proc replaceChild(tree: var TabTree, parent, oldId, newId: uint32) =
  if parent == 0:
    tree.root = newId
  else:
    let pi = tree.nodeIndex(parent)
    let at = tree.nodes[pi].children.find(oldId)
    if at < 0:
      fail("tab replacement is detached")
    tree.nodes[pi].children[at] = newId
    if tree.nodes[pi].selectedChild == oldId:
      tree.nodes[pi].selectedChild = newId
  tree.nodes[tree.nodeIndex(newId)].parent = parent

proc tabTreeCommand*(
    model: var PolicyModel, outputId: OutputId, command: TabTreeCommand
) =
  model.syncTabTrees()
  if not model.tabLayoutActive(outputId):
    return
  let view = model.outputs[outputId].activeView
  if view notin model.tabTrees:
    return
  var tree = model.tabTrees[view].cloneTabTree()
  var focused = tree.focused
  let current = tree.representative(focused)
  let horizontal =
    command in {
      TabTreeCommand.splitHorizontal, TabTreeCommand.layoutHorizontal,
      TabTreeCommand.focusLeft, TabTreeCommand.focusRight, TabTreeCommand.moveLeft,
      TabTreeCommand.moveRight, TabTreeCommand.resizeLeft, TabTreeCommand.resizeRight,
    }
  let desired = if horizontal: TabTreeMode.horizontal else: TabTreeMode.vertical
  case command
  of TabTreeCommand.splitHorizontal, TabTreeCommand.splitVertical,
      TabTreeCommand.splitToggle:
    if tree.frameStyle and tree.node(focused).mode != TabTreeMode.leaf:
      return
    if tree.frameStyle and command == TabTreeCommand.splitToggle:
      let parent = tree.node(focused).parent
      if parent != 0:
        let i = tree.nodeIndex(parent)
        tree.nodes[i].mode =
          if tree.nodes[i].mode == TabTreeMode.horizontal:
            TabTreeMode.vertical
          else:
            TabTreeMode.horizontal
        model.tabTrees[view] = tree
      return
    var mode = desired
    if command == TabTreeCommand.splitToggle:
      let parent = tree.node(focused).parent
      mode =
        if parent != 0 and tree.node(parent).mode == TabTreeMode.horizontal:
          TabTreeMode.vertical
        else:
          TabTreeMode.horizontal
    let parent = tree.node(focused).parent
    if not tree.frameStyle and parent != 0 and tree.node(parent).children.len == 1:
      tree.nodes[tree.nodeIndex(parent)].mode = mode
      tree.nodes[tree.nodeIndex(parent)].lastSplit = mode
    else:
      let wrapper = tree.addNode(mode, parent)
      # Explicit split intent survives until the next window is inserted.
      tree.nodes[tree.nodeIndex(wrapper)].pendingSplit = not tree.frameStyle
      tree.replaceChild(parent, focused, wrapper)
      tree.nodes[tree.nodeIndex(focused)].parent = wrapper
      tree.nodes[tree.nodeIndex(wrapper)].children = @[focused]
      tree.nodes[tree.nodeIndex(wrapper)].selectedChild = focused
      if tree.frameStyle:
        let empty = tree.addNode(TabTreeMode.leaf, wrapper)
        tree.nodes[tree.nodeIndex(wrapper)].children.add(empty)
        let fi = tree.nodeIndex(focused)
        if tree.nodes[fi].windows.len > 1:
          tree.nodes[fi].windows.keepItIf(it != current)
          tree.nodes[fi].active = tree.nodes[fi].windows[^1]
          tree.nodes[tree.nodeIndex(empty)].windows = @[current]
          tree.nodes[tree.nodeIndex(empty)].active = current
          tree.selectWindow(current)
  of TabTreeCommand.unsplit:
    let n = tree.node(focused)
    if n.mode == TabTreeMode.leaf and n.windows.len == 0 and n.parent != 0:
      let parent = tree.node(n.parent)
      if parent.children.len == 2:
        let sibling = parent.children[if parent.children[0] == focused: 1 else: 0]
        tree.replaceChild(parent.parent, parent.id, sibling)
        tree.nodes.keepItIf(it.id != focused and it.id != parent.id)
        tree.focused = sibling
  of TabTreeCommand.layoutHorizontal, TabTreeCommand.layoutVertical,
      TabTreeCommand.layoutTabbed, TabTreeCommand.layoutStacking,
      TabTreeCommand.toggleSplit, TabTreeCommand.cycleAll:
    if tree.frameStyle:
      return
    if tree.node(focused).mode == TabTreeMode.leaf:
      if tree.node(focused).parent == 0:
        return
      focused = tree.node(focused).parent
    let i = tree.nodeIndex(focused)
    let previous = tree.nodes[i].mode
    var mode = desired
    case command
    of TabTreeCommand.layoutTabbed:
      mode = TabTreeMode.tabbed
    of TabTreeCommand.layoutStacking:
      mode = TabTreeMode.stacking
    of TabTreeCommand.toggleSplit:
      mode =
        if previous == TabTreeMode.horizontal:
          TabTreeMode.vertical
        elif previous == TabTreeMode.vertical:
          TabTreeMode.horizontal
        else:
          tree.nodes[i].lastSplit
    of TabTreeCommand.cycleAll:
      mode =
        if previous == TabTreeMode.stacking:
          TabTreeMode.horizontal
        else:
          TabTreeMode(ord(previous) + 1)
    else:
      discard
    if previous in {TabTreeMode.horizontal, TabTreeMode.vertical}:
      tree.nodes[i].lastSplit = previous
    tree.nodes[i].mode = mode
  of TabTreeCommand.focusParent:
    if tree.node(focused).parent != 0:
      tree.focused = tree.node(focused).parent
  of TabTreeCommand.focusChild:
    if tree.node(focused).children.len > 0:
      tree.focused = tree.node(focused).selectedChild
  of TabTreeCommand.nextTab, TabTreeCommand.previousTab, TabTreeCommand.nextSibling,
      TabTreeCommand.previousSibling:
    let delta =
      if command in {TabTreeCommand.nextTab, TabTreeCommand.nextSibling}: 1 else: -1
    if tree.frameStyle:
      let i = tree.nodeIndex(focused)
      let windows = tree.nodes[i].windows
      if windows.len > 0:
        tree.selectWindow(
          windows[wrappedIndex(windows.find(current), delta, windows.len)]
        )
    else:
      var parent = tree.node(focused).parent
      while parent != 0:
        let n = tree.node(parent)
        if command in {TabTreeCommand.nextSibling, TabTreeCommand.previousSibling} or
            n.mode in {TabTreeMode.tabbed, TabTreeMode.stacking}:
          let index = n.children.find(focused)
          let next = n.children[wrappedIndex(index, delta, n.children.len)]
          tree.selectWindow(tree.representative(next))
          break
        focused = parent
        parent = n.parent
  of TabTreeCommand.focusLeft .. TabTreeCommand.resizeDown:
    let positive =
      command in {
        TabTreeCommand.focusRight, TabTreeCommand.focusDown, TabTreeCommand.moveRight,
        TabTreeCommand.moveDown, TabTreeCommand.resizeRight, TabTreeCommand.resizeDown,
      }
    var branch = focused
    var parent = tree.node(branch).parent
    while parent != 0:
      let n = tree.node(parent)
      let at = n.children.find(branch)
      let resizing = command in {TabTreeCommand.resizeLeft .. TabTreeCommand.resizeDown}
      let next =
        if resizing:
          (if at > 0: at - 1 else: at + 1)
        else:
          at + (if positive: 1 else: -1)
      if n.mode == desired and next >= 0 and next < n.children.len:
        let target = n.children[next]
        if command in {TabTreeCommand.resizeLeft .. TabTreeCommand.resizeDown}:
          let i = tree.nodeIndex(if positive: branch else: target)
          let j = tree.nodeIndex(if positive: target else: branch)
          let total = uint32(tree.nodes[i].weight) + uint32(tree.nodes[j].weight)
          let step = max(1'u32, total div 20)
          if uint32(tree.nodes[j].weight) > step * 2 and
              uint32(tree.nodes[i].weight) + step <=
              uint32(scaleOne) * uint32(maxTabTreeNodes):
            tree.nodes[i].weight = Scale(uint32(tree.nodes[i].weight) + step)
            tree.nodes[j].weight = Scale(uint32(tree.nodes[j].weight) - step)
        elif command in {TabTreeCommand.moveLeft .. TabTreeCommand.moveDown}:
          if tree.frameStyle:
            var targetLeaf = target
            while tree.node(targetLeaf).mode != TabTreeMode.leaf:
              targetLeaf = tree.node(targetLeaf).selectedChild
            if current == nullWindowId:
              break
            let replacement = tree.representative(targetLeaf)
            let fromIndex = tree.nodeIndex(tree.leafFor(current))
            tree.nodes[fromIndex].windows.keepItIf(it != current)
            if tree.nodes[fromIndex].active == current:
              tree.nodes[fromIndex].active =
                if tree.nodes[fromIndex].windows.len > 0:
                  tree.nodes[fromIndex].windows[0]
                else:
                  nullWindowId
            if replacement != nullWindowId:
              tree.nodes[tree.nodeIndex(targetLeaf)].windows.keepItIf(it != replacement)
              tree.nodes[fromIndex].windows.add(replacement)
              tree.nodes[fromIndex].active = replacement
            tree.nodes[tree.nodeIndex(targetLeaf)].windows.add(current)
            tree.selectWindow(current)
          else:
            let leaf = tree.leafFor(current)
            if leaf == 0:
              break
            if branch == leaf:
              let pi = tree.nodeIndex(parent)
              swap(tree.nodes[pi].children[at], tree.nodes[pi].children[next])
            else:
              let oldParent = tree.node(leaf).parent
              tree.nodes[tree.nodeIndex(oldParent)].children.keepItIf(it != leaf)
              let pi = tree.nodeIndex(parent)
              let at = tree.nodes[pi].children.find(target)
              tree.nodes[pi].children.insert(leaf, at + (if positive: 1 else: 0))
              tree.nodes[tree.nodeIndex(leaf)].parent = parent
              tree.selectWindow(current)
        else:
          tree.focused = target
          let w = tree.representative(target)
          if w != nullWindowId:
            tree.selectWindow(w)
        break
      branch = parent
      parent = n.parent
  of TabTreeCommand.group, TabTreeCommand.ungroup:
    if current == nullWindowId:
      return
    if tree.frameStyle and command == TabTreeCommand.group:
      let target = tree.leafFor(current)
      for n in tree.nodes.mitems:
        if n.id != target and n.windows.len > 0:
          tree.nodes[tree.nodeIndex(target)].windows.add(n.windows)
          n.windows = @[]
          n.active = nullWindowId
          break
    elif tree.frameStyle and command == TabTreeCommand.ungroup:
      let source = tree.leafFor(current)
      if source != 0 and tree.node(source).windows.len > 1:
        var target = 0'u32
        for n in tree.nodes:
          if n.mode == TabTreeMode.leaf and n.windows.len == 0:
            target = n.id
            break
        if target == 0:
          let parent = tree.node(source).parent
          let wrapper = tree.addNode(TabTreeMode.horizontal, parent)
          tree.replaceChild(parent, source, wrapper)
          target = tree.addNode(TabTreeMode.leaf, wrapper)
          tree.nodes[tree.nodeIndex(source)].parent = wrapper
          tree.nodes[tree.nodeIndex(wrapper)].children = @[source, target]
          tree.nodes[tree.nodeIndex(wrapper)].selectedChild = source
        tree.nodes[tree.nodeIndex(source)].windows.keepItIf(it != current)
        tree.nodes[tree.nodeIndex(source)].active = tree.node(source).windows[^1]
        tree.nodes[tree.nodeIndex(target)].windows = @[current]
        tree.nodes[tree.nodeIndex(target)].active = current
        tree.selectWindow(current)
    elif not tree.frameStyle:
      let parent = tree.node(focused).parent
      if parent != 0:
        tree.nodes[tree.nodeIndex(parent)].mode =
          if command == TabTreeCommand.group:
            TabTreeMode.tabbed
          else:
            TabTreeMode.horizontal
  tree.compactTree()
  tree.validateTabTree()
  model.tabTrees[view] = tree
  let next = tree.representative(tree.focused)
  if next != nullWindowId:
    model.setFocus(outputId, next)

proc focusTabWindow*(model: var PolicyModel, outputId: OutputId, window: WindowId) =
  model.syncTabTrees()
  let view = model.outputs[outputId].activeView
  if view in model.tabTrees:
    model.tabTrees[view].selectWindow(window)
