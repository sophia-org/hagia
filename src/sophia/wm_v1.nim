const
  ## Fixed octet run shared by indicator labels and layout names. Declared
  ## ahead of the type section because it bounds an array field.
  indicatorLabelLen* = 32
  profileDigestLen* = 32

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
    policyConfiguration = 42
    policyConfigurationOutcome = 43
    policyDirty = 44
    sessionOperationRequest = 45
    sessionOperationOutcome = 46
    profilePrepare = 47
    profilePrepared = 48
    profileActivate = 49
    profileActive = 50
    profileRollback = 51
    profileRolledBack = 52

  Frame* = object
    kind*: MessageKind
    transaction*: uint64
    payload*: seq[byte]

  ProfileIdentity* = object
    connectionEpoch*: uint64
    profileGeneration*: uint64
    profileDigest*: array[profileDigestLen, byte]

  ProfileOutcomeKind* {.pure.} = enum
    accepted = 1
    rejectedIdentity = 2
    rejectedState = 3

  ProfileCommand* = object
    transaction*: uint64
    identity*: ProfileIdentity

  ProfileCompletion* = object
    transaction*: uint64
    identity*: ProfileIdentity
    outcome*: ProfileOutcomeKind

  SnapshotOutput* = object
    output*: uint64
    generation*: uint64
    focusIndex*: uint32
    focusGeneration*: uint32
    x*: int32
    y*: int32
    width*: int32
    height*: int32
    workX*: int32
    workY*: int32
    workWidth*: int32
    workHeight*: int32

  SnapshotSurface* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    stateGeneration*: uint64
    currentOutput*: uint64
    capabilityBits*: uint16
    kind*: uint16
    requestStateBits*: uint16
    currentStateBits*: uint16
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
    exactWidth*: int32
    exactHeight*: int32

  SnapshotAction* = object
    action*: uint64
    sessionOperationSlot*: uint16
    name*: string

  SnapshotSessionOperation* = object
    operation*: uint64
    slot*: uint16
    targetBits*: uint16

  SnapshotSurfaceClassification* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    classification*: uint64

  ProjectionOutput* = object
    output*: uint64
    placementCount*: uint32
    focusIndex*: uint32
    focusGeneration*: uint32

  ## Policy-authored desktop status. The label is a fixed octet run so the
  ## record stays fixed width; `labelLen` gives the used prefix and the rest
  ## must be zero.
  ProjectionIndicator* = object
    output*: uint64
    slot*: uint32
    indicator*: uint64
    action*: uint64
    stateBits*: uint16
    labelLen*: uint16
    label*: array[indicatorLabelLen, byte]

  ProjectionOutputStatus* = object
    output*: uint64
    focusBits*: uint16
    layoutLen*: uint16
    layout*: array[indicatorLabelLen, byte]

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
    presentationBits*: uint16

const
  frameHeaderLen* = 24
  maxPayloadLen* = 65536
  maxOutputs* = 16
  maxSurfaces* = 1024
  maxBindings* = 256
  maxActionNameBytes* = 128
  snapshotOutputSize* = 56
  snapshotSurfaceSize* = 80
  snapshotActionSize* = 140
  snapshotSurfaceClassificationSize* = 16
  snapshotSessionOperationSize* = 12
  projectionOutputSize* = 24
  projectionPlacementSize* = 60
  projectionIndicatorSize* = 64
  projectionOutputStatusSize* = 48
  maxIndicators* = 256

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
  of 32:
    MessageKind.clientHello
  of 33:
    MessageKind.serverWelcome
  of 34:
    MessageKind.snapshotBegin
  of 35:
    MessageKind.snapshotChunk
  of 36:
    MessageKind.snapshotEnd
  of 37:
    MessageKind.projectionRequest
  of 38:
    MessageKind.projectionBegin
  of 39:
    MessageKind.projectionChunk
  of 40:
    MessageKind.projectionEnd
  of 41:
    MessageKind.projectionOutcome
  of 42:
    MessageKind.policyConfiguration
  of 43:
    MessageKind.policyConfigurationOutcome
  of 44:
    MessageKind.policyDirty
  of 45:
    MessageKind.sessionOperationRequest
  of 46:
    MessageKind.sessionOperationOutcome
  of 47:
    MessageKind.profilePrepare
  of 48:
    MessageKind.profilePrepared
  of 49:
    MessageKind.profileActivate
  of 50:
    MessageKind.profileActive
  of 51:
    MessageKind.profileRollback
  of 52:
    MessageKind.profileRolledBack
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

proc validateProfileIdentity(payload: openArray[byte]) =
  if payload.u64At(0) == 0 or payload.u64At(8) == 0:
    fail(PolicyProtocolErrorKind.fieldTooLarge, "profile identity is null")
  var digestNonzero = false
  for index in 16 ..< 48:
    digestNonzero = digestNonzero or payload[index] != 0
  if not digestNonzero:
    fail(PolicyProtocolErrorKind.fieldTooLarge, "profile digest is null")

