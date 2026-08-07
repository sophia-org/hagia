type
  PolicyProtocolErrorKind* {.pure.} = enum
    truncated
    badMagic
    unsupportedFrameVersion
    wrongMessageKind
    payloadTooLarge
    reservedNonzero
    trailingBytes
    invalidTransaction
    fieldTooLarge

  PolicyProtocolError* = object of CatchableError
    kind*: PolicyProtocolErrorKind

  MessageKind* {.pure.} = enum
    clientHello = 32
    serverWelcome = 33
    snapshotBegin = 34
    snapshotChunk = 35
    snapshotEnd = 36
    projectionRequest = 37
    projectionBegin = 38
    projectionChunk = 39
    projectionEnd = 40
    projectionOutcome = 41

  Frame* = object
    kind*: MessageKind
    transaction*: uint64
    payload*: seq[byte]

  SnapshotOutput* = object
    output*: uint64
    generation*: uint64
    focusIndex*: uint32
    focusGeneration*: uint32
    x*: int32
    y*: int32
    width*: int32
    height*: int32

  SnapshotSurface* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    stateGeneration*: uint64
    currentOutput*: uint64
    capabilityBits*: uint16
    transientIndex*: uint32
    transientGeneration*: uint32
    x*: int32
    y*: int32
    width*: int32
    height*: int32
    minWidth*: int32
    minHeight*: int32
    maxWidth*: int32
    maxHeight*: int32

  ProjectionOutput* = object
    output*: uint64
    placementCount*: uint32
    focusIndex*: uint32
    focusGeneration*: uint32

  ProjectionPlacement* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    stateGeneration*: uint64
    x*: int32
    y*: int32
    width*: int32
    height*: int32
    requestedWidth*: int32
    requestedHeight*: int32
    cropX*: int32
    cropY*: int32
    cropWidth*: int32
    cropHeight*: int32
    transform*: uint16

const
  frameHeaderLen* = 24
  maxPayloadLen* = 65536
  maxOutputs* = 16
  maxSurfaces* = 1024
  maxBindings* = 256
  snapshotOutputSize* = 40
  snapshotSurfaceSize* = 68
  projectionOutputSize* = 24
  projectionPlacementSize* = 60

proc fail(kind: PolicyProtocolErrorKind, message: string) {.noreturn.} =
  var error = newException(PolicyProtocolError, message)
  error.kind = kind
  raise error

proc requireLength(bytes: openArray[byte], offset, length: int) =
  if offset < 0 or length < 0 or offset > bytes.len or length > bytes.len - offset:
    fail(PolicyProtocolErrorKind.truncated, "truncated field")

proc u16At*(bytes: openArray[byte], offset: int): uint16 =
  bytes.requireLength(offset, 2)
  uint16(bytes[offset]) or (uint16(bytes[offset + 1]) shl 8)

proc u32At*(bytes: openArray[byte], offset: int): uint32 =
  bytes.requireLength(offset, 4)
  uint32(bytes[offset]) or (uint32(bytes[offset + 1]) shl 8) or
    (uint32(bytes[offset + 2]) shl 16) or (uint32(bytes[offset + 3]) shl 24)

proc u64At*(bytes: openArray[byte], offset: int): uint64 =
  uint64(bytes.u32At(offset)) or (uint64(bytes.u32At(offset + 4)) shl 32)

proc i32At*(bytes: openArray[byte], offset: int): int32 =
  cast[int32](bytes.u32At(offset))

proc addU16*(bytes: var seq[byte], value: uint16) =
  bytes.add(byte(value and 0xff))
  bytes.add(byte((value shr 8) and 0xff))

proc addU32*(bytes: var seq[byte], value: uint32) =
  bytes.add(byte(value and 0xff))
  bytes.add(byte((value shr 8) and 0xff))
  bytes.add(byte((value shr 16) and 0xff))
  bytes.add(byte((value shr 24) and 0xff))

