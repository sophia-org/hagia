import std/[sets, tables]

import ../types/[core, model]
import ../policy/entity_store
import ./[queries, values]
import ../entities/tab_tree_ops
import ../types/tab_tree

## Model lifecycle: construction, defensive copying for a candidate, and the
## invariant check every state transition must leave satisfied.

proc initPolicyModel*(): PolicyModel =
  PolicyModel(settings: defaultPolicySettings)

proc clone*(model: PolicyModel): PolicyModel =
  for view, tree in model.tabTrees.pairs:
    result.tabTrees[view] = tree.cloneTabTree()
  result.settings = model.settings
  result.settings.layoutCycle = @(model.settings.layoutCycle)
  result.activeOutput = model.activeOutput
  result.counters = model.counters
  result.visibleScratchpad = model.visibleScratchpad
  result.scratchpadTag = model.scratchpadTag
  for id in model.windowOrder:
    result.windowOrder.add(id)
    result.windows[id] = model.windows[id]
  for id in model.minimizedOrder:
    result.minimizedOrder.add(id)
  for id in model.scratchpadOrder:
    result.scratchpadOrder.add(id)
  for id, restore in model.scratchpadRestore.pairs:
    result.scratchpadRestore[id] = restore
    result.scratchpadRestore[id].tags = @(restore.tags)
  for slot, id in model.namedScratchpads.pairs:
    result.namedScratchpads[slot] = id
  for id, group in model.groups.pairs:
    result.groups[id] = group
    result.groups[id].windows = @(group.windows)
  for id, groupId in model.groupOfWindow.pairs:
    result.groupOfWindow[id] = groupId
  for id in model.columnOrder:
    var column = model.columns[id]
    column.windows = @[]
    for windowId in model.columns[id].windows:
      column.windows.add(windowId)
    result.columnOrder.add(id)
    result.columns[id] = column
  for id, view in model.views.pairs:
    result.views[id] = view
  for id, tag in model.tags.pairs:
    result.tags[id] = tag
  for id, tags in model.windowTags.pairs:
    result.windowTags[id] = @tags
  for id, tags in model.viewTags.pairs:
    result.viewTags[id] = @tags
  for id in model.outputOrder:
    var output = model.outputs[id]
    output.views = @[]
    output.focusHistory = @[]
    for viewId in model.outputs[id].views:
      output.views.add(viewId)
    for windowId in model.outputs[id].focusHistory:
      output.focusHistory.add(windowId)
    result.outputOrder.add(id)
    result.outputs[id] = output
  for id in model.affinityOrder:
    var affinity = model.affinities[id]
    affinity.views = @[]
    for viewId in model.affinities[id].views:
      affinity.views.add(viewId)
    result.affinityOrder.add(id)
    result.affinities[id] = affinity

