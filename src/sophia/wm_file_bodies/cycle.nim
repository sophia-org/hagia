import std/options
import ../../types/[session, wm_file_bodies, wm_files, wm_presentation, wm_v1]
import ../[policy_semantics, wm_file_payload, wm_files]

## Cycle bodies: an immutable snapshot's transaction, the request's own
## transaction, and one complete projection request with exactly one cause.
## The file numbers causes differently from the legacy scalar frame
## (PointerFocus 3, Interaction 4) and has no `none` interaction phase, so every
## code is converted explicitly here. The decoded request keeps the reducer's
## flat `ProjectionCause` conventions: a PointerFocus output rides `action`.

const h = wmFileHeaderBytes

proc fileCauseKind*(code: uint16): Option[WmFileCauseKind] =
  case code
  of 0:
    some(WmFileCauseKind.sceneChanged)
  of 1:
    some(WmFileCauseKind.action)
  of 2:
    some(WmFileCauseKind.focus)
  of 3:
    some(WmFileCauseKind.pointerFocus)
  of 4:
    some(WmFileCauseKind.interaction)
  of 5:
    some(WmFileCauseKind.outputAction)
  of 6:
    some(WmFileCauseKind.presentationAction)
  else:
    none(WmFileCauseKind)

proc projectionCauseKind*(kind: WmFileCauseKind): ProjectionCauseKind =
  ## Explicit, because the file and legacy numberings swap PointerFocus and
  ## Interaction.
  case kind
  of WmFileCauseKind.sceneChanged: ProjectionCauseKind.sceneChanged
  of WmFileCauseKind.action: ProjectionCauseKind.action
  of WmFileCauseKind.focus: ProjectionCauseKind.focus
  of WmFileCauseKind.pointerFocus: ProjectionCauseKind.pointerFocus
  of WmFileCauseKind.interaction: ProjectionCauseKind.interaction
  of WmFileCauseKind.outputAction: ProjectionCauseKind.outputAction
  of WmFileCauseKind.presentationAction: ProjectionCauseKind.presentationAction

proc fileCauseKind*(kind: ProjectionCauseKind): WmFileCauseKind =
  case kind
  of ProjectionCauseKind.sceneChanged: WmFileCauseKind.sceneChanged
  of ProjectionCauseKind.action: WmFileCauseKind.action
  of ProjectionCauseKind.focus: WmFileCauseKind.focus
  of ProjectionCauseKind.pointerFocus: WmFileCauseKind.pointerFocus
  of ProjectionCauseKind.interaction: WmFileCauseKind.interaction
  of ProjectionCauseKind.outputAction: WmFileCauseKind.outputAction
  of ProjectionCauseKind.presentationAction: WmFileCauseKind.presentationAction

proc interactionPhaseFromFileCode*(code: uint16): Option[InteractionPhase] =
  ## The file has no `none` phase; its End is Hagia's `finish`.
  case code
  of 1:
    some(InteractionPhase.begin)
  of 2:
    some(InteractionPhase.update)
  of 3:
    some(InteractionPhase.finish)
  of 4:
    some(InteractionPhase.cancel)
  else:
    none(InteractionPhase)

proc interactionKindFromFileCode*(code: uint16): Option[InteractionKind] =
  case code
  of 1:
    some(InteractionKind.move)
  of 2:
    some(InteractionKind.resize)
  of 3:
    some(InteractionKind.drag)
  of 4:
    some(InteractionKind.scroll)
  else:
    none(InteractionKind)

proc interactionAxisFromFileCode*(code: uint16): Option[InteractionAxis] =
  case code
  of 0:
    some(InteractionAxis.none)
  of 1:
    some(InteractionAxis.horizontal)
  of 2:
    some(InteractionAxis.vertical)
  else:
    none(InteractionAxis)

proc fileCode*(phase: InteractionPhase): uint16 =
  ## `none` has no file code; callers validate the phase before encoding.
  case phase
  of InteractionPhase.none: 0
  of InteractionPhase.begin: 1
  of InteractionPhase.update: 2
  of InteractionPhase.finish: 3
  of InteractionPhase.cancel: 4

proc fileCode*(kind: InteractionKind): uint16 =
  case kind
  of InteractionKind.none: 0
  of InteractionKind.move: 1
  of InteractionKind.resize: 2
  of InteractionKind.drag: 3
  of InteractionKind.scroll: 4

proc fileCode*(axis: InteractionAxis): uint16 =
  case axis
  of InteractionAxis.none: 0
  of InteractionAxis.horizontal: 1
  of InteractionAxis.vertical: 2

proc causeBytes*(kind: WmFileCauseKind): int =
  case kind
  of WmFileCauseKind.sceneChanged: 0
  of WmFileCauseKind.action: 16
  of WmFileCauseKind.focus: 8
  of WmFileCauseKind.pointerFocus: 16
  of WmFileCauseKind.interaction: 32
  of WmFileCauseKind.outputAction: 32
  of WmFileCauseKind.presentationAction: 64