proc addU64*(bytes: var seq[byte], value: uint64) =
  bytes.addU32(uint32(value and 0xffffffff'u64))
  bytes.addU32(uint32(value shr 32))

proc messageKind(raw: uint16): MessageKind =
  case raw
  of 32: MessageKind.clientHello
  of 33: MessageKind.serverWelcome
  of 34: MessageKind.snapshotBegin
  of 35: MessageKind.snapshotChunk
  of 36: MessageKind.snapshotEnd
  of 37: MessageKind.projectionRequest
  of 38: MessageKind.projectionBegin
  of 39: MessageKind.projectionChunk
  of 40: MessageKind.projectionEnd
  of 41: MessageKind.projectionOutcome
  else:
    fail(PolicyProtocolErrorKind.wrongMessageKind, "unknown message kind")

proc requireExact(payload: openArray[byte], expected: int) =
  if payload.len < expected:
    fail(PolicyProtocolErrorKind.truncated, "truncated payload")
  if payload.len > expected:
    fail(PolicyProtocolErrorKind.trailingBytes, "trailing payload bytes")

proc requireReserved(payload: openArray[byte], offset, length: int) =
  payload.requireLength(offset, length)
  for index in offset ..< offset + length:
    if payload[index] != 0:
      fail(PolicyProtocolErrorKind.reservedNonzero, "reserved field is nonzero")

proc validatePayload(kind: MessageKind, payload: openArray[byte]) =
  case kind
  of MessageKind.clientHello:
    payload.requireExact(12)
  of MessageKind.serverWelcome:
    payload.requireExact(32)
    payload.requireReserved(2, 2)
  of MessageKind.snapshotBegin:
    payload.requireExact(28)
    payload.requireReserved(26, 2)
  of MessageKind.snapshotChunk, MessageKind.projectionChunk:
    if payload.len < 16:
      fail(PolicyProtocolErrorKind.truncated, "truncated chunk prefix")
  of MessageKind.snapshotEnd:
    payload.requireExact(20)
    payload.requireReserved(18, 2)
  of MessageKind.projectionRequest:
    if payload.len < 28:
      fail(PolicyProtocolErrorKind.truncated, "truncated projection request")
    if payload.len > 156:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "affected output bytes are excessive")
    payload.requireReserved(26, 2)
    let outputCount = int(payload.u16At(24))
    if outputCount < 1 or outputCount > maxOutputs or payload.len != 28 + outputCount * 8:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "affected output count does not match")
    for index in 0 ..< outputCount:
      let output = payload.u64At(28 + index * 8)
      if output == 0:
        fail(PolicyProtocolErrorKind.fieldTooLarge, "invalid output identity")
      for previous in 0 ..< index:
        if payload.u64At(28 + previous * 8) == output:
          fail(PolicyProtocolErrorKind.fieldTooLarge, "duplicate output identity")
  of MessageKind.projectionBegin:
    payload.requireExact(32)
  of MessageKind.projectionEnd, MessageKind.projectionOutcome:
    payload.requireExact(28)
    payload.requireReserved(26, 2)

proc decodeFrame*(bytes: openArray[byte], expected: MessageKind): Frame =
  if bytes.len < frameHeaderLen:
    fail(PolicyProtocolErrorKind.truncated, "truncated frame header")
  if bytes[0] != byte('S') or bytes[1] != byte('O') or bytes[2] != byte('P') or
      bytes[3] != byte('H'):
    fail(PolicyProtocolErrorKind.badMagic, "invalid frame magic")
  if bytes.u16At(4) != 1:
    fail(PolicyProtocolErrorKind.unsupportedFrameVersion, "unsupported frame version")
  let kind = messageKind(bytes.u16At(6))
  if kind != expected:
    fail(PolicyProtocolErrorKind.wrongMessageKind, "unexpected message kind")
  let transaction = bytes.u64At(8)
  let payloadLen = int(bytes.u32At(16))
  if payloadLen > maxPayloadLen:
    fail(PolicyProtocolErrorKind.payloadTooLarge, "payload is excessive")
  if bytes.u32At(20) != 0:
    fail(PolicyProtocolErrorKind.reservedNonzero, "header reserved field is nonzero")
  if bytes.len < frameHeaderLen + payloadLen:
    fail(PolicyProtocolErrorKind.truncated, "truncated frame payload")
  if bytes.len > frameHeaderLen + payloadLen:
    fail(PolicyProtocolErrorKind.trailingBytes, "trailing frame bytes")
  if kind in {MessageKind.clientHello, MessageKind.serverWelcome}:
    if transaction != 0:
      fail(PolicyProtocolErrorKind.invalidTransaction, "handshake transaction is nonzero")
  elif transaction == 0:
    fail(PolicyProtocolErrorKind.invalidTransaction, "required transaction is zero")
  result.kind = kind
  result.transaction = transaction
  result.payload = @bytes[frameHeaderLen ..< bytes.len]
  result.kind.validatePayload(result.payload)

