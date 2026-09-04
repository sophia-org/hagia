import std/[sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[id_gen, queries, values]

import ./tag_ops

## View lifecycle over an output's ordered view list.

proc addView*(model: var PolicyModel, outputId: OutputId, tags: TagMask): ViewId =
  if tags == emptyTagMask:
    fail("a view must select at least one tag")
  if outputId notin model.outputs:
    fail("view output does not exist")
  result = model.allocateViewId()
  model.views[result] = ViewData(
    id: result, preferredOutput: outputId, layout: model.settings.layoutCycle[0]
  )
  model.viewTags[result] = model.tagIdsForMask(tags)
  model.outputs[outputId].views.add(result)

proc addView*(
    model: var PolicyModel, outputId: OutputId, tags: openArray[TagId]
): ViewId =
  if tags.len == 0:
    fail("a view must select at least one tag")
  if outputId notin model.outputs:
    fail("view output does not exist")
  for tagId in tags:
    if tagId notin model.tags or model.tags[tagId].kind == TagKind.scratchpad:
      fail("view membership names an unknown tag")
  result = model.allocateViewId()
  model.views[result] = ViewData(
    id: result, preferredOutput: outputId, layout: model.settings.layoutCycle[0]
  )
  model.viewTags[result] = @tags
  model.outputs[outputId].views.add(result)

proc removeView*(model: var PolicyModel, viewId: ViewId) =
  if viewId notin model.views:
    return
  for outputId in model.outputOrder:
    if model.outputs[outputId].activeView == viewId:
      fail("active configured view must be replaced before removal")
    model.outputs[outputId].views.keepItIf(it != viewId)
  for outputId in model.affinityOrder:
    model.affinities[outputId].views.keepItIf(it != viewId)
    if model.affinities[outputId].activeView == viewId:
      if model.affinities[outputId].views.len == 0:
        fail("configured view removal detached an output affinity")
      model.affinities[outputId].activeView = model.affinities[outputId].views[0]
  model.viewTags.del(viewId)
  model.views.del(viewId)

proc ensureViewCount*(model: var PolicyModel, outputId: OutputId, count: int) =
  if outputId notin model.outputs or count < 1 or count > 9:
    fail("view profile is outside Hagia's bounded range")
  for slot in 1'u32 .. uint32(count):
    if model.profileViewForSlot(outputId, slot) == nullViewId:
      discard model.addView(outputId, [model.profileTag(slot)])