proc causeCapabilities*(kind: WmFileCauseKind): uint64 =
  ## What a connection must have negotiated to receive each cause.
  case kind
  of WmFileCauseKind.sceneChanged, WmFileCauseKind.focus:
    0'u64
  of WmFileCauseKind.action:
    capabilityActions
  of WmFileCauseKind.outputAction:
    capabilityActions or capabilityOutputActions
  of WmFileCauseKind.presentationAction:
    capabilityActions or capabilitySurfaceInstances or capabilityPresentationActions
  of WmFileCauseKind.pointerFocus:
    capabilityPointerFocus
  of WmFileCauseKind.interaction:
    capabilityPointerInteractions

proc validFileCause(cause: ProjectionCause, affected: openArray[uint64]): bool =
  ## The strict file rules on the reducer's flat record. Every field the file
  ## kind does not carry must be zero, so encoding never drops a value.
  let noInteraction =
    cause.interactionPhase == InteractionPhase.none and
    cause.interactionKind == InteractionKind.none and
    cause.interactionAxis == InteractionAxis.none
  let noGeometry =
    cause.x == 0 and cause.y == 0 and cause.width == 0 and cause.height == 0
  let noTarget = cause.targetIndex == 0 and cause.targetGeneration == 0
  let noOutput = cause.output == 0 and cause.outputGeneration == 0
  let noPresentation = cause.presentation == PresentationIdentity()
  let noAction = cause.activationSerial == 0 and cause.action == 0
  case cause.kind
  of ProjectionCauseKind.sceneChanged:
    noInteraction and noGeometry and noTarget and noOutput and noPresentation and
      noAction
  of ProjectionCauseKind.action:
    cause.activationSerial != 0 and cause.action != 0 and noInteraction and noGeometry and
      noTarget and noOutput and noPresentation
  of ProjectionCauseKind.focus:
    validSurface(cause.targetIndex, cause.targetGeneration) and noInteraction and
      noGeometry and noOutput and noPresentation and noAction
  of ProjectionCauseKind.pointerFocus:
    cause.action != 0 and cause.action in affected and cause.activationSerial == 0 and
      validOptionalSurface(cause.targetIndex, cause.targetGeneration) and noInteraction and
      noGeometry and noOutput and noPresentation
  of ProjectionCauseKind.interaction:
    cause.interactionPhase != InteractionPhase.none and
      validSurface(cause.targetIndex, cause.targetGeneration) and
      validInteractionPayload(
        cause.interactionPhase, cause.interactionKind, cause.interactionAxis, cause.x,
        cause.y, cause.width, cause.height,
      ) and noAction and noOutput and noPresentation
  of ProjectionCauseKind.outputAction:
    cause.activationSerial != 0 and cause.action != 0 and cause.output != 0 and
      cause.outputGeneration != 0 and cause.output in affected and noInteraction and
      noGeometry and noTarget and noPresentation
  of ProjectionCauseKind.presentationAction:
    cause.activationSerial != 0 and cause.action != 0 and
      validPresentationIdentity(cause.presentation) and
      cause.presentation.output in affected and noInteraction and noGeometry and noTarget and
      noOutput

proc requireCycle(cycle: WmFileCycle) =
  let request = cycle.request
  requireNonzero(
    [
      cycle.snapshotTransaction, cycle.requestTransaction, request.requestId,
      request.sceneGeneration, request.policyGeneration,
    ]
  )
  if not validAffectedOutputs(request.affectedOutputs):
    failWmFile(WmFileErrorKind.value, "cycle affected outputs are invalid")
  if not validFileCause(request.cause, request.affectedOutputs):
    failWmFile(WmFileErrorKind.value, "cycle cause is invalid")

proc addCause(body: var seq[byte], cause: ProjectionCause) =
  case cause.kind
  of ProjectionCauseKind.sceneChanged:
    discard
  of ProjectionCauseKind.action:
    body.addU64(cause.activationSerial)
    body.addU64(cause.action)
  of ProjectionCauseKind.focus:
    body.addSurface(cause.targetIndex, cause.targetGeneration)
  of ProjectionCauseKind.pointerFocus:
    body.addU64(cause.action)
    body.addSurface(cause.targetIndex, cause.targetGeneration)
  of ProjectionCauseKind.interaction:
    body.addU16(cause.interactionPhase.fileCode)
    body.addU16(cause.interactionKind.fileCode)
    body.addU16(cause.interactionAxis.fileCode)
    body.addU16(0)
    body.addSurface(cause.targetIndex, cause.targetGeneration)
    for value in [cause.x, cause.y, cause.width, cause.height]:
      body.addI32(value)
  of ProjectionCauseKind.outputAction:
    for value in [
      cause.activationSerial, cause.action, cause.output, cause.outputGeneration
    ]:
      body.addU64(value)
  of ProjectionCauseKind.presentationAction:
    let identity = cause.presentation
    for value in [
      cause.activationSerial, cause.action, identity.publicationGeneration,
      identity.output, identity.outputGeneration, identity.presentationEpoch,
      identity.targetId, identity.targetGeneration,
    ]:
      body.addU64(value)

