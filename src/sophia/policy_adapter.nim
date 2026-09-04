import std/[algorithm, json, jsonutils, options, sets, strutils, tables]

import ../types/config_values
import ../config/policy_candidate
import ../types/observability
import ../observability
import ../types/[core, model, policy_messages, projection]
import ../policy/[actions, entity_store, projection, reducer, state]
import ../types/wm_v1
import ../types/session
import ./snapshot_convert

export PolicyAdapterError

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyAdapterError, message)

type
  PolicyAdapter* = object
    model: PolicyModel
    surfaceToWindow: Table[uint64, WindowId]
    windowToSurface: Table[WindowId, uint64]
    outputToLogical: Table[uint64, OutputId]
    activeOutputToLogical: Table[OutputHandle, OutputId]
    dormantOutputToLogical: Table[OutputHandle, OutputId]
    logicalToOutput: Table[OutputId, OutputHandle]
    surfaceFacts: Table[WindowId, SnapshotSurface]

  TagRelationDto = object
    owner: uint32
    tags: seq[uint32]

  SurfaceDto = object
    key: uint64
    window: uint32
    facts: SnapshotSurface

  OutputDto = object
    output: uint64
    generation: uint64
    logical: uint32

  ScratchpadRestoreDto = object
    window: uint32
    restore: ScratchpadRestoreData

  NamedScratchpadDto = object
    slot: uint32
    window: uint32

  CheckpointV2Dto = object
    schema: uint32
    counters: IdCounters
    settings: PolicySettings
    activeOutput: uint32
    windows: seq[WindowData]
    windowOrder: seq[uint32]
    columns: seq[ColumnData]
    columnOrder: seq[uint32]
    views: seq[ViewData]
    tags: seq[TagData]
    outputs: seq[OutputData]
    outputOrder: seq[uint32]
    windowTags: seq[TagRelationDto]
    viewTags: seq[TagRelationDto]
    minimizedOrder: seq[uint32]
    affinities: seq[OutputAffinity]
    affinityOrder: seq[uint32]
    scratchpadOrder: seq[uint32]
    scratchpadRestore: seq[ScratchpadRestoreDto]
    namedScratchpads: seq[NamedScratchpadDto]
    visibleScratchpad: uint32
    scratchpadTag: uint32
    surfaces: seq[SurfaceDto]
    activeOutputs: seq[OutputDto]
    dormantOutputs: seq[OutputDto]

proc applyPolicyCandidate*(adapter: var PolicyAdapter, candidate: AuthorityCandidate)

proc initPolicyAdapter*(): PolicyAdapter =
  PolicyAdapter(model: initPolicyModel())

proc initPolicyAdapter*(candidate: AuthorityCandidate): PolicyAdapter =
  result = initPolicyAdapter()
  result.applyPolicyCandidate(candidate)

proc applyPolicyCandidate*(adapter: var PolicyAdapter, candidate: AuthorityCandidate) =
  var prepared = adapter.model.clone()
  prepared.applyPolicyCandidate(candidate)
  prepared.reconcilePolicySettings()
  prepared.validate()
  adapter.model = prepared

proc clone*(adapter: PolicyAdapter): PolicyAdapter =
  result.model = adapter.model.clone()
  for key, value in adapter.surfaceToWindow.pairs:
    result.surfaceToWindow[key] = value
  for key, value in adapter.windowToSurface.pairs:
    result.windowToSurface[key] = value
  for key, value in adapter.outputToLogical.pairs:
    result.outputToLogical[key] = value
  for key, value in adapter.activeOutputToLogical.pairs:
    result.activeOutputToLogical[key] = value
  for key, value in adapter.dormantOutputToLogical.pairs:
    result.dormantOutputToLogical[key] = value
  for key, value in adapter.logicalToOutput.pairs:
    result.logicalToOutput[key] = value
  for key, value in adapter.surfaceFacts.pairs:
    result.surfaceFacts[key] = value

