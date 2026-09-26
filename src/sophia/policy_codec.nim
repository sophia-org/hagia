import std/[options, sets]

import ../types/[actions, session, wm_v1, wm_presentation]
import ./wm_v1 as wm_codec
import ../policy/actions
import ./policy_transport
import ./policy_semantics
import ./policy_snapshot as snapshot_checks

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
  snapshot_checks.validateSnapshot(snapshot)

## Assemble into local scratch state; callers see a snapshot only after every
## identity, ordinal, record total, and terminal frame agrees.
proc decodeProjectionRequest*(
    frame: Frame, expectedConnectionEpoch: uint64, selectedCapabilities: uint64 = 0
): ProjectionRequest =
  ## `selectedCapabilities` is what negotiation actually chose. It defaults to
  ## none so a caller that never negotiated cannot be handed a cause it did not
  ## agree to receive.
  if frame.kind == MessageKind.presentationActionRequest:
    let required = capabilitySurfaceInstances or capabilityPresentationActions
    if (selectedCapabilities and required) != required or frame.payload.len < 100:
      fail("presentation action was not negotiated or is truncated")
    result.connectionEpoch = frame.payload.u64At(0)
    result.requestId = frame.payload.u64At(8)
    result.sceneGeneration = frame.payload.u64At(16)
    result.policyGeneration = frame.payload.u64At(24)
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.presentationAction,
      activationSerial: frame.payload.u64At(32),
      action: frame.payload.u64At(40),
      presentation: PresentationIdentity(
        output: frame.payload.u64At(48),
        outputGeneration: frame.payload.u64At(56),
        publicationGeneration: frame.payload.u64At(64),
        presentationEpoch: frame.payload.u64At(72),
        targetId: frame.payload.u64At(80),
        targetGeneration: frame.payload.u64At(88),
      ),
    )
    let count = int(frame.payload.u16At(96))
    if result.connectionEpoch != expectedConnectionEpoch or result.connectionEpoch == 0 or
        result.requestId == 0 or result.sceneGeneration == 0 or
        result.policyGeneration == 0 or count notin 1 .. maxOutputs or
        frame.payload.len != 100 + count * 8 or frame.payload.u16At(98) != 0:
      fail("presentation action request identity is invalid")
    for index in 0 ..< count:
      let output = frame.payload.u64At(100 + index * 8)
      if output == 0 or output in result.affectedOutputs:
        fail("presentation action coverage is invalid")
      result.affectedOutputs.add(output)
    let identity = result.cause.presentation
    # Coverage already refused a zero output, so the shared identity predicate
    # is exactly this decoder's former condition.
    if result.cause.activationSerial == 0 or result.cause.action == 0 or
        identity.output notin result.affectedOutputs or
        not validPresentationIdentity(identity):
      fail("presentation action target is invalid")
    return
  if frame.kind == MessageKind.outputActionRequest:
    if (selectedCapabilities and capabilityOutputActions) == 0:
      fail("targeted output action was not negotiated")
    result.connectionEpoch = frame.payload.u64At(0)
    result.requestId = frame.payload.u64At(8)
    result.sceneGeneration = frame.payload.u64At(16)
    result.policyGeneration = frame.payload.u64At(24)
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.outputAction,
      activationSerial: frame.payload.u64At(32),
      action: frame.payload.u64At(40),
      output: frame.payload.u64At(48),
      outputGeneration: frame.payload.u64At(56),
    )
    let count = int(frame.payload.u16At(64))
    if result.connectionEpoch != expectedConnectionEpoch or result.connectionEpoch == 0 or
        result.requestId == 0 or result.sceneGeneration == 0 or
        result.policyGeneration == 0 or result.cause.activationSerial == 0 or
        result.cause.action == 0 or result.cause.output == 0 or
        result.cause.outputGeneration == 0 or count < 1 or count > maxOutputs or
        frame.payload.len != 68 + count * 8 or frame.payload.u16At(66) != 0:
      fail("targeted output action identity is invalid")
    for index in 0 ..< count:
      let output = frame.payload.u64At(68 + index * 8)
      if output == 0 or output in result.affectedOutputs:
        fail("targeted output action coverage is invalid")
      result.affectedOutputs.add(output)
    if result.cause.output notin result.affectedOutputs:
      fail("targeted output action is outside projection coverage")
    return
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
  of ProjectionCauseKind.outputAction, ProjectionCauseKind.presentationAction:
    fail("targeted output action requires its own message")
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
  of ProjectionCauseKind.pointerFocus:
    if (selectedCapabilities and capabilityPointerFocus) == 0:
      fail("policy pointer-focus cause arrived without its negotiated capability")
    # The output rides the action slot. The target is absent only when both
    # halves are zero: a surface identity is valid at index zero as long as its
    # generation is not, so generation is what says a target is present, and an
    # index without one is the malformed case. The all-ones index is not a
    # surface identity either, so it is refused with the rest.
    if result.cause.interactionPhase != InteractionPhase.none or
        result.cause.interactionKind != InteractionKind.none or
        result.cause.interactionAxis != InteractionAxis.none or
        result.cause.activationSerial != 0 or result.cause.action == 0 or
        not validOptionalSurface(
          result.cause.targetIndex, result.cause.targetGeneration
        ) or result.cause.x != 0 or result.cause.y != 0 or result.cause.width != 0 or
        result.cause.height != 0:
      fail("policy pointer-focus cause is invalid")
  of ProjectionCauseKind.interaction:
    if result.cause.interactionPhase == InteractionPhase.none or
        result.cause.interactionKind == InteractionKind.none or
        result.cause.activationSerial != 0 or result.cause.action != 0 or
        result.cause.targetIndex == 0 or result.cause.targetGeneration == 0:
      fail("policy interaction cause is invalid")
    # The target rule above (index zero refused) stays this decoder's own; the
    # payload rule is shared.
    if not validInteractionPayload(
      result.cause.interactionPhase, result.cause.interactionKind,
      result.cause.interactionAxis, result.cause.x, result.cause.y, result.cause.width,
      result.cause.height,
    ):
      case result.cause.interactionKind
      of InteractionKind.move, InteractionKind.resize, InteractionKind.drag:
        fail("policy geometry interaction payload is invalid")
      of InteractionKind.scroll:
        fail("policy scroll interaction payload is invalid")
      else:
        fail("policy interaction kind is invalid")
  for index in 0 ..< outputCount:
    result.affectedOutputs.add(frame.payload.u64At(84 + index * 8))
  # The output a pointer observation names has to be one this cycle may change,
  # or the projection would answer for an output the request never covered.
  if result.cause.kind == ProjectionCauseKind.pointerFocus and
      result.cause.action notin result.affectedOutputs:
    fail("policy pointer-focus cause names an unaffected output")

