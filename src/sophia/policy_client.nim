import std/[net, options, os, sets, strutils]

import ../policy/actions
import ./[policy_adapter, policy_checkpoint, policy_session, session_types, wm_v1]

type
  PolicyClientError* = object of CatchableError

  PolicyClient = ref object
    socket: Socket
    connectionEpoch: uint64
    capabilities: uint64
    nextTransaction: uint64

var configuredFaultOccurrences {.threadvar.}: int

const
  capabilityBindings = 1'u64 shl 0
  capabilityActions = 1'u64 shl 1
  capabilityMultiOutput = 1'u64 shl 2
  capabilityChrome = 1'u64 shl 4
  capabilityConfiguration = 1'u64 shl 6
  capabilitySessionOperations = 1'u64 shl 7
  capabilityIndicators = 1'u64 shl 8
  surfaceFocusable = 1'u16 shl 2

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyClientError, message)

proc injectConfiguredFault(phase: string) =
  ## Deterministic live-gate hook. It is inert unless both variables are set,
  ## and the marker makes one supervised replacement the maximum effect.
  let selected = getEnv("HAGIA_POLICY_FAULT_AFTER")
  let marker = getEnv("HAGIA_POLICY_FAULT_MARKER")
  if selected != phase or marker.len == 0 or fileExists(marker):
    return
  inc configuredFaultOccurrences
  let occurrence = parseInt(getEnv("HAGIA_POLICY_FAULT_OCCURRENCE", "1"))
  if configuredFaultOccurrences != occurrence:
    return
  let delayMsec = parseInt(getEnv("HAGIA_POLICY_FAULT_DELAY_MSEC", "0"))
  if delayMsec > 0:
    sleep(delayMsec)
  writeFile(marker, phase & "\n")
  stderr.writeLine("hagia_policy_fault schema=1 phase=" & phase)
  quit(70)

proc toBytes(data: string): seq[byte] =
  result = newSeq[byte](data.len)
  for index, character in data:
    result[index] = byte(character)

proc toBinaryString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc receiveExact(socket: Socket, length: int): seq[byte] =
  result = newSeqOfCap[byte](length)
  while result.len < length:
    let part = socket.recv(length - result.len)
    if part.len == 0:
      fail("policy socket closed during a frame")
    result.add(part.toBytes())

proc receiveFrame(client: PolicyClient, kind: MessageKind): Frame =
  let header = client.socket.receiveExact(frameHeaderLen)
  let payloadLen = int(header.u32At(16))
  if payloadLen > maxPayloadLen:
    fail("policy frame payload is excessive")
  let payload = client.socket.receiveExact(payloadLen)
  var bytes = header
  bytes.add(payload)
  bytes.decodeFrame(kind)

proc sendFrame(client: PolicyClient, frame: Frame) =
  client.socket.send(frame.encodeFrame().toBinaryString())

proc connectWhenReady(path: string): Socket =
  for _ in 0 ..< 200:
    let socket = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    try:
      socket.connectUnix(path)
      return socket
    except OSError:
      socket.close()
      sleep(10)
  fail("Sophia policy socket did not become ready")

proc negotiatePolicy(socket: Socket, requestConfiguration: bool): PolicyClient =
  result = PolicyClient(socket: socket, nextTransaction: 1)
  var payload: seq[byte]
  payload.addU16(1)
  payload.addU16(1)
  # Request only behavior implemented by this client. The independent codec
  # still checks every draft revision-1 message in the shared corpus.
  let optional =
    if requestConfiguration:
      capabilityChrome or capabilityConfiguration or capabilitySessionOperations
    else:
      0'u64
  payload.addU64(
    capabilityBindings or capabilityActions or capabilityMultiOutput or
      capabilityIndicators or optional
  )
  result.sendFrame(Frame(kind: MessageKind.clientHello, payload: payload))
  let welcome = result.receiveFrame(MessageKind.serverWelcome)
  if welcome.payload.u16At(0) != 1:
    fail("Sophia selected an unsupported policy revision")
  result.capabilities = welcome.payload.u64At(4)
  if (
    result.capabilities and (
      capabilityBindings or capabilityActions or capabilityMultiOutput or
      capabilityIndicators
    )
  ) != (
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityIndicators
  ):
    fail("Sophia omitted a required policy capability")
  if requestConfiguration and (result.capabilities and optional) != optional:
    fail("Sophia omitted native policy configuration")
  result.connectionEpoch = welcome.payload.u64At(12)
  if result.connectionEpoch == 0 or welcome.payload.u16At(20) == 0 or
      welcome.payload.u16At(20) > uint16(maxOutputs) or welcome.payload.u32At(24) == 0 or
      welcome.payload.u32At(24) > uint32(maxSurfaces) or
      welcome.payload.u16At(22) > uint16(maxBindings) or welcome.payload.u32At(28) == 0 or
      welcome.payload.u32At(28) > uint32(maxPayloadLen):
    fail("Sophia advertised invalid policy limits")
  injectConfiguredFault("negotiated")

