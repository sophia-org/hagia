import std/[algorithm, options, sequtils, sets]

import ../types/shell_v1

## Frame encoding, decoding, and the shell candidate reducer. The record layout
## lives in `src/types/shell_v1.nim`; malformed input fails closed here.

type ShellProtocolError* = object of CatchableError

proc fail(message: string) {.noreturn.} =
  raise newException(ShellProtocolError, message)

proc require(bytes: openArray[byte], offset, length: int) =
  if offset < 0 or length < 0 or offset > bytes.len or length > bytes.len - offset:
    fail("shell frame is truncated")

proc u16At*(bytes: openArray[byte], offset: int): uint16 =
  bytes.require(offset, 2)
  uint16(bytes[offset]) or (uint16(bytes[offset + 1]) shl 8)

proc u32At*(bytes: openArray[byte], offset: int): uint32 =
  bytes.require(offset, 4)
  uint32(bytes[offset]) or (uint32(bytes[offset + 1]) shl 8) or
    (uint32(bytes[offset + 2]) shl 16) or (uint32(bytes[offset + 3]) shl 24)

proc u64At*(bytes: openArray[byte], offset: int): uint64 =
  uint64(bytes.u32At(offset)) or (uint64(bytes.u32At(offset + 4)) shl 32)

proc addU8(bytes: var seq[byte], value: uint8) =
  bytes.add(byte(value))

proc addU16*(bytes: var seq[byte], value: uint16) =
  bytes.add(byte(value and 0xff))
  bytes.add(byte((value shr 8) and 0xff))

proc addU32(bytes: var seq[byte], value: uint32) =
  bytes.add(byte(value and 0xff))
  bytes.add(byte((value shr 8) and 0xff))
  bytes.add(byte((value shr 16) and 0xff))
  bytes.add(byte((value shr 24) and 0xff))

