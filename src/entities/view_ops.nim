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

proc rememberViewportOffset*(
    model: var PolicyModel, outputId: OutputId, offset: int32, camera = CameraAnchor()
) =
  ## Record where the scroller camera ended up on the view this output is
  ## showing. The projection decides the position; this is what makes the next
  ## projection start from it rather than from the configured offset.
  if outputId notin model.outputs:
    return
  let viewId = model.outputs[outputId].activeView
  if viewId in model.views:
    # The camera that produced this offset scrolled along one axis, and the
    # layout says which, so the offset lands in the field for that axis and
    # the other axis keeps its own place.
    if model.views[viewId].layout == LayoutMode.verticalScroller:
      model.views[viewId].viewportOffsetY = offset
      model.views[viewId].cameraY = camera
    else:
      model.views[viewId].viewportOffset = offset
      model.views[viewId].camera = camera
    # The intent has been resolved into the offset above, so it is spent. A
    # camera action moves the view once; it does not pin it there.
    model.views[viewId].cameraIntent = CameraIntent.none

proc requestCamera*(model: var PolicyModel, outputId: OutputId, intent: CameraIntent) =
  ## Ask the next projection to move the camera somewhere named.
  ##
  ## The strip geometry only exists inside the projection, so an action that
  ## wants to centre something records what it wants rather than working out
  ## where that is. The request is spent when the projection resolves it.
  if outputId notin model.outputs:
    return
  let viewId = model.outputs[outputId].activeView
  if viewId in model.views:
    model.views[viewId].cameraIntent = intent
