import std/[options, sequtils, tables]

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

proc tiledColumnIds*(model: PolicyModel, outputId: OutputId): seq[ColumnId] =
  ## Columns homed to an output, in the order a scroller lays them left to
  ## right. Emptiness is not judged here; ask `columnWindows` for that.
  for columnId in model.columnOrder:
    if model.columns[columnId].homeOutput == outputId:
      result.add(columnId)

proc columnWindows*(
    model: PolicyModel, columnId: ColumnId, eligible: openArray[WindowId]
): seq[WindowId] =
  ## The windows a projection stacks in one column, top to bottom: those the
  ## caller found eligible, minus the floating ones a layout never positions.
  for windowId in model.columns[columnId].windows:
    if windowId in eligible and not model.windows[windowId].floating:
      result.add(windowId)

proc visibleColumnIds*(model: PolicyModel, outputId: OutputId): seq[ColumnId] =
  ## The columns a layout would actually draw on an output: those holding at
  ## least one window the projection places.
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
  for columnId in model.tiledColumnIds(outputId):
    if model.columnWindows(columnId, eligible).len > 0:
      result.add(columnId)

proc visibleColumns*(model: PolicyModel, outputId: OutputId): seq[seq[WindowId]] =
  ## The same columns as `visibleColumnIds`, in the same order, as their
  ## ordered windows. Focus and movement both have to agree with what the user
  ## sees, so they ask this one question rather than each filtering their own.
  let eligible =
    model.eligibleWindows(outputId).filterIt(not model.windows[it].minimized)
  for columnId in model.tiledColumnIds(outputId):
    let windows = model.columnWindows(columnId, eligible)
    if windows.len > 0:
      result.add(windows)