proc addU64*(bytes: var seq[byte], value: uint64) =
  bytes.addU32(uint32(value and 0xffffffff'u64))
  bytes.addU32(uint32(value shr 32))

proc kind(raw: uint16): ShellMessageKind =
  case raw
  of 96:
    ShellMessageKind.clientHello
  of 97:
    ShellMessageKind.serverWelcome
  of 98:
    ShellMessageKind.descriptorSnapshot
  of 99:
    ShellMessageKind.candidate
  of 100:
    ShellMessageKind.candidateOutcome
  of 101:
    ShellMessageKind.activation
  of 102:
    ShellMessageKind.activationAck
  else:
    fail("unknown shell message kind")

proc validatePayload(kind: ShellMessageKind, payload: openArray[byte]) =
  case kind
  of ShellMessageKind.clientHello:
    if payload.len != 12:
      fail("invalid shell hello length")
  of ShellMessageKind.serverWelcome:
    if payload.len != 28 or payload.u16At(2) != 0 or payload.u16At(26) != 0:
      fail("invalid shell welcome")
  of ShellMessageKind.descriptorSnapshot:
    if payload.len < 52 or payload.u16At(50) != 0:
      fail("invalid shell snapshot prefix")
  of ShellMessageKind.candidate:
    if payload.len < 40 or payload[33] > 4 or
        (payload[33] == 0) != (payload.u16At(38) == 0) or
        payload.u16At(38) > shellMaxReservationThickness or
        (payload[32] == 0 and payload[33] != 0):
      fail("invalid shell candidate reservation")
  of ShellMessageKind.candidateOutcome:
    if payload.len != 28 or payload.u16At(26) != 0:
      fail("invalid shell outcome")
  of ShellMessageKind.activation:
    if payload.len != 76 or payload.u16At(66) != 0:
      fail("invalid shell activation")
  of ShellMessageKind.activationAck:
    if payload.len != 20 or payload.u16At(18) != 0:
      fail("invalid shell activation acknowledgement")

proc decodeShellFrame*(bytes: openArray[byte]): ShellFrame =
  if bytes.len < shellFrameHeaderLen:
    fail("shell frame header is truncated")
  if bytes[0] != byte('S') or bytes[1] != byte('O') or bytes[2] != byte('P') or
      bytes[3] != byte('H'):
    fail("invalid shell frame magic")
  if bytes.u16At(4) != 1 or bytes.u32At(20) != 0:
    fail("invalid shell frame envelope")
  result.kind = bytes.u16At(6).kind()
  result.transaction = bytes.u64At(8)
  let payloadLength = int(bytes.u32At(16))
  if payloadLength > shellMaxPayloadLen or
      bytes.len != shellFrameHeaderLen + payloadLength:
    fail("invalid shell frame length")
  let handshake =
    result.kind in {ShellMessageKind.clientHello, ShellMessageKind.serverWelcome}
  if handshake == (result.transaction != 0):
    fail("invalid shell transaction")
  result.payload = @bytes[shellFrameHeaderLen ..< bytes.len]
  result.kind.validatePayload(result.payload)

proc encodeShellFrame*(frame: ShellFrame): seq[byte] =
  frame.kind.validatePayload(frame.payload)
  let handshake =
    frame.kind in {ShellMessageKind.clientHello, ShellMessageKind.serverWelcome}
  if handshake == (frame.transaction != 0):
    fail("invalid shell transaction")
  result = @[byte('S'), byte('O'), byte('P'), byte('H')]
  result.addU16(1)
  result.addU16(uint16(ord(frame.kind)))
  result.addU64(frame.transaction)
  result.addU32(uint32(frame.payload.len))
  result.addU32(0)
  result.add(frame.payload)

proc clientHelloFrame*(): ShellFrame =
  result.kind = ShellMessageKind.clientHello
  result.payload.addU16(1)
  result.payload.addU16(1)
  result.payload.addU64(shellDescriptorCapability)

proc validateWelcome*(frame: ShellFrame): uint64 =
  if frame.kind != ShellMessageKind.serverWelcome or frame.payload.u16At(0) != 1 or
      frame.payload.u64At(4) == 0 or
      (frame.payload.u64At(12) and shellDescriptorCapability) == 0 or
      frame.payload.u16At(20) == 0 or
      frame.payload.u16At(20) > uint16(shellMaxDescriptors) or
      frame.payload.u16At(22) == 0 or
      frame.payload.u16At(22) > uint16(shellMaxLabelBytes) or
      frame.payload.u16At(24) == 0:
    fail("Sophia advertised invalid shell limits")
  frame.payload.u64At(4)

proc decodeAction(payload: openArray[byte], offset: int): ShellActionRef =
  result.token = payload.u64At(offset)
  result.issuerEpoch = payload.u64At(offset + 8)
  result.issuerRevocationEpoch = payload.u64At(offset + 16)
  result.recipientEpoch = payload.u64At(offset + 24)
  result.targetSlot = payload.u16At(offset + 32)
  if payload.u16At(offset + 34) != 0:
    fail("shell action reserved field is nonzero")
  result.targetGeneration = payload.u64At(offset + 36)
  if result.token == 0 or result.issuerEpoch == 0 or result.issuerRevocationEpoch == 0 or
      result.recipientEpoch == 0 or result.targetSlot == 0 or
      result.targetGeneration == 0:
    fail("shell action identity is null")

proc encodeAction(payload: var seq[byte], action: ShellActionRef) =
  payload.addU64(action.token)
  payload.addU64(action.issuerEpoch)
  payload.addU64(action.issuerRevocationEpoch)
  payload.addU64(action.recipientEpoch)
  payload.addU16(action.targetSlot)
  payload.addU16(0)
  payload.addU64(action.targetGeneration)

proc decodeSnapshot*(frame: ShellFrame): ShellSnapshot =
  if frame.kind != ShellMessageKind.descriptorSnapshot:
    fail("expected a shell descriptor snapshot")
  let payload = frame.payload
  result.connectionEpoch = payload.u64At(0)
  result.generation = payload.u64At(8)
  result.output = payload.u64At(16)
  result.outputGeneration = payload.u64At(24)
  result.brokerEpoch = payload.u64At(32)
  result.brokerRevocationEpoch = payload.u64At(40)
  let count = int(payload.u16At(48))
  if result.connectionEpoch == 0 or result.generation == 0 or result.output == 0 or
      result.outputGeneration == 0 or result.brokerEpoch == 0 or
      result.brokerRevocationEpoch == 0 or count > shellMaxDescriptors:
    fail("invalid shell snapshot identity")
  var offset = 52
  var slots = initHashSet[uint16]()
  for _ in 0 ..< count:
    payload.require(offset, 57)
    var descriptor: ShellDescriptor
    descriptor.slot = payload.u16At(offset)
    descriptor.trust = uint8(payload[offset + 2])
    descriptor.attention = uint8(payload[offset + 3])
    descriptor.generation = payload.u64At(offset + 4)
    descriptor.action = payload.decodeAction(offset + 12)
    let present = payload[offset + 56]
    offset += 57
    if present > 1:
      fail("invalid shell descriptor label")
    var labelLength = 0
    if present == 1:
      payload.require(offset, 2)
      labelLength = int(payload.u16At(offset))
      offset += 2
      if labelLength > shellMaxLabelBytes:
        fail("invalid shell descriptor label")
      if labelLength == 0:
        fail("empty shell descriptor label")
      payload.require(offset, labelLength)
      var label = newString(labelLength)
      for index in 0 ..< labelLength:
        if payload[offset + index] < 0x20 or payload[offset + index] == 0x7f:
          fail("control byte in shell descriptor label")
        label[index] = char(payload[offset + index])
      descriptor.label = some(label)
      offset += labelLength
    payload.require(offset, 1)
    descriptor.labelRedacted = payload[offset] == 1
    if payload[offset] > 1 or (descriptor.label.isNone and descriptor.labelRedacted):
      fail("invalid shell descriptor redaction")
    inc offset
    if descriptor.slot == 0 or descriptor.generation == 0 or descriptor.slot in slots or
        descriptor.trust > 3 or descriptor.attention > 2 or
        descriptor.action.issuerEpoch != result.brokerEpoch or
        descriptor.action.issuerRevocationEpoch != result.brokerRevocationEpoch or
        descriptor.action.recipientEpoch != result.connectionEpoch or
        descriptor.action.targetSlot != descriptor.slot or
        descriptor.action.targetGeneration != descriptor.generation:
      fail("invalid shell descriptor")
    slots.incl(descriptor.slot)
    result.descriptors.add(descriptor)
  if offset != payload.len:
    fail("trailing shell descriptor bytes")

proc reconcile*(model: var ShellModel, snapshot: ShellSnapshot) =
  if model.connectionEpoch != snapshot.connectionEpoch:
    model = ShellModel(connectionEpoch: snapshot.connectionEpoch)
  var live = initHashSet[ShellDescriptorKey]()
  for descriptor in snapshot.descriptors:
    live.incl(
      ShellDescriptorKey(slot: descriptor.slot, generation: descriptor.generation)
    )
  model.order.keepItIf(it in live)
  var additions: seq[ShellDescriptorKey]
  for key in live:
    if key notin model.order:
      additions.add(key)
  additions.sort(
    proc(a, b: ShellDescriptorKey): int =
      result = cmp(a.slot, b.slot)
      if result == 0:
        result = cmp(a.generation, b.generation)
  )
  model.order.add(additions)
  model.snapshotGeneration = snapshot.generation
  model.output = snapshot.output
  if model.selected.isNone or model.order.allIt(it.slot != model.selected.get()):
    model.selected =
      if model.order.len == 0:
        none(uint16)
      else:
        some(model.order[0].slot)

proc candidate*(
    model: ShellModel,
    generation: uint64,
    visible: bool,
    reservation = none(ShellReservation),
): ShellCandidate =
  result.connectionEpoch = model.connectionEpoch
  result.snapshotGeneration = model.snapshotGeneration
  result.generation = generation
  result.output = model.output
  result.visible = visible and model.order.len > 0
  if result.visible:
    result.selected = model.selected
    result.entries = model.order
    result.reservation = reservation

proc candidateFrame*(candidate: ShellCandidate, transaction: uint64): ShellFrame =
  if candidate.connectionEpoch == 0 or candidate.snapshotGeneration == 0 or
      candidate.generation == 0 or candidate.output == 0 or
      candidate.visible != (candidate.entries.len > 0) or
      candidate.visible != candidate.selected.isSome:
    fail("invalid shell candidate")
  if candidate.reservation.isSome:
    if not candidate.visible:
      fail("hidden shell candidate cannot reserve")
    let thickness = candidate.reservation.get().thicknessPx
    if thickness == 0 or thickness > shellMaxReservationThickness:
      fail("invalid shell reservation thickness")
  result.kind = ShellMessageKind.candidate
  result.transaction = transaction
  result.payload.addU64(candidate.connectionEpoch)
  result.payload.addU64(candidate.snapshotGeneration)
  result.payload.addU64(candidate.generation)
  result.payload.addU64(candidate.output)
  result.payload.addU8(uint8(candidate.visible))
  result.payload.addU8(
    if candidate.reservation.isSome:
      uint8(ord(candidate.reservation.get().edge))
    else:
      0
  )
  result.payload.addU16(
    if candidate.selected.isSome:
      candidate.selected.get()
    else:
      0
  )
  result.payload.addU16(uint16(candidate.entries.len))
  result.payload.addU16(
    if candidate.reservation.isSome:
      candidate.reservation.get().thicknessPx
    else:
      0
  )
  for entry in candidate.entries:
    result.payload.addU16(entry.slot)
    result.payload.addU16(0)
    result.payload.addU64(entry.generation)

proc decodeOutcome*(frame: ShellFrame): ShellCandidateOutcome =
  if frame.kind != ShellMessageKind.candidateOutcome:
    fail("expected a shell candidate outcome")
  result.connectionEpoch = frame.payload.u64At(0)
  result.candidateGeneration = frame.payload.u64At(8)
  result.presentationEpoch = frame.payload.u64At(16)
  let raw = frame.payload.u16At(24)
  if raw < 1 or raw > 4:
    fail("unknown shell candidate outcome")
  result.kind = ShellCandidateOutcomeKind(raw)
  if result.connectionEpoch == 0 or result.candidateGeneration == 0 or (
    (result.kind == ShellCandidateOutcomeKind.presented) !=
    (result.presentationEpoch != 0)
  ):
    fail("invalid shell candidate outcome")

proc decodeActivation*(frame: ShellFrame): ShellActivation =
  if frame.kind != ShellMessageKind.activation:
    fail("expected a shell activation")
  result.connectionEpoch = frame.payload.u64At(0)
  result.candidateGeneration = frame.payload.u64At(8)
  result.presentationEpoch = frame.payload.u64At(16)
  result.activation = frame.payload.u64At(24)
  result.action = frame.payload.decodeAction(32)
  if result.connectionEpoch == 0 or result.candidateGeneration == 0 or
      result.presentationEpoch == 0 or result.activation == 0:
    fail("invalid shell activation")

proc accept*(
    model: var ShellModel, activation: ShellActivation
): ShellActivationDisposition =
  let exact =
    activation.connectionEpoch == model.connectionEpoch and
    activation.candidateGeneration == model.presentedGeneration and
    activation.presentationEpoch == model.presentationEpoch and
    activation.activation > model.lastActivation and
    model.order.anyIt(
      it.slot == activation.action.targetSlot and
        it.generation == activation.action.targetGeneration
    )
  if not exact:
    return ShellActivationDisposition.rejectedStale
  model.lastActivation = activation.activation
  ShellActivationDisposition.consumed

proc activationAckFrame*(
    connectionEpoch, activation, transaction: uint64,
    disposition: ShellActivationDisposition,
): ShellFrame =
  result.kind = ShellMessageKind.activationAck
  result.transaction = transaction
  result.payload.addU64(connectionEpoch)
  result.payload.addU64(activation)
  result.payload.addU16(uint16(ord(disposition)))
  result.payload.addU16(0)

proc rememberPresented*(model: var ShellModel, outcome: ShellCandidateOutcome) =
  if outcome.connectionEpoch != model.connectionEpoch or
      outcome.kind != ShellCandidateOutcomeKind.presented:
    fail("shell presentation outcome is not current")
  model.presentedGeneration = outcome.candidateGeneration
  model.presentationEpoch = outcome.presentationEpoch