proc validatePayload(kind: MessageKind, payload: openArray[byte]) =
  case kind
  of MessageKind.clientHello:
    payload.requireExact(12)
  of MessageKind.serverWelcome:
    payload.requireExact(32)
    payload.requireReserved(2, 2)
  of MessageKind.snapshotBegin:
    payload.requireExact(36)
  of MessageKind.snapshotChunk, MessageKind.projectionChunk:
    if payload.len < 16:
      fail(PolicyProtocolErrorKind.truncated, "truncated chunk prefix")
  of MessageKind.snapshotEnd:
    payload.requireExact(20)
    payload.requireReserved(18, 2)
  of MessageKind.projectionRequest:
    if payload.len < 84:
      fail(PolicyProtocolErrorKind.truncated, "truncated projection request")
    if payload.len > 212:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "affected output bytes are excessive")
    payload.requireReserved(82, 2)
    let outputCount = int(payload.u16At(80))
    if outputCount < 1 or outputCount > maxOutputs or payload.len != 84 + outputCount * 8:
      fail(
        PolicyProtocolErrorKind.fieldTooLarge, "affected output count does not match"
      )
    for index in 0 ..< outputCount:
      let output = payload.u64At(84 + index * 8)
      if output == 0:
        fail(PolicyProtocolErrorKind.fieldTooLarge, "invalid output identity")
      for previous in 0 ..< index:
        if payload.u64At(84 + previous * 8) == output:
          fail(PolicyProtocolErrorKind.fieldTooLarge, "duplicate output identity")
  of MessageKind.projectionBegin:
    payload.requireExact(44)
  of MessageKind.projectionEnd, MessageKind.projectionOutcome:
    payload.requireExact(28)
    payload.requireReserved(26, 2)
  of MessageKind.policyConfiguration:
    if payload.len < 40:
      fail(PolicyProtocolErrorKind.truncated, "truncated policy configuration")
    if payload.len > 35880:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "policy actions are excessive")
    let actionCount = int(payload.u16At(16))
    if actionCount > maxBindings or payload.len != 40 + actionCount * snapshotActionSize:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "policy action count does not match")
  of MessageKind.policyConfigurationOutcome, MessageKind.sessionOperationOutcome:
    payload.requireExact(20)
    payload.requireReserved(18, 2)
  of MessageKind.policyDirty:
    if payload.len < 20:
      fail(PolicyProtocolErrorKind.truncated, "truncated policy dirty request")
    if payload.len > 148:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "dirty output bytes are excessive")
    payload.requireReserved(18, 2)
    let outputCount = int(payload.u16At(16))
    if outputCount < 1 or outputCount > maxOutputs or payload.len != 20 + outputCount * 8:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "dirty output count does not match")
  of MessageKind.sessionOperationRequest:
    payload.requireExact(32)
  of MessageKind.profilePrepare, MessageKind.profileActivate,
      MessageKind.profileRollback:
    payload.requireExact(48)
    payload.validateProfileIdentity()
  of MessageKind.profilePrepared, MessageKind.profileActive,
      MessageKind.profileRolledBack:
    payload.requireExact(52)
    payload.validateProfileIdentity()
    let outcome = payload.u16At(48)
    if outcome < 1 or outcome > 3:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "profile outcome is invalid")
    payload.requireReserved(50, 2)

proc decodeFrame*(bytes: openArray[byte]): Frame =
  if bytes.len < frameHeaderLen:
    fail(PolicyProtocolErrorKind.truncated, "truncated frame header")
  if bytes[0] != byte('S') or bytes[1] != byte('O') or bytes[2] != byte('P') or
      bytes[3] != byte('H'):
    fail(PolicyProtocolErrorKind.badMagic, "invalid frame magic")
  if bytes.u16At(4) != 1:
    fail(PolicyProtocolErrorKind.unsupportedFrameVersion, "unsupported frame version")
  let kind = messageKind(bytes.u16At(6))
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
      fail(
        PolicyProtocolErrorKind.invalidTransaction, "handshake transaction is nonzero"
      )
  elif transaction == 0:
    fail(PolicyProtocolErrorKind.invalidTransaction, "required transaction is zero")
  result.kind = kind
  result.transaction = transaction
  result.payload = @bytes[frameHeaderLen ..< bytes.len]
  result.kind.validatePayload(result.payload)

proc decodeFrame*(bytes: openArray[byte], expected: MessageKind): Frame =
  result = bytes.decodeFrame()
  if result.kind != expected:
    fail(PolicyProtocolErrorKind.wrongMessageKind, "unexpected message kind")

