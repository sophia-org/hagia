import std/[sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, queries, values]

## Tag and workspace membership. These procedures apply the index arithmetic of
## creating, retiring, and re-pointing tags; they decide no policy.

proc profileTag*(model: var PolicyModel, slot: uint32): TagId =
  if slot == 0 or slot > maxWorkspaceTagSlot:
    fail("tag slot is outside Hagia's bounded range")
  for tagId, tag in model.tags.pairs:
    if tag.slot == slot:
      return tagId
  result = TagId(nextRaw(model.counters.tags, "tag"))
  model.tags[result] = TagData(id: result, slot: slot, kind: TagKind.profile)

proc ensureScratchpadTag*(model: var PolicyModel): TagId =
  if model.scratchpadTag != nullTagId:
    if model.scratchpadTag notin model.tags:
      fail("private scratchpad tag is missing")
    return model.scratchpadTag
  let occupied = model.tagIdForSlot(scratchpadTagSlot)
  if occupied != nullTagId:
    fail("private scratchpad tag slot is already occupied")
  result = TagId(nextRaw(model.counters.tags, "tag"))
  model.tags[result] =
    TagData(id: result, slot: scratchpadTagSlot, kind: TagKind.scratchpad)
  model.scratchpadTag = result

proc tagIdsForMask*(model: var PolicyModel, mask: TagMask): seq[TagId] =
  if mask == emptyTagMask:
    fail("tag membership must be nonempty")
  if (uint64(mask) and uint64(tagForSlot(scratchpadTagSlot))) != 0:
    fail("the private scratchpad tag cannot be selected by a mask")
  for slot in 1'u32 .. maxWorkspaceTagSlot:
    if (uint64(mask) and uint64(tagForSlot(slot))) != 0:
      result.add(model.profileTag(slot))

proc setWorkspaceName*(model: var PolicyModel, tagId: TagId, name: string) =
  if tagId notin model.tags or model.tags[tagId].kind == TagKind.scratchpad or
      name.len > maxWorkspaceNameBytes or '\0' in name:
    fail("workspace name is invalid")
  model.tags[tagId].name = name

proc pruneDynamicWorkspaces*(model: var PolicyModel): seq[TagId] =
  ## Dynamic workspace slots are reusable, but their logical TagId and ViewId
  ## identities never are. Only inactive, unoccupied workspaces may disappear.
  let tagIds = model.tags.ids
  for tagId in tagIds:
    if model.tags[tagId].kind != TagKind.dynamic or model.workspaceOccupied(tagId):
      continue
    var active = false
    for outputId in model.outputOrder:
      if tagId in model.viewTagIds(model.outputs[outputId].activeView):
        active = true
        break
    if active:
      continue
    var removedViews: seq[ViewId]
    for viewId in model.views.ids:
      if tagId in model.viewTagIds(viewId):
        removedViews.add(viewId)
    for viewId in removedViews:
      for outputId in model.outputOrder:
        model.outputs[outputId].views.keepItIf(it != viewId)
      for outputId in model.affinityOrder:
        model.affinities[outputId].views.keepItIf(it != viewId)
        if model.affinities[outputId].activeView == viewId:
          if model.affinities[outputId].views.len == 0:
            fail("dynamic workspace removal detached an output affinity")
          model.affinities[outputId].activeView = model.affinities[outputId].views[0]
      model.viewTags.del(viewId)
      model.views.del(viewId)
    model.tags.del(tagId)
    result.add(tagId)

proc setWindowTags*(model: var PolicyModel, id: WindowId, tags: TagMask) =
  if tags == emptyTagMask:
    fail("a window must retain at least one tag")
  if id notin model.windows:
    fail("window does not exist")
  model.windowTags[id] = model.tagIdsForMask(tags)
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow != id:
      continue
    let activeView = model.outputs[outputId].activeView
    if id != model.visibleScratchpad and
        not model.windowTagIds(id).intersects(model.viewTagIds(activeView)):
      model.outputs[outputId].focusedWindow = nullWindowId
  discard model.pruneDynamicWorkspaces()

proc setWindowTagIds*(model: var PolicyModel, id: WindowId, tags: openArray[TagId]) =
  if tags.len == 0 or id notin model.windows:
    fail("a window must retain at least one valid tag")
  var unique: seq[TagId]
  for tagId in tags:
    if tagId notin model.tags:
      fail("window membership names an unknown tag")
    if model.tags[tagId].kind == TagKind.scratchpad and id notin model.scratchpadRestore:
      fail("private scratchpad membership lacks restore state")
    if tagId notin unique:
      unique.add(tagId)
  model.windowTags[id] = unique
  for outputId in model.outputOrder:
    if model.outputs[outputId].focusedWindow == id and id != model.visibleScratchpad and
        not unique.intersects(model.viewTagIds(model.outputs[outputId].activeView)):
      model.outputs[outputId].focusedWindow = nullWindowId
  discard model.pruneDynamicWorkspaces()

proc setViewTags*(
    model: var PolicyModel, outputId: OutputId, viewId: ViewId, tags: TagMask
) =
  if tags == emptyTagMask:
    fail("a view must retain at least one tag")
  if outputId notin model.outputs or viewId notin model.outputs[outputId].views:
    fail("view does not belong to the output")
  model.viewTags[viewId] = model.tagIdsForMask(tags)
  if model.outputs[outputId].activeView != viewId:
    return
  let focus = model.outputs[outputId].focusedWindow
  if focus != nullWindowId and focus != model.visibleScratchpad and
      not model.windowTagIds(focus).intersects(model.viewTagIds(viewId)):
    model.outputs[outputId].focusedWindow = nullWindowId

proc setViewTagIds*(
    model: var PolicyModel, outputId: OutputId, viewId: ViewId, tags: openArray[TagId]
) =
  if tags.len == 0 or outputId notin model.outputs or
      viewId notin model.outputs[outputId].views:
    fail("a view must retain at least one valid tag")
  var unique: seq[TagId]
  for tagId in tags:
    if tagId notin model.tags or model.tags[tagId].kind == TagKind.scratchpad:
      fail("view membership names an unknown tag")
    if tagId notin unique:
      unique.add(tagId)
  model.viewTags[viewId] = unique
  if model.outputs[outputId].activeView == viewId:
    let focus = model.outputs[outputId].focusedWindow
    if focus != nullWindowId and focus != model.visibleScratchpad and
        not model.windowTagIds(focus).intersects(unique):
      model.outputs[outputId].focusedWindow = nullWindowId