proc logicalWindow*(
    adapter: PolicyAdapter, surfaceIndex, surfaceGeneration: uint32
): Option[WindowId] =
  let key = surfaceKey(surfaceIndex, surfaceGeneration)
  if key in adapter.surfaceToWindow:
    some(adapter.surfaceToWindow[key])
  else:
    none(WindowId)

proc logicalOutput*(adapter: PolicyAdapter, output: uint64): Option[OutputId] =
  if output in adapter.outputToLogical:
    some(adapter.outputToLogical[output])
  else:
    none(OutputId)

proc model*(adapter: PolicyAdapter): PolicyModel =
  adapter.model

proc hasWindows*(adapter: PolicyAdapter): bool =
  adapter.model.windowOrder.len > 0

proc checkpointDto(adapter: PolicyAdapter): CheckpointV2Dto =
  result.schema = 2
  result.counters = adapter.model.counters
  result.settings = adapter.model.settings
  result.activeOutput = uint32(adapter.model.activeOutput)
  for _, window in adapter.model.windows.pairs:
    result.windows.add(window)
  result.windows.sort(idOrder[WindowData])
  for id in adapter.model.windowOrder:
    result.windowOrder.add(uint32(id))
  for _, column in adapter.model.columns.pairs:
    result.columns.add(column)
  result.columns.sort(idOrder[ColumnData])
  for id in adapter.model.columnOrder:
    result.columnOrder.add(uint32(id))
  for _, view in adapter.model.views.pairs:
    result.views.add(view)
  result.views.sort(idOrder[ViewData])
  for _, tag in adapter.model.tags.pairs:
    result.tags.add(tag)
  result.tags.sort(idOrder[TagData])
  for _, output in adapter.model.outputs.pairs:
    result.outputs.add(output)
  result.outputs.sort(idOrder[OutputData])
  for id in adapter.model.outputOrder:
    result.outputOrder.add(uint32(id))
  for id in adapter.model.windowOrder:
    var relation = TagRelationDto(owner: uint32(id))
    for tag in adapter.model.windowTagIds(id):
      relation.tags.add(uint32(tag))
    relation.tags.sort()
    result.windowTags.add(relation)
  var viewIds = adapter.model.views.ids
  viewIds.sort(
    proc(left, right: ViewId): int =
      cmp(uint32(left), uint32(right))
  )
  for id in viewIds:
    var relation = TagRelationDto(owner: uint32(id))
    for tag in adapter.model.viewTagIds(id):
      relation.tags.add(uint32(tag))
    relation.tags.sort()
    result.viewTags.add(relation)
  for id in adapter.model.minimizedOrder:
    result.minimizedOrder.add(uint32(id))
  for id in adapter.model.affinityOrder:
    result.affinities.add(adapter.model.affinities[id])
    result.affinityOrder.add(uint32(id))
  for id in adapter.model.scratchpadOrder:
    result.scratchpadOrder.add(uint32(id))
    result.scratchpadRestore.add(
      ScratchpadRestoreDto(
        window: uint32(id), restore: adapter.model.scratchpadRestore[id]
      )
    )
  for slot, window in adapter.model.namedScratchpads.pairs:
    result.namedScratchpads.add(
      NamedScratchpadDto(slot: uint32(slot), window: uint32(window))
    )
  result.namedScratchpads.sort(
    proc(left, right: NamedScratchpadDto): int =
      cmp(left.slot, right.slot)
  )
  result.visibleScratchpad = uint32(adapter.model.visibleScratchpad)
  result.scratchpadTag = uint32(adapter.model.scratchpadTag)
  for key, window in adapter.surfaceToWindow.pairs:
    result.surfaces.add(
      SurfaceDto(key: key, window: uint32(window), facts: adapter.surfaceFacts[window])
    )
  result.surfaces.sort(
    proc(left, right: SurfaceDto): int =
      cmp(left.window, right.window)
  )
  for handle, logical in adapter.activeOutputToLogical.pairs:
    result.activeOutputs.add(
      OutputDto(
        output: handle.output, generation: handle.generation, logical: uint32(logical)
      )
    )
  result.activeOutputs.sort(
    proc(left, right: OutputDto): int =
      cmp(left.logical, right.logical)
  )
  for handle, logical in adapter.dormantOutputToLogical.pairs:
    result.dormantOutputs.add(
      OutputDto(
        output: handle.output, generation: handle.generation, logical: uint32(logical)
      )
    )
  result.dormantOutputs.sort(
    proc(left, right: OutputDto): int =
      cmp(left.logical, right.logical)
  )

