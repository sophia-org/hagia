import std/sets

import ../types/[actions, session, wm_v1]
import ./wm_v1 as wm_codec
import ../policy/actions
import ./policy_transport

## Decoding and validation for policy frames. These read bytes and refuse
## malformed input; they hold no connection state, so the conformance corpus
## can exercise them without a socket.

proc recordBytes*(payload: openArray[byte], index, size: int): seq[byte] =
  let first = 16 + index * size
  let past = first + size
  if first < 16 or past > payload.len:
    fail("policy record chunk is truncated")
  @payload[first ..< past]

proc validateSnapshot*(snapshot: PolicySnapshot) =
  if snapshot.generation == 0 or snapshot.activeOutput == 0 or snapshot.outputs.len == 0 or
      snapshot.outputs.len > maxOutputs or snapshot.surfaces.len > maxSurfaces:
    fail("policy snapshot count is invalid")
  var outputs = initHashSet[uint64]()
  for output in snapshot.outputs:
    if output.output == 0 or output.generation == 0 or output.width <= 0 or
        output.height <= 0 or output.workWidth <= 0 or output.workHeight <= 0 or
        output.workX < output.x or output.workY < output.y or
        int64(output.workX) + int64(output.workWidth) >
        int64(output.x) + int64(output.width) or
        int64(output.workY) + int64(output.workHeight) >
        int64(output.y) + int64(output.height) or output.output in outputs:
      fail("policy snapshot output is invalid")
    outputs.incl(output.output)
  if snapshot.activeOutput notin outputs:
    fail("policy snapshot active output is invalid")
  var surfaces = initHashSet[(uint32, uint32)]()
  for surface in snapshot.surfaces:
    let identity = (surface.surfaceIndex, surface.surfaceGeneration)
    if surface.surfaceGeneration == 0 or surface.stateGeneration == 0 or
        surface.width <= 0 or surface.height <= 0 or identity in surfaces or
        (surface.currentOutput != 0 and surface.currentOutput notin outputs):
      fail("policy snapshot surface is invalid")
    if (surface.minWidth == 0) != (surface.minHeight == 0) or
        (surface.maxWidth == 0) != (surface.maxHeight == 0) or surface.minWidth < 0 or
        surface.minHeight < 0 or surface.maxWidth < 0 or surface.maxHeight < 0 or (
      surface.minWidth > 0 and surface.maxWidth > 0 and
      (surface.minWidth > surface.maxWidth or surface.minHeight > surface.maxHeight)
    ):
      fail("policy surface constraints are invalid")
    if surface.kind < 1 or surface.kind > 5 or
        (surface.requestStateBits and not 7'u16) != 0 or
        (surface.currentStateBits and not 7'u16) != 0 or
        (surface.exactWidth == 0) != (surface.exactHeight == 0) or surface.exactWidth < 0 or
        surface.exactHeight < 0:
      fail("policy surface reduced state is invalid")
    if (surface.currentStateBits and 1) != 0 and (surface.currentStateBits and 2) != 0 or
        (surface.currentStateBits and 4) != 0 and (surface.currentStateBits and 3) != 0:
      fail("policy surface presentation state conflicts")
    surfaces.incl(identity)
  for surface in snapshot.surfaces:
    if surface.transientGeneration != 0 and
        (surface.transientIndex, surface.transientGeneration) notin surfaces:
      fail("policy transient owner is invalid")
  for output in snapshot.outputs:
    if (output.focusIndex == 0) != (output.focusGeneration == 0):
      fail("policy output focus identity is partial")
    if output.focusGeneration != 0:
      var validFocus = false
      for surface in snapshot.surfaces:
        if surface.surfaceIndex == output.focusIndex and
            surface.surfaceGeneration == output.focusGeneration and
            surface.currentOutput == output.output and
            (surface.capabilityBits and surfaceFocusable) != 0 and
            (surface.currentStateBits and 4) == 0:
          validFocus = true
          break
      if not validFocus:
        fail("policy output focus is invalid")
  var classifiedSurfaces = initHashSet[(uint32, uint32)]()
  for classification in snapshot.classifications:
    let identity = (classification.surfaceIndex, classification.surfaceGeneration)
    if classification.classification == 0 or identity notin surfaces or
        identity in classifiedSurfaces:
      fail("policy surface classification is invalid")
    classifiedSurfaces.incl(identity)
  var actions = initHashSet[uint64]()
  var operationSlots = initHashSet[uint16]()
  for operation in snapshot.sessionOperations:
    if operation.operation == 0 or operation.slot == 0 or
        operation.slot in operationSlots:
      fail("policy session operation is invalid")
    operationSlots.incl(operation.slot)
  var actionNames = initHashSet[string]()
  for action in snapshot.actions:
    if action.action == 0 or action.action in actions or action.name in actionNames or
        action.sessionOperationSlot != 0 and
        action.sessionOperationSlot notin operationSlots:
      fail("policy action is invalid")
    actions.incl(action.action)
    actionNames.incl(action.name)

## Assemble into local scratch state; callers see a snapshot only after every
## identity, ordinal, record total, and terminal frame agrees.
proc decodeProjectionRequest*(
    frame: Frame, expectedConnectionEpoch: uint64
): ProjectionRequest =
  if frame.kind != MessageKind.projectionRequest:
    fail("policy projection request has the wrong message kind")
  result.connectionEpoch = frame.payload.u64At(0)
  result.requestId = frame.payload.u64At(8)
  result.sceneGeneration = frame.payload.u64At(16)
  result.policyGeneration = frame.payload.u64At(24)
  let rawCause = frame.payload.u16At(32)
  if rawCause > uint16(ord(high(ProjectionCauseKind))):
    fail("policy projection cause is invalid")
  result.cause.kind = ProjectionCauseKind(rawCause)
  let rawPhase = frame.payload.u16At(34)
  if rawPhase > uint16(ord(high(InteractionPhase))):
    fail("policy interaction phase is invalid")
  result.cause.interactionPhase = InteractionPhase(rawPhase)
  let rawInteraction = frame.payload.u16At(36)
  if rawInteraction > uint16(ord(high(InteractionKind))):
    fail("policy interaction kind is invalid")
  result.cause.interactionKind = InteractionKind(rawInteraction)
  let rawAxis = frame.payload.u16At(38)
  if rawAxis > uint16(ord(high(InteractionAxis))):
    fail("policy interaction axis is invalid")
  result.cause.interactionAxis = InteractionAxis(rawAxis)
  result.cause.activationSerial = frame.payload.u64At(40)
  result.cause.action = frame.payload.u64At(48)
  result.cause.targetIndex = frame.payload.u32At(56)
  result.cause.targetGeneration = frame.payload.u32At(60)
  result.cause.x = frame.payload.i32At(64)
  result.cause.y = frame.payload.i32At(68)
  result.cause.width = frame.payload.i32At(72)
  result.cause.height = frame.payload.i32At(76)
  let outputCount = int(frame.payload.u16At(80))
  if result.connectionEpoch != expectedConnectionEpoch or result.requestId == 0 or
      result.sceneGeneration == 0 or result.policyGeneration == 0 or outputCount == 0 or
      outputCount > maxOutputs:
    fail("policy projection request is invalid")
  case result.cause.kind
  of ProjectionCauseKind.sceneChanged:
    if result.cause.interactionPhase != InteractionPhase.none or
        result.cause.interactionKind != InteractionKind.none or
        result.cause.interactionAxis != InteractionAxis.none or
        result.cause.activationSerial != 0 or result.cause.action != 0 or
        result.cause.targetIndex != 0 or result.cause.targetGeneration != 0 or
        result.cause.x != 0 or result.cause.y != 0 or result.cause.width != 0 or
        result.cause.height != 0:
      fail("policy scene-change cause is ambiguous")
  of ProjectionCauseKind.action:
    if result.cause.interactionPhase != InteractionPhase.none or
        result.cause.interactionKind != InteractionKind.none or
        result.cause.interactionAxis != InteractionAxis.none or
        result.cause.activationSerial == 0 or result.cause.action == 0 or
        result.cause.targetIndex != 0 or result.cause.targetGeneration != 0 or
        result.cause.x != 0 or result.cause.y != 0 or result.cause.width != 0 or
        result.cause.height != 0:
      fail("policy action cause is invalid")
  of ProjectionCauseKind.focus:
    if result.cause.interactionPhase != InteractionPhase.none or
        result.cause.interactionKind != InteractionKind.none or
        result.cause.interactionAxis != InteractionAxis.none or
        result.cause.activationSerial != 0 or result.cause.action != 0 or
        result.cause.targetIndex == 0 or result.cause.targetGeneration == 0 or
        result.cause.x != 0 or result.cause.y != 0 or result.cause.width != 0 or
        result.cause.height != 0:
      fail("policy focus cause is invalid")
  of ProjectionCauseKind.interaction:
    if result.cause.interactionPhase == InteractionPhase.none or
        result.cause.interactionKind == InteractionKind.none or
        result.cause.activationSerial != 0 or result.cause.action != 0 or
        result.cause.targetIndex == 0 or result.cause.targetGeneration == 0:
      fail("policy interaction cause is invalid")
    case result.cause.interactionKind
    of InteractionKind.move, InteractionKind.resize, InteractionKind.drag:
      if result.cause.interactionAxis != InteractionAxis.none or result.cause.width <= 0 or
          result.cause.height <= 0:
        fail("policy geometry interaction payload is invalid")
    of InteractionKind.scroll:
      if result.cause.interactionAxis == InteractionAxis.none or result.cause.width != 0 or
          result.cause.height != 0 or (
        result.cause.interactionPhase != InteractionPhase.cancel and result.cause.x == 0 and
        result.cause.y == 0
      ):
        fail("policy scroll interaction payload is invalid")
    else:
      fail("policy interaction kind is invalid")
  for index in 0 ..< outputCount:
    result.affectedOutputs.add(frame.payload.u64At(84 + index * 8))

proc addAction*(payload: var seq[byte], action: PolicyAction) =
  let name = action.profileName()
  if name.len < 1 or name.len > maxActionNameBytes:
    fail("policy action name is invalid")
  payload.addU64(action.raw())
  payload.addU16(action.sessionOperationSlot())
  payload.addU16(uint16(name.len))
  for value in name:
    payload.add(byte(value))
  for _ in name.len ..< maxActionNameBytes:
    payload.add(0)

proc decodeProjectionOutcome*(frame: Frame): ProjectionOutcome =
  if frame.kind != MessageKind.projectionOutcome:
    fail("policy outcome frame has the wrong kind")
  let rawOutcome = frame.payload.u16At(24)
  if rawOutcome < uint16(ord(low(ProjectionOutcomeKind))) or
      rawOutcome > uint16(ord(high(ProjectionOutcomeKind))):
    fail("Sophia returned an unknown policy outcome")
  ProjectionOutcome(
    transaction: frame.transaction,
    connectionEpoch: frame.payload.u64At(0),
    requestId: frame.payload.u64At(8),
    sceneGeneration: frame.payload.u64At(16),
    kind: ProjectionOutcomeKind(rawOutcome),
  )