proc readCause(
    bytes: openArray[byte], at: int, kind: WmFileCauseKind
): ProjectionCause =
  ## `at` is the absolute offset of the cause, whose exact size the caller
  ## has already checked.
  result.kind = kind.projectionCauseKind
  case kind
  of WmFileCauseKind.sceneChanged:
    discard
  of WmFileCauseKind.action:
    result.activationSerial = bytes.readU64(at)
    result.action = bytes.readU64(at + 8)
  of WmFileCauseKind.focus:
    result.targetIndex = bytes.readU32(at)
    result.targetGeneration = bytes.readU32(at + 4)
  of WmFileCauseKind.pointerFocus:
    result.action = bytes.readU64(at)
    result.targetIndex = bytes.readU32(at + 8)
    result.targetGeneration = bytes.readU32(at + 12)
  of WmFileCauseKind.interaction:
    let phase = interactionPhaseFromFileCode(bytes.readU16(at))
    let interaction = interactionKindFromFileCode(bytes.readU16(at + 2))
    let axis = interactionAxisFromFileCode(bytes.readU16(at + 4))
    if phase.isNone or interaction.isNone or axis.isNone:
      failWmFile(WmFileErrorKind.value, "interaction code is unknown")
    if bytes.readU16(at + 6) != 0:
      failWmFile(WmFileErrorKind.reserved, "interaction reserved field is nonzero")
    result.interactionPhase = phase.get
    result.interactionKind = interaction.get
    result.interactionAxis = axis.get
    result.targetIndex = bytes.readU32(at + 8)
    result.targetGeneration = bytes.readU32(at + 12)
    result.x = bytes.readI32(at + 16)
    result.y = bytes.readI32(at + 20)
    result.width = bytes.readI32(at + 24)
    result.height = bytes.readI32(at + 28)
  of WmFileCauseKind.outputAction:
    result.activationSerial = bytes.readU64(at)
    result.action = bytes.readU64(at + 8)
    result.output = bytes.readU64(at + 16)
    result.outputGeneration = bytes.readU64(at + 24)
  of WmFileCauseKind.presentationAction:
    result.activationSerial = bytes.readU64(at)
    result.action = bytes.readU64(at + 8)
    result.presentation = PresentationIdentity(
      publicationGeneration: bytes.readU64(at + 16),
      output: bytes.readU64(at + 24),
      outputGeneration: bytes.readU64(at + 32),
      presentationEpoch: bytes.readU64(at + 40),
      targetId: bytes.readU64(at + 48),
      targetGeneration: bytes.readU64(at + 56),
    )

proc encodeCycle*(
    header: WmFileHeader, cycle: WmFileCycle, selected: uint64
): seq[byte] =
  let request = cycle.request
  header.requireEpoch(request.connectionEpoch)
  cycle.requireCycle()
  let kind = request.cause.kind.fileCauseKind
  requireCapabilities(selected, kind.causeCapabilities)
  var body = newSeqOfCap[byte](
    wmFileCyclePrefixBytes + request.affectedOutputs.len * 8 + kind.causeBytes
  )
  for value in [
    cycle.snapshotTransaction, cycle.requestTransaction, request.requestId,
    request.sceneGeneration, request.policyGeneration,
  ]:
    body.addU64(value)
  body.addU16(uint16(ord(kind)))
  body.addU16(uint16(request.affectedOutputs.len))
  body.addU32(0)
  body.addOutputs(request.affectedOutputs)
  body.addCause(request.cause)
  header.encodePayload(WmFileKind.cycle, body)

proc decodeCycle*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileCycle =
  let header =
    bytes.prefixedPayload(WmFileKind.cycle, expectedEpoch, wmFileCyclePrefixBytes)
  requireReserved(bytes.toOpenArray(h, bytes.high), 44, 4)
  let kind = fileCauseKind(bytes.readU16(h + 40))
  if kind.isNone:
    failWmFile(WmFileErrorKind.value, "cycle cause kind is unknown")
  let count = bytes.readU16(h + 42)
  if count < 1 or int(count) > maxOutputs:
    failWmFile(WmFileErrorKind.value, "cycle output count is out of range")
  let causeAt = wmFileCyclePrefixBytes + int(count) * 8
  if bytes.len - h - causeAt != kind.get.causeBytes:
    failWmFile(WmFileErrorKind.length, "cycle body does not end with its cause")
  result = WmFileCycle(
    snapshotTransaction: bytes.readU64(h),
    requestTransaction: bytes.readU64(h + 8),
    request: ProjectionRequest(
      connectionEpoch: header.connectionEpoch,
      requestId: bytes.readU64(h + 16),
      sceneGeneration: bytes.readU64(h + 24),
      policyGeneration: bytes.readU64(h + 32),
      affectedOutputs: readOutputs(
        bytes.toOpenArray(h, h + causeAt - 1), wmFileCyclePrefixBytes, count
      ),
      cause: bytes.readCause(h + causeAt, kind.get),
    ),
  )
  result.requireCycle()
  requireCapabilities(selected, kind.get.causeCapabilities)