proc checkpointPayload*(adapter: PolicyAdapter): string =
  "HAGIA-POLICY-CHECKPOINT-2\n" & $adapter.checkpointDto().toJson()

proc restoreCheckpointPayload*(payload: string): PolicyAdapter =
  const prefix = "HAGIA-POLICY-CHECKPOINT-2\n"
  if payload.startsWith("HAGIA-POLICY-CHECKPOINT-1\n"):
    fail("policy checkpoint v1 is unsupported; a complete snapshot will rebuild it")
  if not payload.startsWith(prefix):
    fail("policy checkpoint version is invalid")
  var dto: CheckpointV2Dto
  try:
    dto = payload[prefix.len .. ^1].parseJson().jsonTo(CheckpointV2Dto)
  except CatchableError:
    fail("policy checkpoint payload is malformed")
  if dto.schema != 2:
    fail("policy checkpoint schema is invalid")
  result.model.counters = dto.counters
  if dto.settings.layoutCycle.len == 0:
    dto.settings.layoutCycle = defaultLayoutCycle
  result.model.settings = dto.settings
  result.model.activeOutput = OutputId(dto.activeOutput)
  for window in dto.windows:
    result.model.windows[window.id] = window
  for raw in dto.windowOrder:
    result.model.windowOrder.add(WindowId(raw))
  for column in dto.columns:
    result.model.columns[column.id] = column
  for raw in dto.columnOrder:
    result.model.columnOrder.add(ColumnId(raw))
  for view in dto.views:
    result.model.views[view.id] = view
  for tag in dto.tags:
    result.model.tags[tag.id] = tag
  for output in dto.outputs:
    result.model.outputs[output.id] = output
  for raw in dto.outputOrder:
    result.model.outputOrder.add(OutputId(raw))
  for relation in dto.windowTags:
    let owner = WindowId(relation.owner)
    for raw in relation.tags:
      result.model.windowTags.mgetOrPut(owner, @[]).add(TagId(raw))
  for relation in dto.viewTags:
    let owner = ViewId(relation.owner)
    for raw in relation.tags:
      result.model.viewTags.mgetOrPut(owner, @[]).add(TagId(raw))
  for raw in dto.minimizedOrder:
    result.model.minimizedOrder.add(WindowId(raw))
  if dto.scratchpadOrder.len != dto.scratchpadRestore.len:
    fail("policy checkpoint scratchpad records diverged")
  for index, raw in dto.scratchpadOrder:
    let id = WindowId(raw)
    if dto.scratchpadRestore[index].window != raw:
      fail("policy checkpoint scratchpad order is invalid")
    result.model.scratchpadOrder.add(id)
    result.model.scratchpadRestore[id] = dto.scratchpadRestore[index].restore
  for relation in dto.namedScratchpads:
    result.model.namedScratchpads[ScratchpadSlotId(relation.slot)] =
      WindowId(relation.window)
  result.model.visibleScratchpad = WindowId(dto.visibleScratchpad)
  result.model.scratchpadTag = TagId(dto.scratchpadTag)
  if dto.affinities.len != dto.affinityOrder.len:
    fail("policy checkpoint affinity records diverged")
  for index, raw in dto.affinityOrder:
    let id = OutputId(raw)
    result.model.affinities[id] = dto.affinities[index]
    result.model.affinityOrder.add(id)
  for surface in dto.surfaces:
    let window = WindowId(surface.window)
    result.surfaceToWindow[surface.key] = window
    result.windowToSurface[window] = surface.key
    result.surfaceFacts[window] = surface.facts
  for output in dto.activeOutputs:
    let handle = (output: output.output, generation: output.generation)
    let logical = OutputId(output.logical)
    result.activeOutputToLogical[handle] = logical
    result.outputToLogical[output.output] = logical
    result.logicalToOutput[logical] = handle
  for output in dto.dormantOutputs:
    result.dormantOutputToLogical[
      (output: output.output, generation: output.generation)
    ] = OutputId(output.logical)
  result.model.validate()
  if result.surfaceToWindow.len > maxSurfaces or
      result.surfaceToWindow.len != result.windowToSurface.len or
      result.surfaceToWindow.len != result.surfaceFacts.len or
      result.surfaceToWindow.len != result.model.windows.len or
      result.activeOutputToLogical.len > maxOutputs or
      result.activeOutputToLogical.len != result.outputToLogical.len or
      result.activeOutputToLogical.len != result.logicalToOutput.len or
      result.activeOutputToLogical.len != result.model.outputs.len or
      result.dormantOutputToLogical.len > maxOutputAffinities or
      result.dormantOutputToLogical.len != result.model.affinities.len:
    fail("policy checkpoint exceeds bounded identities")
  for key, window in result.surfaceToWindow.pairs:
    if window notin result.model.windows or window notin result.windowToSurface or
        result.windowToSurface[window] != key:
      fail("policy checkpoint surface indexes diverged")
  for window, key in result.windowToSurface.pairs:
    if key notin result.surfaceToWindow or result.surfaceToWindow[key] != window or
        window notin result.surfaceFacts or
        result.surfaceFacts[window].surfaceKey() != key:
      fail("policy checkpoint reverse surface index diverged")
  for handle, output in result.activeOutputToLogical.pairs:
    if output notin result.model.outputs or output notin result.logicalToOutput or
        result.logicalToOutput[output] != handle or
        result.outputToLogical.getOrDefault(handle.output) != output:
      fail("policy checkpoint active output indexes diverged")
  for handle, output in result.dormantOutputToLogical.pairs:
    if output notin result.model.affinities or output in result.logicalToOutput:
      fail("policy checkpoint dormant output indexes diverged")
  for rawOutput, output in result.outputToLogical.pairs:
    if output notin result.logicalToOutput or
        result.logicalToOutput[output].output != rawOutput:
      fail("policy checkpoint raw output indexes diverged")
  for output in result.model.affinityOrder:
    var found = false
    for _, dormantOutput in result.dormantOutputToLogical.pairs:
      if dormantOutput == output:
        if found:
          fail("policy checkpoint dormant output is ambiguous")
        found = true
    if not found:
      fail("policy checkpoint output affinity has no opaque handle")