proc connectPolicy(path: string, requestConfiguration: bool): PolicyClient =
  path.connectWhenReady().negotiatePolicy(requestConfiguration)

proc recordBytes(payload: openArray[byte], index, size: int): seq[byte] =
  let first = 16 + index * size
  let past = first + size
  if first < 16 or past > payload.len:
    fail("policy record chunk is truncated")
  @payload[first ..< past]

proc validateSnapshot(snapshot: PolicySnapshot) =
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
  var actions = initHashSet[uint64]()
  var operationSlots = initHashSet[uint16]()
  for operation in snapshot.sessionOperations:
    if operation.operation == 0 or operation.slot == 0 or
        operation.slot in operationSlots:
      fail("policy session operation is invalid")
    operationSlots.incl(operation.slot)
  for binding in snapshot.bindings:
    if binding.action == 0 or binding.action in actions or
        binding.sessionOperationSlot != 0 and
        binding.sessionOperationSlot notin operationSlots:
      fail("policy binding is invalid")
    actions.incl(binding.action)

## Assemble into local scratch state; callers see a snapshot only after every
## identity, ordinal, record total, and terminal frame agrees.
proc receiveSnapshot(client: PolicyClient): PolicySnapshot =
  let begin = client.receiveFrame(MessageKind.snapshotBegin)
  let connectionEpoch = begin.payload.u64At(0)
  let generation = begin.payload.u64At(8)
  let activeOutput = begin.payload.u64At(16)
  let chunkCount = int(begin.payload.u16At(24))
  let declaredOutputs = int(begin.payload.u16At(26))
  let declaredSurfaces = int(begin.payload.u32At(28))
  let declaredBindings = int(begin.payload.u16At(32))
  let declaredSessionOperations = int(begin.payload.u16At(34))
  if connectionEpoch != client.connectionEpoch or generation == 0 or chunkCount == 0 or
      activeOutput == 0 or declaredOutputs == 0 or declaredOutputs > maxOutputs or
      declaredSurfaces > maxSurfaces or declaredBindings > maxBindings or
      declaredSessionOperations > maxBindings:
    fail("policy snapshot header is invalid")
  var outputs: seq[SnapshotOutput]
  var surfaces: seq[SnapshotSurface]
  var bindings: seq[SnapshotBinding]
  var sessionOperations: seq[SnapshotSessionOperation]
  for ordinal in 0 ..< chunkCount:
    let chunk = client.receiveFrame(MessageKind.snapshotChunk)
    if chunk.transaction != begin.transaction or
        chunk.payload.u64At(0) != client.connectionEpoch or
        int(chunk.payload.u16At(8)) != ordinal:
      fail("policy snapshot chunk identity is invalid")
    let recordKind = chunk.payload.u16At(10)
    let itemCount = int(chunk.payload.u32At(12))
    if itemCount == 0:
      fail("empty policy snapshot chunk")
    case recordKind
    of 1:
      if chunk.payload.len != 16 + itemCount * snapshotOutputSize or
          outputs.len + itemCount > declaredOutputs:
        fail("policy output chunk count is invalid")
      for index in 0 ..< itemCount:
        outputs.add(
          chunk.payload.recordBytes(index, snapshotOutputSize).decodeSnapshotOutput()
        )
    of 2:
      if chunk.payload.len != 16 + itemCount * snapshotSurfaceSize or
          surfaces.len + itemCount > declaredSurfaces:
        fail("policy surface chunk count is invalid")
      for index in 0 ..< itemCount:
        surfaces.add(
          chunk.payload.recordBytes(index, snapshotSurfaceSize).decodeSnapshotSurface()
        )
    of 3:
      if chunk.payload.len != 16 + itemCount * snapshotBindingSize or
          bindings.len + itemCount > declaredBindings:
        fail("policy binding chunk count is invalid")
      for index in 0 ..< itemCount:
        bindings.add(
          chunk.payload.recordBytes(index, snapshotBindingSize).decodeSnapshotBinding()
        )
    of 4:
      if chunk.payload.len != 16 + itemCount * snapshotSessionOperationSize or
          sessionOperations.len + itemCount > declaredSessionOperations:
        fail("policy session-operation chunk count is invalid")
      for index in 0 ..< itemCount:
        sessionOperations.add(
          chunk.payload
            .recordBytes(index, snapshotSessionOperationSize)
            .decodeSnapshotSessionOperation()
        )
    else:
      fail("unknown policy snapshot record kind")
  let finish = client.receiveFrame(MessageKind.snapshotEnd)
  if finish.transaction != begin.transaction or
      finish.payload.u64At(0) != client.connectionEpoch or
      finish.payload.u64At(8) != generation or
      finish.payload.u16At(16) != uint16(chunkCount) or outputs.len != declaredOutputs or
      surfaces.len != declaredSurfaces or bindings.len != declaredBindings or
      sessionOperations.len != declaredSessionOperations:
    fail("policy snapshot did not settle exactly")
  result = PolicySnapshot(
    generation: generation,
    activeOutput: activeOutput,
    outputs: outputs,
    surfaces: surfaces,
    bindings: bindings,
    sessionOperations: sessionOperations,
  )
  result.validateSnapshot()

