import std/[net, os, sets]

import ./[policy_session, session_types, wm_v1]

type
  PolicyClientError* = object of CatchableError

  PolicyClient = ref object
    socket: Socket
    connectionEpoch: uint64
    nextTransaction: uint64

const
  capabilityBindings = 1'u64 shl 0
  capabilityActions = 1'u64 shl 1
  capabilityMultiOutput = 1'u64 shl 2
  surfaceFocusable = 1'u16 shl 2

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyClientError, message)

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

proc negotiatePolicy(socket: Socket): PolicyClient =
  result = PolicyClient(socket: socket, nextTransaction: 1)
  var payload: seq[byte]
  payload.addU16(1)
  payload.addU16(1)
  payload.addU64(capabilityBindings or capabilityActions or capabilityMultiOutput)
  result.sendFrame(Frame(kind: MessageKind.clientHello, payload: payload))
  let welcome = result.receiveFrame(MessageKind.serverWelcome)
  if welcome.payload.u16At(0) != 1:
    fail("Sophia selected an unsupported policy revision")
  result.connectionEpoch = welcome.payload.u64At(12)
  if result.connectionEpoch == 0 or welcome.payload.u16At(20) == 0 or
      welcome.payload.u16At(20) > uint16(maxOutputs) or welcome.payload.u32At(24) == 0 or
      welcome.payload.u32At(24) > uint32(maxSurfaces) or
      welcome.payload.u16At(22) > uint16(maxBindings) or welcome.payload.u32At(28) == 0 or
      welcome.payload.u32At(28) > uint32(maxPayloadLen):
    fail("Sophia advertised invalid policy limits")

proc connectPolicy(path: string): PolicyClient =
  path.connectWhenReady().negotiatePolicy()

proc recordBytes(payload: openArray[byte], index, size: int): seq[byte] =
  let first = 16 + index * size
  let past = first + size
  if first < 16 or past > payload.len:
    fail("policy record chunk is truncated")
  @payload[first ..< past]

proc validateSnapshot(snapshot: PolicySnapshot) =
  if snapshot.generation == 0 or snapshot.outputs.len == 0 or
      snapshot.outputs.len > maxOutputs or snapshot.surfaces.len > maxSurfaces:
    fail("policy snapshot count is invalid")
  var outputs = initHashSet[uint64]()
  for output in snapshot.outputs:
    if output.output == 0 or output.generation == 0 or output.width <= 0 or
        output.height <= 0 or output.output in outputs:
      fail("policy snapshot output is invalid")
    outputs.incl(output.output)
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
            (surface.capabilityBits and surfaceFocusable) != 0:
          validFocus = true
          break
      if not validFocus:
        fail("policy output focus is invalid")

## Assemble into local scratch state; callers see a snapshot only after every
## identity, ordinal, record total, and terminal frame agrees.
proc receiveSnapshot(client: PolicyClient): PolicySnapshot =
  let begin = client.receiveFrame(MessageKind.snapshotBegin)
  let connectionEpoch = begin.payload.u64At(0)
  let generation = begin.payload.u64At(8)
  let chunkCount = int(begin.payload.u16At(16))
  let declaredOutputs = int(begin.payload.u16At(18))
  let declaredSurfaces = int(begin.payload.u32At(20))
  let declaredBindings = int(begin.payload.u16At(24))
  if connectionEpoch != client.connectionEpoch or generation == 0 or chunkCount == 0 or
      declaredOutputs == 0 or declaredOutputs > maxOutputs or
      declaredSurfaces > maxSurfaces or declaredBindings > maxBindings:
    fail("policy snapshot header is invalid")
  var outputs: seq[SnapshotOutput]
  var surfaces: seq[SnapshotSurface]
  var bindings: seq[SnapshotBinding]
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
    else:
      fail("unknown policy snapshot record kind")
  let finish = client.receiveFrame(MessageKind.snapshotEnd)
  if finish.transaction != begin.transaction or
      finish.payload.u64At(0) != client.connectionEpoch or
      finish.payload.u64At(8) != generation or
      finish.payload.u16At(16) != uint16(chunkCount) or outputs.len != declaredOutputs or
      surfaces.len != declaredSurfaces or bindings.len != declaredBindings:
    fail("policy snapshot did not settle exactly")
  result = PolicySnapshot(
    generation: generation, outputs: outputs, surfaces: surfaces, bindings: bindings
  )
  result.validateSnapshot()

