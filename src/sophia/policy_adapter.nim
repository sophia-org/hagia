import std/[options, sets, tables]

import ../policy/[projection, state, types]
import ./[session_types, wm_v1]

type
  PolicyAdapterError* = object of CatchableError

  PolicyAdapter* = object
    model: PolicyModel
    surfaceToWindow: Table[uint64, WindowId]
    windowToSurface: Table[WindowId, uint64]
    outputToLogical: Table[uint64, OutputId]
    logicalToOutput: Table[OutputId, uint64]
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
  Rect(x: output.x, y: output.y, width: output.width, height: output.height)

proc initPolicyAdapter*(): PolicyAdapter =
  PolicyAdapter(model: initPolicyModel())

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

## Reconcile only complete Sophia snapshots. The policy model never observes a
## partial transfer or stores a Sophia identity in its own entity tables.
proc reconcile*(adapter: var PolicyAdapter, snapshot: PolicySnapshot) =
  if snapshot.generation == 0 or snapshot.outputs.len == 0:
    fail("Sophia snapshot is empty")

  var liveOutputs = initHashSet[uint64]()
  for output in snapshot.outputs:
    liveOutputs.incl(output.output)
    if output.output in adapter.outputToLogical:
      adapter.model.updateOutput(
        adapter.outputToLogical[output.output], output.bounds()
      )
    else:
      let logical = adapter.model.addOutput(output.bounds())
      adapter.outputToLogical[output.output] = logical
      adapter.logicalToOutput[logical] = output.output

  let fallback = adapter.outputToLogical[snapshot.outputs[0].output]
  var removedOutputs: seq[uint64]
  for output in adapter.outputToLogical.keys:
    if output notin liveOutputs:
      removedOutputs.add(output)
  for output in removedOutputs:
    let logical = adapter.outputToLogical[output]
    adapter.model.removeOutput(logical, fallback)
    adapter.outputToLogical.del(output)
    adapter.logicalToOutput.del(logical)

  var liveSurfaces = initHashSet[uint64]()
  for surface in snapshot.surfaces:
    let key = surface.surfaceKey()
    liveSurfaces.incl(key)
    if key in adapter.surfaceToWindow:
      let window = adapter.surfaceToWindow[key]
      adapter.model.updateWindowFacts(
        window, surface.capabilityBits.capabilities(), surface.constraints()
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

  for logical in adapter.model.projectColumns(affected):
    let rawOutput = adapter.logicalToOutput[logical.output]
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