proc receiveProjectionRequest(client: PolicyClient): ProjectionRequest =
  let frame = client.receiveFrame(MessageKind.projectionRequest)
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
  result.cause.activationSerial = frame.payload.u64At(40)
  result.cause.action = frame.payload.u64At(48)
  result.cause.targetIndex = frame.payload.u32At(56)
  result.cause.targetGeneration = frame.payload.u32At(60)
  result.cause.x = frame.payload.i32At(64)
  result.cause.y = frame.payload.i32At(68)
  result.cause.width = frame.payload.i32At(72)
  result.cause.height = frame.payload.i32At(76)
  let outputCount = int(frame.payload.u16At(80))
  if result.connectionEpoch != client.connectionEpoch or result.requestId == 0 or
      result.sceneGeneration == 0 or result.policyGeneration == 0 or outputCount == 0 or
      outputCount > maxOutputs:
    fail("policy projection request is invalid")
  for index in 0 ..< outputCount:
    result.affectedOutputs.add(frame.payload.u64At(84 + index * 8))

proc allocateTransaction(client: PolicyClient): uint64 =
  result = client.nextTransaction
  inc client.nextTransaction
  if result == 0 or client.nextTransaction == 0:
    fail("policy transaction identity space is exhausted")

proc addBinding(
    payload: var seq[byte],
    action: uint64,
    keycode, modifiers: uint32,
    sessionOperationSlot: uint16 = 0,
) =
  payload.addU64(action)
  payload.addU32(keycode)
  payload.addU32(modifiers)
  payload.addU16(sessionOperationSlot)
  payload.addU16(0)