proc applyCause*(adapter: var PolicyAdapter, request: ProjectionRequest) =
  if request.affectedOutputs.len == 0:
    fail("policy cause has no affected output")
  let rawOutput = request.affectedOutputs[0]
  if rawOutput notin adapter.outputToLogical:
    fail("policy cause names an unknown output")
  let output = adapter.model.activeOutput
  var message = PolicyMsg(kind: PolicyMsgKind.sceneChanged, output: output)
  case request.cause.kind
  of ProjectionCauseKind.sceneChanged:
    discard
  of ProjectionCauseKind.action:
    if request.cause.activationSerial == 0 or not request.cause.action.isPolicyAction():
      fail("policy action cause is invalid")
    message = PolicyMsg(
      kind: PolicyMsgKind.action,
      output: output,
      action: request.cause.action.policyAction(),
    )
  of ProjectionCauseKind.focus:
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy focus cause names an unknown surface")
    let window = adapter.surfaceToWindow[key]
    message = PolicyMsg(
      kind: PolicyMsgKind.focus,
      output: adapter.model.windows[window].homeOutput,
      focusWindow: window,
    )
  of ProjectionCauseKind.interaction:
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy interaction cause names an unknown surface")
    let window = adapter.surfaceToWindow[key]
    let interactionOutput = adapter.model.windows[window].homeOutput
    let geometry = Rect(
      x: request.cause.x,
      y: request.cause.y,
      width: request.cause.width,
      height: request.cause.height,
    )
    if request.cause.interactionPhase == InteractionPhase.cancel:
      message = PolicyMsg(kind: PolicyMsgKind.sceneChanged, output: interactionOutput)
      adapter.model = adapter.model.reducePolicy(message).candidate
      recordEvidence(
        EvidenceEvent(
          kind: EvidenceKind.reducer,
          event: "interaction",
          epoch: request.connectionEpoch,
          generation: request.policyGeneration,
          requestId: request.requestId,
          status: $request.cause.interactionPhase,
        )
      )
      return
    case request.cause.interactionKind
    of InteractionKind.move:
      message = PolicyMsg(
        kind: PolicyMsgKind.interaction,
        output: interactionOutput,
        interactionWindow: window,
        interactionKind: PolicyInteractionKind.move,
        geometry: geometry,
      )
    of InteractionKind.resize:
      message = PolicyMsg(
        kind: PolicyMsgKind.interaction,
        output: interactionOutput,
        interactionWindow: window,
        interactionKind: PolicyInteractionKind.resize,
        geometry: geometry,
      )
    of InteractionKind.drag:
      message = PolicyMsg(
        kind: PolicyMsgKind.interaction,
        output: interactionOutput,
        interactionWindow: window,
        interactionKind: PolicyInteractionKind.move,
        geometry: geometry,
      )
    of InteractionKind.scroll:
      fail("policy interaction kind is not implemented")
    else:
      fail("policy interaction kind is invalid")
  adapter.model = adapter.model.reducePolicy(message).candidate
  recordEvidence(
    EvidenceEvent(
      kind: EvidenceKind.reducer,
      event: "cause_applied",
      epoch: request.connectionEpoch,
      generation: request.policyGeneration,
      requestId: request.requestId,
      status: $message.kind,
    )
  )

