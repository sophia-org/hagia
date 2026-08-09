import std/[marshal, options, sets, strutils, tables]

import ../policy/[actions, projection, state, types]
import ./[session_types, wm_v1]

type
  PolicyAdapterError* = object of CatchableError

  OutputHandle = tuple[output, generation: uint64]

  PolicyAdapter* = object
    model: PolicyModel
    surfaceToWindow: Table[uint64, WindowId]
    windowToSurface: Table[WindowId, uint64]
    outputToLogical: Table[uint64, OutputId]
    activeOutputToLogical: Table[OutputHandle, OutputId]
    dormantOutputToLogical: Table[OutputHandle, OutputId]
    logicalToOutput: Table[OutputId, OutputHandle]
    surfaceFacts: Table[WindowId, SnapshotSurface]

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyAdapterError, message)

proc surfaceKey(index, generation: uint32): uint64 =
  uint64(index) or (uint64(generation) shl 32)

proc surfaceKey(surface: SnapshotSurface): uint64 =
  surfaceKey(surface.surfaceIndex, surface.surfaceGeneration)

proc capabilities(bits: uint16): WindowCapabilities =
  WindowCapabilities(
    movable: (bits and (1'u16 shl 0)) != 0,
    resizable: (bits and (1'u16 shl 1)) != 0,
    focusable: (bits and (1'u16 shl 2)) != 0,
    closable: (bits and (1'u16 shl 3)) != 0,
    fullscreenable: (bits and (1'u16 shl 4)) != 0,
  )

proc applyPresentation(model: var PolicyModel, window: WindowId, bits: uint16) =
  model.setWindowPresentation(
    window,
    (bits and (1'u16 shl 0)) != 0,
    (bits and (1'u16 shl 1)) != 0,
    (bits and (1'u16 shl 2)) != 0,
  )

proc constraints(surface: SnapshotSurface): SizeConstraints =
  SizeConstraints(
    minWidth: surface.minWidth,
    minHeight: surface.minHeight,
    maxWidth: surface.maxWidth,
    maxHeight: surface.maxHeight,
  )

proc bounds(output: SnapshotOutput): Rect =
  ## Layout uses Engine's bounded work rectangle; panels and other reserved
  ## shell regions never become private Hagia policy.
  if output.workWidth > 0 and output.workHeight > 0:
    Rect(
      x: output.workX,
      y: output.workY,
      width: output.workWidth,
      height: output.workHeight,
    )
  else:
    # Unit-level policy fixtures may construct semantic records directly. The
    # live wire validator requires a positive work rectangle before this layer.
    Rect(x: output.x, y: output.y, width: output.width, height: output.height)

proc handle(output: SnapshotOutput): OutputHandle =
  (output: output.output, generation: output.generation)

proc constrainedExtent(extent, minimum, maximum, exact: int32): int32 =
  if exact > 0:
    return exact
  result = extent
  if minimum > 0:
    result = max(result, minimum)
  if maximum > 0:
    result = min(result, maximum)

proc initPolicyAdapter*(): PolicyAdapter =
  PolicyAdapter(model: initPolicyModel())

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

proc checkpointPayload*(adapter: PolicyAdapter): string =
  "HAGIA-POLICY-CHECKPOINT-1\n" & $$adapter

proc restoreCheckpointPayload*(payload: string): PolicyAdapter =
  const prefix = "HAGIA-POLICY-CHECKPOINT-1\n"
  if not payload.startsWith(prefix):
    fail("policy checkpoint version is invalid")
  try:
    result = to[PolicyAdapter](payload[prefix.len .. ^1])
  except CatchableError:
    fail("policy checkpoint payload is malformed")
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
  case request.cause.kind
  of ProjectionCauseKind.sceneChanged:
    discard
  of ProjectionCauseKind.action:
    if request.cause.activationSerial == 0 or not request.cause.action.isPolicyAction():
      fail("policy action cause is invalid")
    adapter.model.applyAction(output, request.cause.action.policyAction())
  of ProjectionCauseKind.focus:
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy focus cause names an unknown surface")
    let window = adapter.surfaceToWindow[key]
    adapter.model.setActiveOutput(adapter.model.windows[window].homeOutput)
    adapter.model.setFocus(adapter.model.activeOutput, window)
  of ProjectionCauseKind.interaction:
    if request.cause.interactionPhase != InteractionPhase.finish:
      fail("only one reduced completed interaction is accepted")
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy interaction cause names an unknown surface")
    let window = adapter.surfaceToWindow[key]
    let interactionOutput = adapter.model.windows[window].homeOutput
    adapter.model.setActiveOutput(interactionOutput)
    let geometry = Rect(
      x: request.cause.x,
      y: request.cause.y,
      width: request.cause.width,
      height: request.cause.height,
    )
    let facts = adapter.model.window(window).get()
    case request.cause.interactionKind
    of InteractionKind.move:
      if not facts.capabilities.movable:
        fail("policy move interaction targets an immovable surface")
    of InteractionKind.resize:
      if not facts.capabilities.resizable:
        fail("policy resize interaction targets a fixed-size surface")
    else:
      fail("policy interaction kind is invalid")
    adapter.model.setFloatingGeometry(interactionOutput, window, geometry)
  adapter.model.validate()

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
      adapter.model.ensureViewCount(logical, 9)
    adapter.activeOutputToLogical[current] = logical
    adapter.outputToLogical[output.output] = logical
    adapter.logicalToOutput[logical] = current
  if snapshot.activeOutput notin adapter.outputToLogical:
    fail("Sophia snapshot active output is not live")
  adapter.model.setActiveOutput(adapter.outputToLogical[snapshot.activeOutput])

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
        if surface.currentOutput != 0:
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

  for logical in adapter.model.projectScroller(affected):
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
    let view = adapter.model.views[adapter.model.outputs[logical.output].activeView]
    for windowId in adapter.model.windowOrder:
      let window = adapter.model.windows[windowId]
      if window.homeOutput != logical.output or not window.minimized or
          not window.tags.intersects(view.selectedTags):
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
    for index, viewId in outputState.views:
      let view = adapter.model.views[viewId]
      var stateBits = 0'u16
      if viewId == outputState.activeView:
        stateBits = stateBits or (1'u16 shl 0)
      for windowId in adapter.model.windowOrder:
        let window = adapter.model.windows[windowId]
        if window.homeOutput == logical.output and
            window.tags.intersects(view.selectedTags):
          stateBits = stateBits or (1'u16 shl 2)
          break
      for otherOutputId in adapter.model.outputOrder:
        if otherOutputId == logical.output:
          continue
        let other = adapter.model.outputs[otherOutputId]
        if adapter.model.views[other.activeView].selectedTags.intersects(
          view.selectedTags
        ):
          stateBits = stateBits or (1'u16 shl 3)
          break
      let labelText = $(index + 1)
      var indicator = ProjectionIndicator(
        output: rawOutput,
        slot: uint32(index),
        indicator: uint64(uint32(viewId)),
        action: uint64(ord(PolicyAction.activateView1) + index),
        stateBits: stateBits,
        labelLen: uint16(labelText.len),
      )
      for labelIndex, character in labelText:
        indicator.label[labelIndex] = byte(character)
      result.indicators.add(indicator)

    const layoutText = "Scroller"
    var status = ProjectionOutputStatus(
      output: rawOutput,
      focusBits: (if outputState.focusedWindow != nullWindowId: 1'u16 else: 0'u16),
      layoutLen: uint16(layoutText.len),
    )
    for index, character in layoutText:
      status.layout[index] = byte(character)
    result.outputStatuses.add(status)

  result.activeOutput = adapter.logicalToOutput[adapter.model.activeOutput].output
