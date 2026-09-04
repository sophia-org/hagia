import std/[options, tables]

import ../types/[core, model]
import ../policy/entity_store
import ./values

## Read-only questions about a `PolicyModel`. A query never mutates; it answers
## from the indexes that `src/entities` maintains.

proc nextTagSlot*(model: PolicyModel): uint32 =
  for _, tag in model.tags.pairs:
    result = max(result, tag.slot)

proc outputIds*(model: PolicyModel): seq[OutputId] =
  model.outputOrder

proc windowIds*(model: PolicyModel): seq[WindowId] =
  model.windowOrder

proc output*(model: PolicyModel, id: OutputId): Option[OutputData] =
  if id in model.outputs:
    some(model.outputs[id])
  else:
    none(OutputData)

proc window*(model: PolicyModel, id: WindowId): Option[WindowData] =
  if id in model.windows:
    some(model.windows[id])
  else:
    none(WindowData)

proc view*(model: PolicyModel, id: ViewId): Option[ViewData] =
  if id in model.views:
    some(model.views[id])
  else:
    none(ViewData)

proc affinity*(model: PolicyModel, id: OutputId): Option[OutputAffinity] =
  if id in model.affinities:
    some(model.affinities[id])
  else:
    none(OutputAffinity)

proc windowTagIds*(model: PolicyModel, id: WindowId): seq[TagId] =
  if id in model.windowTags:
    model.windowTags[id]
  else:
    @[]

proc viewTagIds*(model: PolicyModel, id: ViewId): seq[TagId] =
  if id in model.viewTags:
    model.viewTags[id]
  else:
    @[]

proc tagsToMask*(model: PolicyModel, tags: openArray[TagId]): TagMask =
  var bits = 0'u64
  for tagId in tags:
    if tagId notin model.tags:
      fail("tag membership names an unknown tag")
    let slot = model.tags[tagId].slot
    if slot == 0 or slot > maxTagBits:
      fail("tag slot is outside Hagia's bounded range")
    bits = bits or uint64(tagForSlot(slot))
  TagMask(bits)

proc windowTagMask*(model: PolicyModel, id: WindowId): TagMask =
  model.tagsToMask(model.windowTagIds(id))

proc viewTagMask*(model: PolicyModel, id: ViewId): TagMask =
  model.tagsToMask(model.viewTagIds(id))

proc tagIdForSlot*(model: PolicyModel, slot: uint32): TagId =
  if slot == 0 or slot > maxTagBits:
    return nullTagId
  for tagId, tag in model.tags.pairs:
    if tag.slot == slot:
      return tagId
  nullTagId

proc workspaceOccupied*(model: PolicyModel, tagId: TagId): bool =
  if tagId notin model.tags:
    return false
  for windowId in model.windowOrder:
    if tagId in model.windowTagIds(windowId):
      return true
  for _, restore in model.scratchpadRestore.pairs:
    if tagId in restore.tags:
      return true

proc nextDynamicWorkspaceSlot*(model: PolicyModel): uint32 =
  let first = uint32(model.settings.viewCount + 1)
  if first > maxWorkspaceTagSlot:
    return 0
  for slot in first .. maxWorkspaceTagSlot:
    if model.tagIdForSlot(slot) == nullTagId:
      return slot

proc profileViewForSlot*(model: PolicyModel, outputId: OutputId, slot: uint32): ViewId =
  for viewId in model.outputs[outputId].views:
    let tags = model.viewTagIds(viewId)
    if tags.len == 1 and model.tags[tags[0]].kind == TagKind.profile and
        model.tags[tags[0]].slot == slot:
      return viewId
  nullViewId

proc eligibleWindows*(model: PolicyModel, outputId: OutputId): seq[WindowId] =
  let output = model.output(outputId)
  if output.isNone:
    fail("projection output does not exist")
  let view = model.view(output.get().activeView)
  if view.isNone:
    fail("projection output has no active view")
  for windowId in model.windowOrder:
    let window = model.windows[windowId]
    if window.kind != WindowKind.popup and window.homeOutput == outputId and (
      windowId == model.visibleScratchpad or
      model.windowTagIds(windowId).intersects(model.viewTagIds(view.get().id))
    ):
      result.add(windowId)