## Reconcile only complete Sophia snapshots. The policy model never observes a
## partial transfer or stores a Sophia identity in its own entity tables.
proc reconcile*(adapter: var PolicyAdapter, snapshot: PolicySnapshot) =
  if snapshot.generation == 0 or snapshot.outputs.len == 0:
    fail("Sophia snapshot is empty")
  if snapshot.activeOutput == 0:
    fail("Sophia snapshot has no active output")

  var previousActive: seq[(OutputHandle, OutputId)]
  for output, logical in adapter.activeOutputToLogical.pairs:
    previousActive.add((output, logical))
  var liveOutputs = initHashSet[OutputHandle]()
  for output in snapshot.outputs:
    let current = output.handle()
    liveOutputs.incl(current)
    var logical: OutputId
    if current in adapter.activeOutputToLogical:
      logical = adapter.activeOutputToLogical[current]
      adapter.model.updateOutput(logical, output.bounds())
    elif current in adapter.dormantOutputToLogical:
      logical = adapter.dormantOutputToLogical[current]
      adapter.model.restoreOutput(logical, output.bounds())
      adapter.dormantOutputToLogical.del(current)
    else:
      logical = adapter.model.addOutput(output.bounds())
      adapter.model.ensureViewCount(logical, adapter.model.settings.viewCount)
    adapter.activeOutputToLogical[current] = logical
    adapter.outputToLogical[output.output] = logical
    adapter.logicalToOutput[logical] = current
  if snapshot.activeOutput notin adapter.outputToLogical:
    fail("Sophia snapshot active output is not live")
  adapter.model.setActiveOutput(adapter.outputToLogical[snapshot.activeOutput])

  var launchClassifications = initTable[uint64, uint64]()
  for classification in snapshot.classifications:
    launchClassifications[
      surfaceKey(classification.surfaceIndex, classification.surfaceGeneration)
    ] = classification.classification

  let fallback = adapter.outputToLogical[snapshot.outputs[0].output]
  for item in previousActive:
    let (output, logical) = item
    if output in liveOutputs:
      continue
    let evicted = adapter.model.removeOutput(logical, fallback)
    adapter.activeOutputToLogical.del(output)
    adapter.dormantOutputToLogical[output] = logical
    if output.output in adapter.outputToLogical and
        adapter.outputToLogical[output.output] == logical:
      adapter.outputToLogical.del(output.output)
    adapter.logicalToOutput.del(logical)
    if evicted.isSome:
      var evictedHandles: seq[OutputHandle]
      for handle, dormantLogical in adapter.dormantOutputToLogical.pairs:
        if dormantLogical == evicted.get():
          evictedHandles.add(handle)
      for handle in evictedHandles:
        adapter.dormantOutputToLogical.del(handle)

  var liveSurfaces = initHashSet[uint64]()
  for surface in snapshot.surfaces:
    let key = surface.surfaceKey()
    liveSurfaces.incl(key)
    if key in adapter.surfaceToWindow:
      let window = adapter.surfaceToWindow[key]
      adapter.model.updateWindowFacts(
        window, surface.capabilityBits.capabilities(), surface.constraints()
      )
      adapter.model.applyPresentation(window, surface.currentStateBits)
      if surface.currentOutput != 0:
        adapter.model.adoptWindowOutput(
          window, adapter.outputToLogical[surface.currentOutput]
        )
      adapter.surfaceFacts[window] = surface
    else:
      let rawHome =
        if key in launchClassifications:
          snapshot.activeOutput
        elif surface.currentOutput != 0:
          surface.currentOutput
        else:
          snapshot.outputs[0].output
      if rawHome notin adapter.outputToLogical:
        fail("surface home output is not present")
      let window = adapter.model.addWindow(
        adapter.outputToLogical[rawHome],
        surface.capabilityBits.capabilities(),
        surface.constraints(),
      )
      adapter.surfaceToWindow[key] = window
      adapter.windowToSurface[window] = key
      adapter.surfaceFacts[window] = surface
      adapter.model.applyPresentation(window, surface.currentStateBits)
      if key in launchClassifications:
        let classification = launchClassifications[key]
        # Hagia's retained daily-driver vocabulary maps classes 1..9 to its
        # corresponding view slots. Unknown opaque classes are advisory and
        # remain intentionally ignorable.
        if classification >= 1 and classification <= uint64(high(int)) and
            int(classification) <= adapter.model.settings.viewCount:
          adapter.model.placeWindowInViewSlot(
            window, adapter.outputToLogical[snapshot.activeOutput], int(classification)
          )

  var removedSurfaces: seq[uint64]
  for key in adapter.surfaceToWindow.keys:
    if key notin liveSurfaces:
      removedSurfaces.add(key)
  for key in removedSurfaces:
    let window = adapter.surfaceToWindow[key]
    adapter.model.removeWindow(window)
    adapter.surfaceToWindow.del(key)
    adapter.windowToSurface.del(window)
    adapter.surfaceFacts.del(window)

  # Resolve reduced transient ownership only after every live Sophia handle has
  # a stable logical identity. No generational handle crosses this boundary.
  for surface in snapshot.surfaces:
    let window = adapter.surfaceToWindow[surface.surfaceKey()]
    var parent = nullWindowId
    if surface.transientGeneration != 0:
      let parentKey = surfaceKey(surface.transientIndex, surface.transientGeneration)
      if parentKey notin adapter.surfaceToWindow:
        fail("surface transient owner has no logical identity")
      parent = adapter.surfaceToWindow[parentKey]
    let kind = surface.kind.windowKind()
    let relationChanged =
      adapter.model.windows[window].kind != kind or
      adapter.model.windows[window].parent != parent
    adapter.model.setWindowRelation(window, kind, parent)
    let inheritanceChanged =
      parent != nullWindowId and (
        adapter.model.windows[window].homeOutput !=
        adapter.model.windows[parent].homeOutput or
        adapter.model.windowTagIds(window) != adapter.model.windowTagIds(parent)
      )
    if (relationChanged or inheritanceChanged) and parent != nullWindowId and
        kind in {WindowKind.dialog, WindowKind.utility} and
        window notin adapter.model.scratchpadRestore:
      let parentOutput = adapter.model.windows[parent].homeOutput
      let parentBounds = adapter.model.outputs[parentOutput].bounds
      let parentFacts = adapter.surfaceFacts[parent]
      adapter.model.placeTransient(
        window,
        parent,
        (if surface.width > 0: surface.width
        else: parentBounds.width div 2),
        (if surface.height > 0: surface.height
        else: parentBounds.height div 2),
        Rect(
          x: parentFacts.x,
          y: parentFacts.y,
          width: parentFacts.width,
          height: parentFacts.height,
        ),
      )

  for output in snapshot.outputs:
    if output.focusGeneration == 0:
      adapter.model.clearFocus(adapter.outputToLogical[output.output])
      continue
    let key = surfaceKey(output.focusIndex, output.focusGeneration)
    if key in adapter.surfaceToWindow:
      let window = adapter.surfaceToWindow[key]
      try:
        adapter.model.setFocus(adapter.outputToLogical[output.output], window)
      except PolicyStateError:
        discard
  adapter.model.validate()