proc encodeFrame*(frame: Frame): seq[byte] =
  if frame.payload.len > maxPayloadLen:
    fail(PolicyProtocolErrorKind.payloadTooLarge, "payload is excessive")
  frame.kind.validatePayload(frame.payload)
  if frame.kind in {MessageKind.clientHello, MessageKind.serverWelcome}:
    if frame.transaction != 0:
      fail(PolicyProtocolErrorKind.invalidTransaction, "handshake transaction is nonzero")
  elif frame.transaction == 0:
    fail(PolicyProtocolErrorKind.invalidTransaction, "required transaction is zero")
  result = @[byte('S'), byte('O'), byte('P'), byte('H')]
  result.addU16(1)
  result.addU16(uint16(ord(frame.kind)))
  result.addU64(frame.transaction)
  result.addU32(uint32(frame.payload.len))
  result.addU32(0)
  result.add(frame.payload)

proc decodeSnapshotOutput*(bytes: openArray[byte]): SnapshotOutput =
  bytes.requireExact(snapshotOutputSize)
  result.output = bytes.u64At(0)
  result.generation = bytes.u64At(8)
  result.focusIndex = bytes.u32At(16)
  result.focusGeneration = bytes.u32At(20)
  result.x = bytes.i32At(24)
  result.y = bytes.i32At(28)
  result.width = bytes.i32At(32)
  result.height = bytes.i32At(36)

proc decodeSnapshotSurface*(bytes: openArray[byte]): SnapshotSurface =
  bytes.requireExact(snapshotSurfaceSize)
  bytes.requireReserved(26, 2)
  result.surfaceIndex = bytes.u32At(0)
  result.surfaceGeneration = bytes.u32At(4)
  result.stateGeneration = bytes.u64At(8)
  result.currentOutput = bytes.u64At(16)
  result.capabilityBits = bytes.u16At(24)
  result.transientIndex = bytes.u32At(28)
  result.transientGeneration = bytes.u32At(32)
  result.x = bytes.i32At(36)
  result.y = bytes.i32At(40)
  result.width = bytes.i32At(44)
  result.height = bytes.i32At(48)
  result.minWidth = bytes.i32At(52)
  result.minHeight = bytes.i32At(56)
  result.maxWidth = bytes.i32At(60)
  result.maxHeight = bytes.i32At(64)

proc decodeProjectionOutput*(bytes: openArray[byte]): ProjectionOutput =
  bytes.requireExact(projectionOutputSize)
  bytes.requireReserved(20, 4)
  result.output = bytes.u64At(0)
  result.placementCount = bytes.u32At(8)
  result.focusIndex = bytes.u32At(12)
  result.focusGeneration = bytes.u32At(16)

proc decodeProjectionPlacement*(bytes: openArray[byte]): ProjectionPlacement =
  bytes.requireExact(projectionPlacementSize)
  bytes.requireReserved(58, 2)
  result.surfaceIndex = bytes.u32At(0)
  result.surfaceGeneration = bytes.u32At(4)
  result.stateGeneration = bytes.u64At(8)
  result.x = bytes.i32At(16)
  result.y = bytes.i32At(20)
  result.width = bytes.i32At(24)
  result.height = bytes.i32At(28)
  result.requestedWidth = bytes.i32At(32)
  result.requestedHeight = bytes.i32At(36)
  result.cropX = bytes.i32At(40)
  result.cropY = bytes.i32At(44)
  result.cropWidth = bytes.i32At(48)
  result.cropHeight = bytes.i32At(52)
  result.transform = bytes.u16At(56)

proc encodeProjectionOutput*(record: ProjectionOutput): seq[byte] =
  result.addU64(record.output)
  result.addU32(record.placementCount)
  result.addU32(record.focusIndex)
  result.addU32(record.focusGeneration)
  result.addU32(0)

proc encodeProjectionPlacement*(record: ProjectionPlacement): seq[byte] =
  result.addU32(record.surfaceIndex)
  result.addU32(record.surfaceGeneration)
  result.addU64(record.stateGeneration)
  result.addU32(cast[uint32](record.x))
  result.addU32(cast[uint32](record.y))
  result.addU32(cast[uint32](record.width))
  result.addU32(cast[uint32](record.height))
  result.addU32(cast[uint32](record.requestedWidth))
  result.addU32(cast[uint32](record.requestedHeight))
  result.addU32(cast[uint32](record.cropX))
  result.addU32(cast[uint32](record.cropY))
  result.addU32(cast[uint32](record.cropWidth))
  result.addU32(cast[uint32](record.cropHeight))
  result.addU16(record.transform)
  result.addU16(0)