proc validateLaunchOrigins*(records: openArray[LaunchOriginRecord], epoch: uint64) =
  ## Index zero is a surface; the all-ones index is not one. Everything else has
  ## to be present, the epoch has to be this connection's so a record held
  ## across a restart cannot resolve against a fresh token space, and no surface
  ## may appear twice -- two contexts for one window have no resolution.
  if records.len > maxLaunchOriginRecords:
    fail("policy launch origin records exceed their bound")
  var seen = initHashSet[uint64]()
  for record in records:
    if record.surfaceIndex == high(uint32) or record.surfaceGeneration == 0 or
        record.epoch == 0 or record.token == 0 or record.epoch != epoch:
      fail("policy launch origin record is invalid")
    let key = uint64(record.surfaceGeneration) shl 32 or uint64(record.surfaceIndex)
    if key in seen:
      fail("policy launch origin names a surface twice")
    seen.incl(key)

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
  let outcome = projectionOutcomeFromCode(frame.payload.u16At(24))
  if outcome.isNone:
    fail("Sophia returned an unknown policy outcome")
  ProjectionOutcome(
    transaction: frame.transaction,
    connectionEpoch: frame.payload.u64At(0),
    requestId: frame.payload.u64At(8),
    sceneGeneration: frame.payload.u64At(16),
    kind: outcome.get,
  )