proc validate*(model: PolicyModel) =
  var tabNodeCount = 0
  for view, tree in model.tabTrees.pairs:
    if view notin model.views:
      fail("tab tree view is missing")
    tabNodeCount += tree.nodes.len
    if tabNodeCount > maxTabTreeNodes:
      fail("global tab tree capacity exhausted")
    tree.validateTabTree()
    for node in tree.nodes:
      for window in node.windows:
        if window notin model.windows:
          fail("tab member is missing")
  if model.settings.viewCount < 1 or model.settings.viewCount > 9 or
      model.settings.outerGap < 0 or model.settings.innerGap < 0 or
      model.settings.viewportOffset < 0 or model.settings.layoutCycle.len == 0 or
      model.settings.layoutCycle.len > ord(high(LayoutMode)) + 1:
    fail("policy settings are invalid")
  var seenLayouts = initHashSet[LayoutMode]()
  for layout in model.settings.layoutCycle:
    if layout in seenLayouts:
      fail("policy layout cycle contains duplicates")
    seenLayouts.incl(layout)
  if not model.windows.validateDense() or not model.columns.validateDense() or
      not model.views.validateDense() or not model.tags.validateDense() or
      not model.outputs.validateDense():
    fail("policy dense entity index is invalid")
  if model.outputOrder.len != model.outputs.len or
      model.windowOrder.len != model.windows.len or
      model.columnOrder.len != model.columns.len:
    fail("policy indexes and ordered identities diverged")
  if model.outputs.len > 0 and model.activeOutput notin model.outputs:
    fail("policy active output is invalid")
  for id in model.windows.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.windows:
      fail("policy window counter is invalid")
  for id in model.columns.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.columns:
      fail("policy column counter is invalid")
  for id in model.views.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.views:
      fail("policy view counter is invalid")
  for id in model.tags.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.tags:
      fail("policy tag counter is invalid")
  for id in model.outputs.ids:
    if uint32(id) == 0 or uint32(id) > model.counters.outputs:
      fail("policy output counter is invalid")
  var seenViews = initHashSet[ViewId]()
  for outputId in model.outputOrder:
    let output = model.outputs[outputId]
    if output.id != outputId or output.bounds.width <= 0 or output.bounds.height <= 0 or
        output.views.len == 0 or output.activeView notin output.views:
      fail("policy output is invalid")
    for viewId in output.views:
      if viewId notin model.views or viewId in seenViews or
          model.viewTagIds(viewId).len == 0 or
          model.views[viewId].preferredOutput == nullOutputId:
        fail("policy view is invalid")
      var seenViewTags = initHashSet[TagId]()
      for tagId in model.viewTagIds(viewId):
        if tagId notin model.tags or tagId in seenViewTags or
            model.tags[tagId].kind == TagKind.scratchpad:
          fail("policy view tag membership is invalid")
        seenViewTags.incl(tagId)
      seenViews.incl(viewId)
    if output.focusedWindow != nullWindowId:
      if output.focusedWindow notin model.windows:
        fail("policy output focus is invalid")
      let focus = model.windows[output.focusedWindow]
      if focus.homeOutput != outputId or not focus.capabilities.focusable or (
        focus.id != model.visibleScratchpad and
        not model.windowTagIds(focus.id).intersects(model.viewTagIds(output.activeView))
      ) or focus.minimized:
        fail("policy output focus is invalid")
    if output.focusHistory.len > maxFocusHistory:
      fail("policy focus history is excessive")
    var seenFocus = initHashSet[WindowId]()
    for windowId in output.focusHistory:
      if windowId notin model.windows or windowId in seenFocus or
          model.windows[windowId].homeOutput != outputId:
        fail("policy focus history is invalid")
      seenFocus.incl(windowId)
  if seenViews.len != model.views.len:
    fail("policy contains a detached view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.id != windowId or window.homeOutput notin model.outputs or
        window.preferredOutput == nullOutputId or window.column notin model.columns or
        model.windowTagIds(windowId).len == 0 or
        uint32(window.heightScale) < uint32(minimumScale):
      fail("policy window is invalid")
    if window.parent == windowId or
        (window.parent != nullWindowId and window.parent notin model.windows):
      fail("policy window parent relation is invalid")
    var ancestor = window.parent
    var depth = 0
    while ancestor != nullWindowId:
      inc depth
      if depth > model.windows.len or ancestor == windowId:
        fail("policy window parent relation is cyclic")
      ancestor = model.windows[ancestor].parent
    var seenWindowTags = initHashSet[TagId]()
    for tagId in model.windowTagIds(windowId):
      if tagId notin model.tags or tagId in seenWindowTags:
        fail("policy window tag membership is invalid")
      seenWindowTags.incl(tagId)
    if window.constraints.minWidth < 0 or window.constraints.minHeight < 0 or
        window.constraints.maxWidth < 0 or window.constraints.maxHeight < 0 or
        (window.constraints.minWidth == 0) != (window.constraints.minHeight == 0) or
        (window.constraints.maxWidth == 0) != (window.constraints.maxHeight == 0) or (
      window.constraints.minWidth > 0 and window.constraints.maxWidth > 0 and (
        window.constraints.minWidth > window.constraints.maxWidth or
        window.constraints.minHeight > window.constraints.maxHeight
      )
    ):
      fail("policy window constraints are invalid")
    if window.floating and
        not model.outputs[window.homeOutput].bounds.contains(window.floatingGeometry):
      fail("floating window geometry is invalid")
    if (window.fullscreen and window.maximized) or
        (window.minimized and (window.fullscreen or window.maximized)):
      fail("policy presentation state is invalid")
  var seenWindows = initHashSet[WindowId]()
  for columnId in model.columnOrder:
    let column = model.columns[columnId]
    if column.id != columnId or column.homeOutput notin model.outputs or
        column.preferredOutput == nullOutputId or column.windows.len == 0 or (
      column.widthScale != autoScale and uint32(column.widthScale) < uint32(
        minimumScale
      )
    ):
      fail("policy column is invalid")
    for windowId in column.windows:
      if windowId notin model.windows or windowId in seenWindows or
          model.windows[windowId].column != columnId or
          model.windows[windowId].homeOutput != column.homeOutput:
        fail("policy column membership is invalid")
      seenWindows.incl(windowId)
  if seenWindows.len != model.windows.len:
    fail("policy contains a detached window")
  if model.windowTags.len != model.windows.len or model.viewTags.len != model.views.len:
    fail("policy tag relationship indexes diverged")
  var seenSlots = initHashSet[uint32]()
  for tagId, tag in model.tags.pairs:
    if tag.id != tagId or tag.slot == 0 or tag.slot > maxTagBits or tag.slot in seenSlots or
        tag.name.len > maxWorkspaceNameBytes or '\0' in tag.name:
      fail("policy tag entity is invalid")
    seenSlots.incl(tag.slot)
    if (tag.kind == TagKind.scratchpad) != (tagId == model.scratchpadTag) or
        (tag.kind == TagKind.scratchpad) != (tag.slot == scratchpadTagSlot):
      fail("private scratchpad tag identity is invalid")
    if tag.kind == TagKind.dynamic and not model.workspaceOccupied(tagId):
      var active = false
      for outputId in model.outputOrder:
        if tagId in model.viewTagIds(model.outputs[outputId].activeView):
          active = true
          break
      if not active:
        fail("policy retains an inactive empty dynamic workspace")
  if model.scratchpadTag != nullTagId and model.scratchpadTag notin model.tags:
    fail("private scratchpad tag is invalid")
  if model.scratchpadOrder.len != model.scratchpadRestore.len or
      model.scratchpadOrder.len > maxScratchpads:
    fail("scratchpad relationship indexes diverged")
  var seenScratchpads = initHashSet[WindowId]()
  for windowId in model.scratchpadOrder:
    if windowId notin model.windows or windowId in seenScratchpads or
        windowId notin model.scratchpadRestore or model.scratchpadTag == nullTagId or
        model.windowTagIds(windowId) != @[model.scratchpadTag]:
      fail("scratchpad relationship is invalid")
    let restore = model.scratchpadRestore[windowId]
    if restore.tags.len == 0 or restore.output == nullOutputId:
      fail("scratchpad restore relationship is invalid")
    var seenRestoreTags = initHashSet[TagId]()
    for tagId in restore.tags:
      if tagId notin model.tags or tagId == model.scratchpadTag or
          tagId in seenRestoreTags:
        fail("scratchpad restore membership is invalid")
      seenRestoreTags.incl(tagId)
    seenScratchpads.incl(windowId)
  if model.visibleScratchpad != nullWindowId and
      model.visibleScratchpad notin seenScratchpads:
    fail("visible scratchpad is invalid")
  for slot, windowId in model.namedScratchpads.pairs:
    if slot == nullScratchpadSlotId or windowId notin seenScratchpads:
      fail("named scratchpad relationship is invalid")
  for groupId in model.groups.ids:
    let group = model.groups[groupId]
    if groupId == nullGroupId or group.id != groupId or group.windows.len < 2 or
        group.windows.len > maxGroupMembers or group.activeWindow notin group.windows:
      fail("window group is invalid")
    var seenMembers = initHashSet[WindowId]()
    for windowId in group.windows:
      if windowId notin model.windows or windowId in seenMembers or
          model.groupOfWindow.getOrDefault(windowId, nullGroupId) != groupId:
        fail("window group membership disagrees with its index")
      seenMembers.incl(windowId)
  for windowId, groupId in model.groupOfWindow.pairs:
    if groupId notin model.groups or windowId notin model.groups[groupId].windows:
      fail("window group index names a membership the group does not hold")
  if model.minimizedOrder.len > maxMinimizedHistory:
    fail("minimized history is excessive")
  var seenMinimized = initHashSet[WindowId]()
  for windowId in model.minimizedOrder:
    if windowId notin model.windows or windowId in seenMinimized or
        not model.windows[windowId].minimized:
      fail("minimized history is invalid")
    seenMinimized.incl(windowId)
  if model.affinityOrder.len != model.affinities.len or
      model.affinityOrder.len > maxOutputAffinities:
    fail("output affinities are invalid")
  var seenAffinities = initHashSet[OutputId]()
  var previousOrder = 0'u64
  for outputId in model.affinityOrder:
    if outputId in seenAffinities or outputId in model.outputs or
        outputId notin model.affinities:
      fail("output affinity identity is invalid")
    let affinity = model.affinities[outputId]
    if affinity.output != outputId or affinity.views.len == 0 or
        affinity.disconnectedOrder <= previousOrder:
      fail("output affinity record is invalid")
    for viewId in affinity.views:
      if viewId notin model.views:
        fail("output affinity view is invalid")
    seenAffinities.incl(outputId)
    previousOrder = affinity.disconnectedOrder
  if previousOrder > model.counters.disconnects:
    fail("output disconnect counter is invalid")