proc installConfiguration(client: PolicyClient) =
  const
    super = 1'u32 shl 3
    shift = 1'u32 shl 0
  let bindings = @[
    (PolicyAction.focusNext.raw(), 36'u32, super, 0'u16),
    (PolicyAction.focusPrevious.raw(), 37'u32, super, 0'u16),
    (PolicyAction.moveToNextOutput.raw(), 106'u32, super or shift, 0'u16),
    (PolicyAction.moveToPreviousOutput.raw(), 105'u32, super or shift, 0'u16),
    (PolicyAction.growColumn.raw(), 38'u32, super, 0'u16),
    (PolicyAction.shrinkColumn.raw(), 35'u32, super, 0'u16),
    (PolicyAction.growWindow.raw(), 38'u32, super or shift, 0'u16),
    (PolicyAction.shrinkWindow.raw(), 35'u32, super or shift, 0'u16),
    (PolicyAction.sessionTerminal.raw(), 28'u32, super, 1'u16),
    (PolicyAction.sessionBrowser.raw(), 33'u32, super, 2'u16),
    (PolicyAction.sessionClose.raw(), 46'u32, super or shift, 3'u16),
    (PolicyAction.sessionLogout.raw(), 16'u32, super or shift, 4'u16),
    (PolicyAction.focusNextOutput.raw(), 105'u32, super, 0'u16),
    (PolicyAction.focusPreviousOutput.raw(), 106'u32, super, 0'u16),
    (PolicyAction.consumeNextColumn.raw(), 26'u32, super, 0'u16),
    (PolicyAction.expelFocusedWindow.raw(), 27'u32, super, 0'u16),
    (PolicyAction.toggleFullscreen.raw(), 21'u32, super, 0'u16),
    (PolicyAction.toggleMaximized.raw(), 50'u32, super, 0'u16),
    (PolicyAction.minimizeFocused.raw(), 49'u32, super, 0'u16),
    (PolicyAction.restoreMinimized.raw(), 19'u32, super, 0'u16),
    (PolicyAction.toggleFloating.raw(), 20'u32, super, 0'u16),
  ]
  var payload: seq[byte]
  payload.addU64(client.connectionEpoch)
  payload.addU64(1)
  payload.addU16(uint16(bindings.len + 18))
  payload.addU16(2) # Engine-owned frame; no focus ring.
  payload.addU32(0)
  payload.addU32(0xffffb6b0'u32)
  payload.addU32(1)
  payload.addU32(0xffffb6b0'u32)
  payload.addU32(0xff7c7c7c'u32)
  for binding in bindings:
    payload.addBinding(binding[0], binding[1], binding[2], binding[3])
  for slot in 1 .. 9:
    payload.addBinding(slot.activateViewAction().raw(), uint32(slot + 1), super)
    payload.addBinding(slot.moveToViewAction().raw(), uint32(slot + 1), super or shift)
  let transaction = client.allocateTransaction()
  client.sendFrame(
    Frame(
      kind: MessageKind.policyConfiguration, transaction: transaction, payload: payload
    )
  )
  let outcome = client.receiveFrame(MessageKind.policyConfigurationOutcome)
  if outcome.transaction != transaction or
      outcome.payload.u64At(0) != client.connectionEpoch or outcome.payload.u64At(8) != 1 or
      outcome.payload.u16At(16) != 1:
    fail("Sophia rejected Hagia's policy configuration")

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

proc sendProjection(
    client: PolicyClient,
    request: ProjectionRequest,
    transaction: uint64,
    projection: PolicyProjection,
): ProjectionOutcome =
  var outputBytes: seq[byte]
  var placementBytes: seq[byte]
  var indicatorBytes: seq[byte]
  var statusBytes: seq[byte]
  var placementCount = 0
  for output in projection.outputs:
    outputBytes.add(output.output.encodeProjectionOutput())
    for placement in output.placements:
      placementBytes.add(placement.encodeProjectionPlacement())
      inc placementCount
  for indicator in projection.indicators:
    indicatorBytes.add(indicator.encodeProjectionIndicator())
  for status in projection.outputStatuses:
    statusBytes.add(status.encodeProjectionOutputStatus())

  if projection.outputs.len != request.affectedOutputs.len:
    fail("projection output count does not match the request")
  let chunkCount =
    1 + (if placementCount == 0: 0 else: 1) +
    (if projection.indicators.len == 0: 0 else: 1) +
    (if projection.outputStatuses.len == 0: 0 else: 1)
  var beginPayload: seq[byte]
  beginPayload.addU64(client.connectionEpoch)
  beginPayload.addU64(request.requestId)
  beginPayload.addU64(request.sceneGeneration)
  beginPayload.addU64(projection.activeOutput)
  beginPayload.addU16(uint16(chunkCount))
  beginPayload.addU16(uint16(projection.outputs.len))
  beginPayload.addU32(uint32(placementCount))
  beginPayload.addU16(uint16(projection.indicators.len))
  beginPayload.addU16(uint16(projection.outputStatuses.len))
  client.sendFrame(
    Frame(
      kind: MessageKind.projectionBegin, transaction: transaction, payload: beginPayload
    )
  )

  var outputPayload: seq[byte]
  outputPayload.addU64(client.connectionEpoch)
  outputPayload.addU16(0)
  outputPayload.addU16(1)
  outputPayload.addU32(uint32(projection.outputs.len))
  outputPayload.add(outputBytes)
  client.sendFrame(
    Frame(
      kind: MessageKind.projectionChunk,
      transaction: transaction,
      payload: outputPayload,
    )
  )
  if placementCount > 0:
    var placementPayload: seq[byte]
    placementPayload.addU64(client.connectionEpoch)
    placementPayload.addU16(1)
    placementPayload.addU16(2)
    placementPayload.addU32(uint32(placementCount))
    placementPayload.add(placementBytes)
    client.sendFrame(
      Frame(
        kind: MessageKind.projectionChunk,
        transaction: transaction,
        payload: placementPayload,
      )
    )
  var nextOrdinal = if placementCount > 0: 2'u16 else: 1'u16
  if projection.indicators.len > 0:
    var payload: seq[byte]
    payload.addU64(client.connectionEpoch)
    payload.addU16(nextOrdinal)
    payload.addU16(3)
    payload.addU32(uint32(projection.indicators.len))
    payload.add(indicatorBytes)
    client.sendFrame(
      Frame(
        kind: MessageKind.projectionChunk, transaction: transaction, payload: payload
      )
    )
    inc nextOrdinal
  if projection.outputStatuses.len > 0:
    var payload: seq[byte]
    payload.addU64(client.connectionEpoch)
    payload.addU16(nextOrdinal)
    payload.addU16(4)
    payload.addU32(uint32(projection.outputStatuses.len))
    payload.add(statusBytes)
    client.sendFrame(
      Frame(
        kind: MessageKind.projectionChunk, transaction: transaction, payload: payload
      )
    )

  var endPayload: seq[byte]
  endPayload.addU64(client.connectionEpoch)
  endPayload.addU64(request.requestId)
  endPayload.addU64(request.sceneGeneration)
  endPayload.addU16(uint16(chunkCount))
  endPayload.addU16(0)
  client.sendFrame(
    Frame(
      kind: MessageKind.projectionEnd, transaction: transaction, payload: endPayload
    )
  )
  injectConfiguredFault("projection_submitted")
  let frame = client.receiveFrame(MessageKind.projectionOutcome)
  result = frame.decodeProjectionOutcome()
  if result.transaction != transaction or
      result.connectionEpoch != client.connectionEpoch or
      result.requestId != request.requestId or result.sceneGeneration == 0:
    fail("Sophia returned a mismatched policy outcome")

proc sendSessionOperation(
    client: PolicyClient, intent: SessionOperationIntent
): ProjectionOutcomeKind =
  var payload: seq[byte]
  payload.addU64(client.connectionEpoch)
  payload.addU64(intent.requestId)
  payload.addU64(intent.operation)
  payload.addU32(intent.targetIndex)
  payload.addU32(intent.targetGeneration)
  let transaction = client.allocateTransaction()
  client.sendFrame(
    Frame(
      kind: MessageKind.sessionOperationRequest,
      transaction: transaction,
      payload: payload,
    )
  )
  injectConfiguredFault("operation_submitted")
  let outcome = client.receiveFrame(MessageKind.sessionOperationOutcome)
  let raw = outcome.payload.u16At(16)
  if outcome.transaction != transaction or
      outcome.payload.u64At(0) != client.connectionEpoch or
      outcome.payload.u64At(8) != intent.requestId or raw < 1 or raw > 5:
    fail("Sophia returned an invalid session-operation outcome")
  injectConfiguredFault("operation_outcome_received")
  ProjectionOutcomeKind(raw)

proc requestFreshCycle(
    client: PolicyClient, policyGeneration: uint64, snapshot: PolicySnapshot
) =
  if policyGeneration == high(uint64) or snapshot.outputs.len == 0 or
      snapshot.outputs.len > maxOutputs:
    fail("policy refresh identity is invalid")
  var payload: seq[byte]
  payload.addU64(client.connectionEpoch)
  payload.addU64(policyGeneration + 1)
  payload.addU16(uint16(snapshot.outputs.len))
  payload.addU16(0)
  var outputs = initHashSet[uint64]()
  for output in snapshot.outputs:
    if output.output == 0 or output.output in outputs:
      fail("policy refresh output scope is invalid")
    outputs.incl(output.output)
    payload.addU64(output.output)
  client.sendFrame(
    Frame(
      kind: MessageKind.policyDirty,
      transaction: client.allocateTransaction(),
      payload: payload,
    )
  )
  stderr.writeLine(
    "hagia_policy_refresh schema=1 status=requested reason=checkpoint_reconciled" &
      " policy_generation=" & $(policyGeneration + 1) & " outputs=" &
      $snapshot.outputs.len
  )

## Exercise a bounded sequence of complete public-policy cycles without Triad
## machinery. The shared revision-1 corpus uses one connection so output loss
## and generational return exercise the client's retained private identity.
proc runPolicyCycles*(path: string, cycleCount: int) =
  if cycleCount < 1 or cycleCount > 16:
    fail("policy proof cycle count is invalid")
  let client = path.connectPolicy(false)
  var session = initPolicySession()
  try:
    for _ in 0 ..< cycleCount:
      let snapshot = client.receiveSnapshot()
      let request = client.receiveProjectionRequest()
      let transaction = client.allocateTransaction()
      let projection = session.prepare(snapshot, request, transaction)
      let outcome = client.sendProjection(request, transaction, projection)
      session.settle(outcome)
  finally:
    session.abort()
    client.socket.close()

## Exercise the smallest complete public-policy cycle without Triad machinery.
proc runOnePolicyCycle*(path: string) =
  path.runPolicyCycles(1)

## Process several settled projections on one authenticated connection. Sophia's
## supervisor, rather than this client, owns restart policy after transport loss.
proc runPolicySession(client: PolicyClient, configure: bool) =
  let privateCheckpoint = checkpointPath()
  var checkpointEnabled = privateCheckpoint.len > 0
  var restoredCheckpoint = false
  var session = initPolicySession()
  if checkpointEnabled:
    try:
      let restored = privateCheckpoint.loadPolicyCheckpoint()
      if restored.isSome:
        let candidate = restored.get()
        stderr.writeLine(
          "hagia_policy_checkpoint schema=1 status=loaded candidate_nonempty=" &
            $candidate.hasWindows()
        )
        session = initPolicySession(candidate)
        restoredCheckpoint = true
    except PolicyCheckpointError as error:
      stderr.writeLine(
        "hagia_policy_checkpoint schema=1 status=discarded reason=" & error.msg
      )
  try:
    if configure:
      client.installConfiguration()
      injectConfiguredFault("configuration_installed")
    while true:
      let snapshot = client.receiveSnapshot()
      injectConfiguredFault("snapshot_received")
      let request = client.receiveProjectionRequest()
      let transaction = client.allocateTransaction()
      let projection = session.prepare(snapshot, request, transaction)
      if projection.activeOutput != snapshot.activeOutput:
        stderr.writeLine(
          "hagia_policy_projection schema=1 status=active_output_changed"
        )
      injectConfiguredFault("projection_prepared")
      let operation = session.pendingOperation()
      let outcome = client.sendProjection(request, transaction, projection)
      injectConfiguredFault("outcome_received")
      session.settle(outcome)
      if outcome.kind == ProjectionOutcomeKind.committed and checkpointEnabled:
        try:
          privateCheckpoint.savePolicyCheckpoint(session.committedAdapter())
          let candidateNonempty = session.committedAdapter().hasWindows()
          stderr.writeLine(
            "hagia_policy_checkpoint schema=1 status=saved candidate_nonempty=" &
              $candidateNonempty
          )
          injectConfiguredFault("checkpoint_saved")
          if restoredCheckpoint:
            stderr.writeLine(
              "hagia_policy_checkpoint schema=1 status=reconciled candidate_nonempty=" &
                $candidateNonempty
            )
        except PolicyCheckpointError as error:
          checkpointEnabled = false
          stderr.writeLine(
            "hagia_policy_checkpoint schema=1 status=disabled reason=" & error.msg
          )
      if outcome.kind == ProjectionOutcomeKind.committed and operation.isSome:
        let operationOutcome = client.sendSessionOperation(operation.get())
        if operationOutcome == ProjectionOutcomeKind.disconnected:
          return
      if outcome.kind == ProjectionOutcomeKind.committed and restoredCheckpoint:
        client.requestFreshCycle(session.policyGeneration(), snapshot)
        restoredCheckpoint = false
      if outcome.kind == ProjectionOutcomeKind.disconnected:
        return
  finally:
    session.abort()
    client.socket.close()

proc runPolicySession*(path: string) =
  path.connectPolicy(true).runPolicySession(true)

proc runPolicySessionOnSocket*(socket: Socket) =
  socket.negotiatePolicy(false).runPolicySession(false)
