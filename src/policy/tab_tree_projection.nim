import ../types/[core, tab_tree]
import ../entities/tab_tree_ops
import ../state/values

proc projectTabTree*(
    tree: TabTree, view: ViewId, bounds: Rect, gap: int32, focusedWindow: WindowId
): TabTreeProjection =
  proc walk(id: uint32, area: Rect, depth: int, projection: var TabTreeProjection) =
    if depth >= maxTabTreeDepth or area.width <= 0 or area.height <= 0:
      fail("tab tree does not fit its allocation")
    let n = tree.node(id)
    if n.mode == TabTreeMode.leaf:
      var content = area
      let active = tree.representative(id)
      if tree.frameStyle:
        let height =
          if active == nullWindowId:
            area.height
          else:
            min(tabStripHeight, area.height - 1)
        projection.groups.add(
          TabTreeGroup(
            id: (uint64(uint32(view)) shl 32) or uint64(id),
            geometry: Rect(x: area.x, y: area.y, width: area.width, height: height),
            focused: id == tree.focused or active == focusedWindow,
            selected: active,
            members: n.windows,
          )
        )
        content.y += height
        content.height -= height
      if active != nullWindowId:
        projection.placements.add(TabTreePlacement(window: active, geometry: content))
      return
    if n.mode in {TabTreeMode.tabbed, TabTreeMode.stacking}:
      var members: seq[WindowId]
      for child in n.children:
        let window = tree.representative(child)
        if window != nullWindowId:
          members.add(window)
      let active = tree.representative(id)
      let height = min(tabStripHeight, area.height - 1)
      projection.groups.add(
        TabTreeGroup(
          id: (uint64(uint32(view)) shl 32) or uint64(id),
          geometry: Rect(x: area.x, y: area.y, width: area.width, height: height),
          focused: id == tree.focused or active == focusedWindow,
          selected: active,
          members: members,
        )
      )
      if n.selectedChild != 0:
        walk(
          n.selectedChild,
          Rect(
            x: area.x,
            y: area.y + height,
            width: area.width,
            height: area.height - height,
          ),
          depth + 1,
          projection,
        )
      return
    let horizontal = n.mode == TabTreeMode.horizontal
    let extent = if horizontal: area.width else: area.height
    let available = int64(extent) - int64(gap) * int64(n.children.len - 1)
    if available < int64(n.children.len):
      fail("tab splits exhaust allocation")
    var total = 0'i64
    for child in n.children:
      total += int64(uint32(tree.node(child).weight))
    if total <= 0:
      fail("tab weights are invalid")
    var cursor = 0'i64
    var accumulated = 0'i64
    for index, child in n.children:
      accumulated += int64(uint32(tree.node(child).weight))
      let boundary =
        if index == n.children.high:
          available
        else:
          available * accumulated div total
      let length = boundary - cursor
      if length <= 0:
        fail("tab child has no extent")
      var rect = area
      if horizontal:
        rect.x += int32(cursor + int64(gap) * int64(index))
        rect.width = int32(length)
      else:
        rect.y += int32(cursor + int64(gap) * int64(index))
        rect.height = int32(length)
      walk(child, rect, depth + 1, projection)
      cursor = boundary

  tree.validateTabTree()
  walk(tree.root, bounds, 0, result)