proc receiveProjectionRequest(client: PolicyClient): ProjectionRequest =
  let frame = client.receiveFrame(MessageKind.projectionRequest)
  result.connectionEpoch = frame.payload.u64At(0)
  result.requestId = frame.payload.u64At(8)
  result.sceneGeneration = frame.payload.u64At(16)
  let outputCount = int(frame.payload.u16At(24))
  if result.connectionEpoch != client.connectionEpoch or result.requestId == 0 or
      result.sceneGeneration == 0 or outputCount == 0 or outputCount > maxOutputs:
    fail("policy projection request is invalid")
  for index in 0 ..< outputCount:
    result.affectedOutputs.add(frame.payload.u64At(28 + index * 8))

proc allocateTransaction(client: PolicyClient): uint64 =
  result = client.nextTransaction
  inc client.nextTransaction
  if result == 0 or client.nextTransaction == 0:
    fail("policy transaction identity space is exhausted")

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
  var placementCount = 0
  for output in projection.outputs:
    outputBytes.add(output.output.encodeProjectionOutput())
    for placement in output.placements:
      placementBytes.add(placement.encodeProjectionPlacement())
      inc placementCount

  if projection.outputs.len != request.affectedOutputs.len:
    fail("projection output count does not match the request")
  let chunkCount = if placementCount == 0: 1 else: 2
  var beginPayload: seq[byte]
  beginPayload.addU64(client.connectionEpoch)
  beginPayload.addU64(request.requestId)
  beginPayload.addU64(request.sceneGeneration)
  beginPayload.addU16(uint16(chunkCount))
  beginPayload.addU16(uint16(projection.outputs.len))
  beginPayload.addU32(uint32(placementCount))
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
  let frame = client.receiveFrame(MessageKind.projectionOutcome)
  result = frame.decodeProjectionOutcome()
  if result.transaction != transaction or
      result.connectionEpoch != client.connectionEpoch or
      result.requestId != request.requestId or result.sceneGeneration == 0:
    fail("Sophia returned a mismatched policy outcome")

## Exercise the smallest complete public-policy cycle without Triad machinery.
proc runOnePolicyCycle*(path: string) =
  let client = path.connectPolicy()
  var session = initPolicySession()
  try:
    let snapshot = client.receiveSnapshot()
    let request = client.receiveProjectionRequest()
    let transaction = client.allocateTransaction()
    let projection = session.prepare(snapshot, request, transaction)
    let outcome = client.sendProjection(request, transaction, projection)
    session.settle(outcome)
    if outcome.kind != ProjectionOutcomeKind.committed:
      fail("Sophia rejected Hagia's projection proof")
  finally:
    session.abort()
    client.socket.close()

## Process several settled projections on one authenticated connection. Sophia's
## supervisor, rather than this client, owns restart policy after transport loss.
proc runPolicySession(client: PolicyClient) =
  var session = initPolicySession()
  try:
    while true:
      let snapshot = client.receiveSnapshot()
      let request = client.receiveProjectionRequest()
      let transaction = client.allocateTransaction()
      let projection = session.prepare(snapshot, request, transaction)
      let outcome = client.sendProjection(request, transaction, projection)
      session.settle(outcome)
      if outcome.kind == ProjectionOutcomeKind.disconnected:
        return
  finally:
    session.abort()
    client.socket.close()

proc runPolicySession*(path: string) =
  path.connectPolicy().runPolicySession()

proc runPolicySessionOnSocket*(socket: Socket) =
  socket.negotiatePolicy().runPolicySession()