proc encodeFrame*(frame: Frame): seq[byte] =
  if frame.payload.len > maxPayloadLen:
    fail(PolicyProtocolErrorKind.payloadTooLarge, "payload is excessive")
  frame.kind.validatePayload(frame.payload)
  if frame.kind in {MessageKind.clientHello, MessageKind.serverWelcome}:
    if frame.transaction != 0:
      fail(
        PolicyProtocolErrorKind.invalidTransaction, "handshake transaction is nonzero"
      )
  elif frame.transaction == 0:
    fail(PolicyProtocolErrorKind.invalidTransaction, "required transaction is zero")
  result = @[byte('S'), byte('O'), byte('P'), byte('H')]
  result.addU16(1)
  result.addU16(uint16(ord(frame.kind)))
  result.addU64(frame.transaction)
  result.addU32(uint32(frame.payload.len))
  result.addU32(0)
  result.add(frame.payload)

proc addProfileIdentity(payload: var seq[byte], identity: ProfileIdentity) =
  payload.addU64(identity.connectionEpoch)
  payload.addU64(identity.profileGeneration)
  for value in identity.profileDigest:
    payload.add(value)

proc decodeProfileIdentity(payload: openArray[byte]): ProfileIdentity =
  payload.validateProfileIdentity()
  result.connectionEpoch = payload.u64At(0)
  result.profileGeneration = payload.u64At(8)
  for index in 0 ..< profileDigestLen:
    result.profileDigest[index] = payload[16 + index]

proc profileCommandFrame*(
    kind: MessageKind, transaction: uint64, identity: ProfileIdentity
): Frame =
  if kind notin {
    MessageKind.profilePrepare, MessageKind.profileActivate, MessageKind.profileRollback
  }:
    fail(PolicyProtocolErrorKind.wrongMessageKind, "message is not a profile command")
  result.kind = kind
  result.transaction = transaction
  result.payload.addProfileIdentity(identity)
  kind.validatePayload(result.payload)

proc decodeProfileCommand*(frame: Frame): ProfileCommand =
  if frame.kind notin {
    MessageKind.profilePrepare, MessageKind.profileActivate, MessageKind.profileRollback
  }:
    fail(PolicyProtocolErrorKind.wrongMessageKind, "message is not a profile command")
  if frame.transaction == 0:
    fail(PolicyProtocolErrorKind.invalidTransaction, "profile transaction is null")
  frame.kind.validatePayload(frame.payload)
  result.transaction = frame.transaction
  result.identity = frame.payload.decodeProfileIdentity()

proc profileCompletionFrame*(
    kind: MessageKind,
    transaction: uint64,
    identity: ProfileIdentity,
    outcome: ProfileOutcomeKind,
): Frame =
  if kind notin {
    MessageKind.profilePrepared, MessageKind.profileActive,
    MessageKind.profileRolledBack,
  }:
    fail(
      PolicyProtocolErrorKind.wrongMessageKind, "message is not a profile completion"
    )
  result.kind = kind
  result.transaction = transaction
  result.payload.addProfileIdentity(identity)
  result.payload.addU16(uint16(ord(outcome)))
  result.payload.addU16(0)
  kind.validatePayload(result.payload)

proc decodeProfileCompletion*(frame: Frame): ProfileCompletion =
  if frame.kind notin {
    MessageKind.profilePrepared, MessageKind.profileActive,
    MessageKind.profileRolledBack,
  }:
    fail(
      PolicyProtocolErrorKind.wrongMessageKind, "message is not a profile completion"
    )
  if frame.transaction == 0:
    fail(PolicyProtocolErrorKind.invalidTransaction, "profile transaction is null")
  frame.kind.validatePayload(frame.payload)
  result.transaction = frame.transaction
  result.identity = frame.payload.decodeProfileIdentity()
  result.outcome = ProfileOutcomeKind(frame.payload.u16At(48))

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
  result.workX = bytes.i32At(40)
  result.workY = bytes.i32At(44)
  result.workWidth = bytes.i32At(48)
  result.workHeight = bytes.i32At(52)

proc decodeSnapshotSurface*(bytes: openArray[byte]): SnapshotSurface =
  bytes.requireExact(snapshotSurfaceSize)
  result.surfaceIndex = bytes.u32At(0)
  result.surfaceGeneration = bytes.u32At(4)
  result.stateGeneration = bytes.u64At(8)
  result.currentOutput = bytes.u64At(16)
  result.capabilityBits = bytes.u16At(24)
  result.kind = bytes.u16At(26)
  result.requestStateBits = bytes.u16At(28)
  result.currentStateBits = bytes.u16At(30)
  result.transientIndex = bytes.u32At(32)
  result.transientGeneration = bytes.u32At(36)
  result.x = bytes.i32At(40)
  result.y = bytes.i32At(44)
  result.width = bytes.i32At(48)
  result.height = bytes.i32At(52)
  result.minWidth = bytes.i32At(56)
  result.minHeight = bytes.i32At(60)
  result.maxWidth = bytes.i32At(64)
  result.maxHeight = bytes.i32At(68)
  result.exactWidth = bytes.i32At(72)
  result.exactHeight = bytes.i32At(76)

