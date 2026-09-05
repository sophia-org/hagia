import std/[options, sets]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, queries, values]
import ../entities/[focus_ops, output_ops, tag_ops, view_ops]

import ./placement

## Workspace and view policy: which view is active, which tags a view selects,
## and how dynamic workspaces come and go.

proc activateView*(model: var PolicyModel, outputId: OutputId, viewId: ViewId) =
  let output = model.output(outputId)
  if output.isNone or viewId notin output.get().views:
    fail("view does not belong to the output")
  model.outputs[outputId].activeView = viewId
  let focus = model.outputs[outputId].focusedWindow
  if focus != nullWindowId:
    let window = model.window(focus)
    let tags = model.viewTagIds(viewId)
    if window.isNone or window.get().homeOutput != outputId or (
      focus != model.visibleScratchpad and not model.windowTagIds(focus).intersects(
        tags
      )
    ):
      model.outputs[outputId].focusedWindow = nullWindowId
  discard model.pruneDynamicWorkspaces()

proc focusOccupiedWorkspaceRelative*(
    model: var PolicyModel, outputId: OutputId, delta: int
) =
  if outputId notin model.outputs:
    fail("occupied workspace output does not exist")
  var occupied: seq[TagId]
  for slot in 1'u32 .. maxWorkspaceTagSlot:
    let tagId = model.tagIdForSlot(slot)
    if tagId != nullTagId and model.workspaceOccupied(tagId):
      occupied.add(tagId)
  if occupied.len == 0:
    return
  let activeTags = model.viewTagIds(model.outputs[outputId].activeView)
  var current = -1
  for index, tagId in occupied:
    if tagId in activeTags:
      current = index
      break
  let targetIndex =
    if current < 0:
      if delta < 0: occupied.high else: 0
    else:
      wrappedIndex(current, delta, occupied.len)
  let target = occupied[targetIndex]
  var targetOutput = nullOutputId
  var targetView = nullViewId
  for candidateOutput in model.outputOrder:
    for viewId in model.outputs[candidateOutput].views:
      if target in model.viewTagIds(viewId) and
          (targetOutput == nullOutputId or candidateOutput == outputId):
        targetOutput = candidateOutput
        targetView = viewId
  if targetOutput == nullOutputId:
    fail("occupied workspace has no live view")
  model.setActiveOutput(targetOutput)
  model.activateView(targetOutput, targetView)

proc reconcilePolicySettings*(model: var PolicyModel) =
  ## Prepare a configuration candidate against stable logical state. Existing
  ## native layout selections survive when the new cycle still admits them;
  ## removed fixed profile views never recycle identity or discard window tags.
  if model.settings.viewCount < 1 or model.settings.viewCount > 9 or
      model.settings.layoutCycle.len == 0:
    fail("policy settings candidate is invalid")
  if model.settings.masterCount < 1 or model.settings.masterCount > maxMasterCount or
      uint32(model.settings.masterRatio) < uint32(minMasterRatio) or
      uint32(model.settings.masterRatio) > uint32(maxMasterRatio) or
      model.settings.gapStep < 1 or model.settings.gapStep > maxGap or
      model.settings.outerGap < 0 or model.settings.outerGap > maxGap or
      model.settings.innerGap < 0 or model.settings.innerGap > maxGap:
    fail("policy layout settings candidate is outside its bounds")
  if model.settings.columnWidthPresets.len > maxColumnWidthPresets:
    fail("policy column width presets exceed their bound")
  for preset in model.settings.columnWidthPresets:
    if preset < 5 or preset > 95:
      fail("policy column width preset is outside 5..95 percent")
  for pair in [
    (
      model.settings.scratchpadWidthPercent, model.settings.scratchpadHeightPercent,
      false,
    ),
    (model.settings.floatingWidthPercent, model.settings.floatingHeightPercent, true),
  ]:
    for value in [pair[0], pair[1]]:
      if (value == 0 and not pair[2]) or value < 0 or
          (value != 0 and (value < 10 or value > 100)):
        fail("policy placement size percentage is outside its bounds")
  var namedSlots = initHashSet[int]()
  for entry in model.settings.viewNames:
    if entry.slot < 1 or entry.slot > model.settings.viewCount or
        entry.slot in namedSlots or entry.name.len == 0 or
        entry.name.len > maxViewNameBytes:
      fail("policy view name candidate is invalid")
    namedSlots.incl(entry.slot)
  var layoutSlots = initHashSet[int]()
  for entry in model.settings.viewLayouts:
    if entry.slot < 1 or entry.slot > model.settings.viewCount or
        entry.slot in layoutSlots:
      fail("policy view layout candidate is invalid")
    layoutSlots.incl(entry.slot)
  for viewId in model.views.ids:
    if model.views[viewId].layout notin model.settings.layoutCycle:
      model.views[viewId].layout = model.settings.layoutCycle[0]
  let outputs = model.outputOrder
  for outputId in outputs:
    for slot in 1'u32 .. uint32(model.settings.viewCount):
      if model.profileViewForSlot(outputId, slot) == nullViewId:
        let created = model.addView(outputId, [model.profileTag(slot)])
        # The profile sets a view's starting layout; a runtime switch wins
        # from then on, so this applies only when the view is born.
        for entry in model.settings.viewLayouts:
          if uint32(entry.slot) == slot:
            model.views[created].layout = entry.layout
    var removed: seq[ViewId]
    for viewId in model.outputs[outputId].views:
      let tags = model.viewTagIds(viewId)
      if tags.len == 1 and model.tags[tags[0]].kind == TagKind.profile and
          model.tags[tags[0]].slot > uint32(model.settings.viewCount):
        removed.add(viewId)
    if model.outputs[outputId].activeView in removed:
      model.activateView(outputId, model.profileViewForSlot(outputId, 1))
    for viewId in removed:
      model.removeView(viewId)
    for entry in model.settings.viewNames:
      let viewId = model.profileViewForSlot(outputId, uint32(entry.slot))
      if viewId != nullViewId:
        for tagId in model.viewTagIds(viewId):
          model.setWorkspaceName(tagId, entry.name)
    var ordered: seq[ViewId]
    for slot in 1'u32 .. uint32(model.settings.viewCount):
      let viewId = model.profileViewForSlot(outputId, slot)
      if viewId != nullViewId:
        ordered.add(viewId)
    for viewId in model.outputs[outputId].views:
      if viewId notin ordered:
        ordered.add(viewId)
    model.outputs[outputId].views = ordered