proc projection*(
    adapter: PolicyAdapter, snapshot: PolicySnapshot, request: ProjectionRequest
): PolicyProjection =
  if request.sceneGeneration != snapshot.generation:
    fail("projection request names a stale snapshot")
  result.activeOutput = snapshot.activeOutput
  var affected: seq[OutputId]
  for output in request.affectedOutputs:
    if output notin adapter.outputToLogical:
      fail("projection request names an unknown output")
    affected.add(adapter.outputToLogical[output])

  for logical in adapter.model.projectLayout(
    affected, adapter.model.settings.outerGap, adapter.model.settings.innerGap,
    adapter.model.settings.viewportOffset,
  ):
    let rawOutput = adapter.logicalToOutput[logical.output].output
    var outputSnapshot: SnapshotOutput
    var foundOutput = false
    for candidate in snapshot.outputs:
      if candidate.output == rawOutput:
        outputSnapshot = candidate
        foundOutput = true
        break
    if not foundOutput:
      fail("logical output has no current Sophia record")
    var output = ProjectionOutput(
      output: rawOutput, placementCount: uint32(logical.placements.len)
    )
    if logical.focus != nullWindowId:
      let key = adapter.windowToSurface[logical.focus]
      output.focusIndex = uint32(key and 0xffffffff'u64)
      output.focusGeneration = uint32(key shr 32)
    var projection = PolicyOutputProjection(output: output)
    for placement in logical.placements:
      if placement.window notin adapter.surfaceFacts:
        fail("logical window has no current Sophia facts")
      let surface = adapter.surfaceFacts[placement.window]
      let window = adapter.model.windows[placement.window]
      var geometry = placement.geometry
      if window.fullscreen:
        geometry = Rect(
          x: outputSnapshot.x,
          y: outputSnapshot.y,
          width: outputSnapshot.width,
          height: outputSnapshot.height,
        )
      elif window.maximized:
        geometry = outputSnapshot.bounds()
      var presentationBits = 0'u16
      if window.fullscreen:
        presentationBits = presentationBits or (1'u16 shl 0)
      if window.maximized:
        presentationBits = presentationBits or (1'u16 shl 1)
      let requestedWidth =
        if window.fullscreen or window.maximized:
          constrainedExtent(
            geometry.width, surface.minWidth, surface.maxWidth, surface.exactWidth
          )
        else:
          placement.requestedWidth
      let requestedHeight =
        if window.fullscreen or window.maximized:
          constrainedExtent(
            geometry.height, surface.minHeight, surface.maxHeight, surface.exactHeight
          )
        else:
          placement.requestedHeight
      projection.placements.add(
        ProjectionPlacement(
          surfaceIndex: surface.surfaceIndex,
          surfaceGeneration: surface.surfaceGeneration,
          stateGeneration: surface.stateGeneration,
          x: geometry.x,
          y: geometry.y,
          width: geometry.width,
          height: geometry.height,
          requestedWidth: requestedWidth,
          requestedHeight: requestedHeight,
          transform: 1,
          presentationBits: presentationBits,
        )
      )
    let viewId = adapter.model.outputs[logical.output].activeView
    for windowId in adapter.model.windowOrder:
      let window = adapter.model.windows[windowId]
      if window.homeOutput != logical.output or not window.minimized or
          not adapter.model.windowTagIds(windowId).intersects(
            adapter.model.viewTagIds(viewId)
          ):
        continue
      let surface = adapter.surfaceFacts[windowId]
      let geometry = outputSnapshot.bounds()
      projection.placements.add(
        ProjectionPlacement(
          surfaceIndex: surface.surfaceIndex,
          surfaceGeneration: surface.surfaceGeneration,
          stateGeneration: surface.stateGeneration,
          x: geometry.x,
          y: geometry.y,
          width: geometry.width,
          height: geometry.height,
          requestedWidth: constrainedExtent(
            geometry.width, surface.minWidth, surface.maxWidth, surface.exactWidth
          ),
          requestedHeight: constrainedExtent(
            geometry.height, surface.minHeight, surface.maxHeight, surface.exactHeight
          ),
          transform: 1,
          presentationBits: 1'u16 shl 2,
        )
      )
      inc projection.output.placementCount
    result.outputs.add(projection)

    let outputState = adapter.model.outputs[logical.output]
    # Migrated views retained for a disconnected output affinity remain model
    # state, not extra public profile slots on the fallback output.
    for index in 0 ..< min(outputState.views.len, 9):
      let viewId = outputState.views[index]
      var stateBits = 0'u16
      if viewId == outputState.activeView:
        stateBits = stateBits or (1'u16 shl 0)
      for windowId in adapter.model.windowOrder:
        let window = adapter.model.windows[windowId]
        if window.homeOutput == logical.output and
            adapter.model.windowTagIds(windowId).intersects(
              adapter.model.viewTagIds(viewId)
            ):
          stateBits = stateBits or (1'u16 shl 2)
          break
      for otherOutputId in adapter.model.outputOrder:
        if otherOutputId == logical.output:
          continue
        let other = adapter.model.outputs[otherOutputId]
        if adapter.model.viewTagIds(other.activeView).intersects(
          adapter.model.viewTagIds(viewId)
        ):
          stateBits = stateBits or (1'u16 shl 3)
          break
      let labelText = $(index + 1)
      var indicator = ProjectionIndicator(
        output: rawOutput,
        slot: uint32(index),
        indicator: uint64(uint32(viewId)),
        action: (index + 1).activateViewAction().raw(),
        stateBits: stateBits,
        labelLen: uint16(labelText.len),
      )
      for labelIndex, character in labelText:
        indicator.label[labelIndex] = byte(character)
      result.indicators.add(indicator)

    let layoutText =
      case adapter.model.views[outputState.activeView].layout
      of LayoutMode.scroller: "Scroller"
      of LayoutMode.tile: "Tile"
      of LayoutMode.grid: "Grid"
      of LayoutMode.monocle: "Monocle"
      of LayoutMode.verticalScroller: "Vertical Scroller"
    var status = ProjectionOutputStatus(
      output: rawOutput,
      focusBits: (if outputState.focusedWindow != nullWindowId: 1'u16 else: 0'u16),
      layoutLen: uint16(layoutText.len),
    )
    for index, character in layoutText:
      status.layout[index] = byte(character)
    result.outputStatuses.add(status)

  result.activeOutput = adapter.logicalToOutput[adapter.model.activeOutput].output