proc decodeSnapshotAction*(bytes: openArray[byte]): SnapshotAction =
  bytes.requireExact(snapshotActionSize)
  result.action = bytes.u64At(0)
  result.sessionOperationSlot = bytes.u16At(8)
  let nameLen = int(bytes.u16At(10))
  if nameLen < 1 or nameLen > maxActionNameBytes:
    fail(PolicyProtocolErrorKind.fieldTooLarge, "policy action name length is invalid")
  result.name = newString(nameLen)
  for index in 0 ..< nameLen:
    let value = bytes[12 + index]
    if not (
      value >= byte('a') and value <= byte('z') or
      value >= byte('A') and value <= byte('Z') or
      value >= byte('0') and value <= byte('9') or
      value in [byte('-'), byte('_'), byte(' '), byte('.')]
    ):
      fail(PolicyProtocolErrorKind.fieldTooLarge, "policy action name is invalid")
    result.name[index] = char(value)
  for index in 12 + nameLen ..< snapshotActionSize:
    if bytes[index] != 0:
      fail(PolicyProtocolErrorKind.reservedNonzero, "policy action padding is nonzero")

proc decodeSnapshotSessionOperation*(bytes: openArray[byte]): SnapshotSessionOperation =
  bytes.requireExact(snapshotSessionOperationSize)
  result.operation = bytes.u64At(0)
  result.slot = bytes.u16At(8)
  result.targetBits = bytes.u16At(10)

proc decodeSnapshotSurfaceClassification*(
    bytes: openArray[byte]
): SnapshotSurfaceClassification =
  bytes.requireExact(snapshotSurfaceClassificationSize)
  result.surfaceIndex = bytes.u32At(0)
  result.surfaceGeneration = bytes.u32At(4)
  result.classification = bytes.u64At(8)

proc decodeProjectionOutput*(bytes: openArray[byte]): ProjectionOutput =
  bytes.requireExact(projectionOutputSize)
  bytes.requireReserved(20, 4)
  result.output = bytes.u64At(0)
  result.placementCount = bytes.u32At(8)
  result.focusIndex = bytes.u32At(12)
  result.focusGeneration = bytes.u32At(16)

proc decodeProjectionPlacement*(bytes: openArray[byte]): ProjectionPlacement =
  bytes.requireExact(projectionPlacementSize)
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
  result.presentationBits = bytes.u16At(58)

proc decodeProjectionIndicator*(bytes: openArray[byte]): ProjectionIndicator =
  bytes.requireExact(projectionIndicatorSize)
  result.output = bytes.u64At(0)
  result.slot = bytes.u32At(8)
  result.indicator = bytes.u64At(12)
  result.action = bytes.u64At(20)
  result.stateBits = bytes.u16At(28)
  result.labelLen = bytes.u16At(30)
  if int(result.labelLen) > indicatorLabelLen:
    fail(PolicyProtocolErrorKind.fieldTooLarge, "indicator label length is excessive")
  for index in 0 ..< indicatorLabelLen:
    let value = bytes[32 + index]
    if index >= int(result.labelLen) and value != 0:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "indicator label padding is not zero")
    result.label[index] = value

proc decodeProjectionOutputStatus*(bytes: openArray[byte]): ProjectionOutputStatus =
  bytes.requireExact(projectionOutputStatusSize)
  bytes.requireReserved(12, 4)
  result.output = bytes.u64At(0)
  result.focusBits = bytes.u16At(8)
  result.layoutLen = bytes.u16At(10)
  if int(result.layoutLen) > indicatorLabelLen:
    fail(PolicyProtocolErrorKind.fieldTooLarge, "layout name length is excessive")
  for index in 0 ..< indicatorLabelLen:
    let value = bytes[16 + index]
    if index >= int(result.layoutLen) and value != 0:
      fail(PolicyProtocolErrorKind.fieldTooLarge, "layout name padding is not zero")
    result.layout[index] = value

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
  result.addU16(record.presentationBits)

proc encodeProjectionIndicator*(record: ProjectionIndicator): seq[byte] =
  result.addU64(record.output)
  result.addU32(record.slot)
  result.addU64(record.indicator)
  result.addU64(record.action)
  result.addU16(record.stateBits)
  result.addU16(record.labelLen)
  for value in record.label:
    result.add(value)

proc encodeProjectionOutputStatus*(record: ProjectionOutputStatus): seq[byte] =
  result.addU64(record.output)
  result.addU16(record.focusBits)
  result.addU16(record.layoutLen)
  result.addU32(0)
  for value in record.layout:
    result.add(value)