proc toggleViewTagSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > int(maxWorkspaceTagSlot):
    fail("view tag slot is outside the bounded range")
  let viewId = model.outputs[outputId].activeView
  let current = model.viewTagMask(viewId)
  let next = TagMask(uint64(current) xor uint64(tagForSlot(uint32(slot))))
  if next != emptyTagMask:
    model.setViewTags(outputId, viewId, next)

proc toggleFocusedWindowTagSlot*(
    model: var PolicyModel, outputId: OutputId, slot: int
) =
  if outputId notin model.outputs or slot < 1 or slot > int(maxWorkspaceTagSlot):
    fail("window tag slot is outside the bounded range")
  let windowId = model.outputs[outputId].focusedWindow
  if windowId == nullWindowId:
    return
  let current = model.windowTagMask(windowId)
  let next = TagMask(uint64(current) xor uint64(tagForSlot(uint32(slot))))
  if next != emptyTagMask:
    model.setWindowTags(windowId, next)

proc activateViewRelative*(model: var PolicyModel, outputId: OutputId, delta: int) =
  if outputId notin model.outputs:
    fail("view output does not exist")
  let views = model.outputs[outputId].views
  let current = views.find(model.outputs[outputId].activeView)
  if views.len == 0 or current < 0:
    fail("output has no active view")
  model.activateView(outputId, views[wrappedIndex(current, delta, views.len)])

proc activateViewSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > model.outputs[outputId].views.len:
    fail("view slot is outside the active profile")
  model.activateView(outputId, model.outputs[outputId].views[slot - 1])

proc moveFocusedToViewSlot*(model: var PolicyModel, outputId: OutputId, slot: int) =
  if outputId notin model.outputs or slot < 1 or slot > model.outputs[outputId].views.len:
    fail("view slot is outside the active profile")
  let window = model.outputs[outputId].focusedWindow
  if window == nullWindowId:
    return
  let view = model.outputs[outputId].views[slot - 1]
  model.setWindowTagIds(window, model.viewTagIds(view))
  model.activateView(outputId, view)
  model.setFocus(outputId, window)

proc placeWindowInViewSlot*(
    model: var PolicyModel, windowId: WindowId, outputId: OutputId, slot: int
) =
  ## Policy-local interpretation of an opaque launch class. Placement changes
  ## membership only; it does not switch the user's active view.
  if windowId notin model.windows or outputId notin model.outputs or slot < 1 or
      slot > model.outputs[outputId].views.len:
    fail("launch placement view slot is outside the active profile")
  model.adoptWindowOutput(windowId, outputId)
  let view = model.outputs[outputId].views[slot - 1]
  model.setWindowTagIds(windowId, model.viewTagIds(view))

proc addDynamicWorkspace*(
    model: var PolicyModel, outputId: OutputId, name = ""
): ViewId =
  if outputId notin model.outputs:
    fail("dynamic workspace output does not exist")
  if name.len > maxWorkspaceNameBytes or '\0' in name:
    fail("workspace name is invalid")
  discard model.pruneDynamicWorkspaces()
  let slot = model.nextDynamicWorkspaceSlot()
  if slot == 0:
    fail("dynamic workspace slots are exhausted")
  let tagId = TagId(nextRaw(model.counters.tags, "tag"))
  model.tags[tagId] = TagData(id: tagId, slot: slot, kind: TagKind.dynamic, name: name)
  result = model.addView(outputId, [tagId])
  model.activateView(outputId, result)
