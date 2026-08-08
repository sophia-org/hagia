import std/[options, sets, tables]

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

proc applyCause*(adapter: var PolicyAdapter, request: ProjectionRequest) =
  if request.affectedOutputs.len == 0:
    fail("policy cause has no affected output")
  let rawOutput = request.affectedOutputs[0]
  if rawOutput notin adapter.outputToLogical:
    fail("policy cause names an unknown output")
  let output = adapter.outputToLogical[rawOutput]
  case request.cause.kind
  of ProjectionCauseKind.sceneChanged:
    discard
  of ProjectionCauseKind.action:
    if request.cause.activationSerial == 0 or request.cause.action < 1 or
        request.cause.action > uint64(ord(high(PolicyAction))):
      fail("policy action cause is invalid")
    adapter.model.applyAction(output, PolicyAction(request.cause.action))
  of ProjectionCauseKind.focus:
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy focus cause names an unknown surface")
    adapter.model.setFocus(output, adapter.surfaceToWindow[key])
  of ProjectionCauseKind.interaction:
    # Hagia does not negotiate this capability until floating geometry is part
    # of its committed private model.
    fail("policy interaction cause is not negotiated")
  adapter.model.validate()

## Reconcile only complete Sophia snapshots. The policy model never observes a
## partial transfer or stores a Sophia identity in its own entity tables.
proc reconcile*(adapter: var PolicyAdapter, snapshot: PolicySnapshot) =
  if snapshot.generation == 0 or snapshot.outputs.len == 0:
    fail("Sophia snapshot is empty")

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
  var affected: seq[OutputId]
  for output in request.affectedOutputs:
    if output notin adapter.outputToLogical:
      fail("projection request names an unknown output")
    affected.add(adapter.outputToLogical[output])

  for logical in adapter.model.projectScroller(affected):
    let rawOutput = adapter.logicalToOutput[logical.output].output
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
      projection.placements.add(
        ProjectionPlacement(
          surfaceIndex: surface.surfaceIndex,
          surfaceGeneration: surface.surfaceGeneration,
          stateGeneration: surface.stateGeneration,
          x: placement.geometry.x,
          y: placement.geometry.y,
          width: placement.geometry.width,
          height: placement.geometry.height,
          requestedWidth: placement.requestedWidth,
          requestedHeight: placement.requestedHeight,
          transform: 1,
        )
      )
    result.outputs.add(projection)
