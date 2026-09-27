import ../../../../src/types/wm_v1
from ../../../../src/sophia/policy_semantics import validActionNameByte

## Fixed row encoding, decoding, and validation for Sophia's WM file role. The
## record layout lives in `src/types/wm_v1.nim`; this module owns only the
## operations that read and write it, and fails closed on any malformed input.

type
  PolicyProtocolErrorKind* {.pure.} = enum
    truncated
    reservedNonzero
    trailingBytes
    fieldTooLarge

  PolicyProtocolError* = object of CatchableError
    kind*: PolicyProtocolErrorKind

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
    if not value.validActionNameByte():
      fail(PolicyProtocolErrorKind.fieldTooLarge, "policy action name is invalid")
    result.name[index] = char(value)
  for index in 12 + nameLen ..< snapshotActionSize:
    if bytes[index] != 0:
      fail(PolicyProtocolErrorKind.reservedNonzero, "policy action padding is nonzero")

proc encodeSnapshotAction*(action: SnapshotAction): seq[byte] =
  if action.name.len < 1 or action.name.len > maxActionNameBytes:
    fail(PolicyProtocolErrorKind.fieldTooLarge, "policy action name length is invalid")
  for value in action.name:
    if not byte(value).validActionNameByte():
      fail(PolicyProtocolErrorKind.fieldTooLarge, "policy action name is invalid")
  result.addU64(action.action)
  result.addU16(action.sessionOperationSlot)
  result.addU16(uint16(action.name.len))
  for value in action.name:
    result.add(byte(value))
  for _ in action.name.len ..< maxActionNameBytes:
    result.add(0)

proc decodeSnapshotSessionOperation*(bytes: openArray[byte]): SnapshotSessionOperation =
  bytes.requireExact(snapshotSessionOperationSize)
  result.operation = bytes.u64At(0)
  result.slot = bytes.u16At(8)
  result.targetBits = bytes.u16At(10)

proc encodeLaunchOriginRecord*(record: LaunchOriginRecord): seq[byte] =
  result.addU32(record.surfaceIndex)
  result.addU32(record.surfaceGeneration)
  result.addU64(record.epoch)
  result.addU64(record.token)

proc encodeOutputLaunchContext*(record: OutputLaunchContext): seq[byte] =
  if record.output == 0 or record.generation == 0 or record.epoch == 0 or
      record.token == 0:
    raise newException(ValueError, "invalid output launch context")
  result.addU64(record.output)
  result.addU64(record.generation)
  result.addU64(record.epoch)
  result.addU64(record.token)

proc decodeLaunchOriginRecord*(bytes: openArray[byte]): LaunchOriginRecord =
  bytes.requireExact(launchOriginRecordSize)
  result.surfaceIndex = bytes.u32At(0)
  result.surfaceGeneration = bytes.u32At(4)
  result.epoch = bytes.u64At(8)
  result.token = bytes.u64At(16)

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
