import std/[strutils, unittest]
import types/[handoff, session, wm_file_bodies, wm_files, wm_presentation, wm_v1]
import sophia/[policy_codec, policy_transport, wm_file_bodies, wm_files]

## Records below are assembled field by field from `sophia-wm-files-v1.kdl`
## (Sophia 4ebfd0b8 controls, 14cab2ed admission) with a local little-endian
## builder; none comes from a Sophia encoder or from the codec under test.

const
  epoch = 7'u64
  allCaps = high(uint64)
  maxIndex = high(uint32)

proc hex(text: string): seq[byte] =
  for value in text.splitWhitespace():
    result.add(byte(parseHexInt(value)))

template refuses(expected: WmFileErrorKind, body: untyped) =
  var raised = false
  try:
    body
  except WmFileError as error:
    raised = true
    check error.kind == expected
  check raised

type Le = object
  bytes: seq[byte]

proc u16(le: var Le, value: uint16): var Le {.discardable.} =
  for index in 0 ..< 2:
    le.bytes.add(byte((value shr (index * 8)) and 0xff))
  le

proc u32(le: var Le, value: uint32): var Le {.discardable.} =
  for index in 0 ..< 4:
    le.bytes.add(byte((value shr (index * 8)) and 0xff))
  le

proc u64(le: var Le, value: uint64): var Le {.discardable.} =
  for index in 0 ..< 8:
    le.bytes.add(byte((value shr (index * 8)) and 0xff))
  le

proc i32(le: var Le, value: int32): var Le {.discardable.} =
  le.u32(cast[uint32](value))

proc zeros(le: var Le, count: int): var Le {.discardable.} =
  for _ in 0 ..< count:
    le.bytes.add(0)
  le

proc record(
    kind: uint16,
    body: seq[byte],
    submission = 0'u64,
    sequence = 0'u64,
    recordEpoch = epoch,
): seq[byte] =
  var le: Le
  le.u32(uint32(32 + body.len)).u16(1).u16(kind).u64(recordEpoch).u64(submission).u64(
    sequence
  )
  le.bytes & body

proc event(kind: uint16, body: seq[byte]): seq[byte] =
  record(kind, body, sequence = 3)

proc candidate(kind: uint16, body: seq[byte]): seq[byte] =
  record(kind, body, submission = 9)

proc eventHeader(kind: WmFileKind): WmFileHeader =
  WmFileHeader(kind: kind, connectionEpoch: epoch, sequence: 3)

proc candidateHeader(kind: WmFileKind): WmFileHeader =
  WmFileHeader(kind: kind, connectionEpoch: epoch, submissionId: 9)

proc patch16(bytes: seq[byte], offset: int, value: uint16): seq[byte] =
  result = bytes
  result[offset] = byte(value and 0xff)
  result[offset + 1] = byte(value shr 8)

proc patch32(bytes: seq[byte], offset: int, value: uint32): seq[byte] =
  result = bytes
  for index in 0 ..< 4:
    result[offset + index] = byte((value shr (index * 8)) and 0xff)

proc patch64(bytes: seq[byte], offset: int, value: uint64): seq[byte] =
  result = bytes
  for index in 0 ..< 8:
    result[offset + index] = byte((value shr (index * 8)) and 0xff)

const b = wmFileHeaderBytes

proc limitsBody(ceiling: uint64, profileRequired: uint16): seq[byte] =
  var le: Le
  le.u64(ceiling).u32(1_048_576).u32(1_048_576).u16(64).u16(32).u32(12_000).u32(4_000)
  le.u16(profileRequired).u16(0)
  le.bytes

proc digest(): array[profileDigestLen, byte] =
  for index in 0 ..< profileDigestLen:
    result[index] = byte(0x11 + index)

proc profileBody(
    transaction, generation: uint64, outcome = 0'u16, completion = false
): seq[byte] =
  var le: Le
  le.u64(transaction).u64(generation)
  le.bytes.add(digest())
  if completion:
    le.u16(outcome).zeros(6)
  le.bytes

proc cycleBody(
    cause: uint16, outputs: openArray[uint64], causeBytes: seq[byte]
): seq[byte] =
  var le: Le
  le.u64(41).u64(42).u64(43).u64(44).u64(45).u16(cause).u16(uint16(outputs.len)).u32(0)
  for output in outputs:
    le.u64(output)
  le.bytes & causeBytes

proc surface(index, generation: uint32): seq[byte] =
  var le: Le
  le.u32(index).u32(generation)
  le.bytes

suite "WM file admission bodies":
  test "Limits matches its layout and admits only API-1 values":
    # Ceiling bindings|profile activation (0x201), profile required.
    let bytes = record(1, limitsBody(0x201, 1))
    check bytes ==
      hex(
        "40 00 00 00 01 00 01 00 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 " &
          "00 00 00 00 00 00 00 00 01 02 00 00 00 00 00 00 00 00 10 00 00 00 10 00 " &
          "40 00 20 00 e0 2e 00 00 a0 0f 00 00 01 00 00 00"
      )
    let limits = bytes.decodeLimits(epoch)
    check limits == WmFileLimits(capabilityCeiling: 0x201, profileRequired: true)
    check WmFileHeader(kind: WmFileKind.limits, connectionEpoch: epoch).encodeLimits(
      limits
    ) == bytes
    for (offset, value) in [
      (b + 8, 1'u32), (b + 12, 0'u32), (b + 20, 11_999'u32), (b + 24, 4_001'u32)
    ]:
      refuses WmFileErrorKind.value:
        discard bytes.patch32(offset, value).decodeLimits(epoch)
    for (offset, value) in [(b + 16, 63'u16), (b + 18, 33'u16), (b + 28, 2'u16)]:
      refuses WmFileErrorKind.value:
        discard bytes.patch16(offset, value).decodeLimits(epoch)
    refuses WmFileErrorKind.reserved:
      discard bytes.patch16(b + 30, 1).decodeLimits(epoch)
    refuses WmFileErrorKind.capability:
      discard record(1, limitsBody(0x1, 1)).decodeLimits(epoch)
    refuses WmFileErrorKind.capability:
      discard WmFileHeader(kind: WmFileKind.limits, connectionEpoch: epoch).encodeLimits(
        WmFileLimits(capabilityCeiling: 1, profileRequired: true)
      )
    refuses WmFileErrorKind.epoch:
      discard bytes.decodeLimits(8)
    refuses WmFileErrorKind.epoch:
      discard bytes.decodeLimits(0)

  test "Negotiate keeps required and optional disjoint; Negotiated is a selection":
    var le: Le
    le.u64(0x3).u64(0x200)
    let offer = candidate(256, le.bytes)
    check offer.decodeNegotiate(epoch) ==
      WmFileNegotiationOffer(required: 3, optional: 0x200)
    check candidateHeader(WmFileKind.negotiate).encodeNegotiate(
      WmFileNegotiationOffer(required: 3, optional: 0x200)
    ) == offer
    refuses WmFileErrorKind.value:
      discard offer.patch64(b + 8, 0x2).decodeNegotiate(epoch)
    refuses WmFileErrorKind.value:
      discard candidateHeader(WmFileKind.negotiate).encodeNegotiate(
          WmFileNegotiationOffer(required: 3, optional: 1)
        )
    var selected: Le
    selected.u64(0x203)
    let negotiated = event(16, selected.bytes)
    check negotiated.decodeNegotiated(epoch) == 0x203
    check eventHeader(WmFileKind.negotiated).encodeNegotiated(0x203) == negotiated
    refuses WmFileErrorKind.class:
      discard offer.decodeNegotiated(epoch)

  test "profile stages map to the handoff kinds and keep the exact identity":
    check commandFileKind(ProfileHandoffMsgKind.prepare) == WmFileKind.profilePrepare
    check commandFileKind(ProfileHandoffMsgKind.activate) == WmFileKind.profileActivate
    check commandFileKind(ProfileHandoffMsgKind.rollback) == WmFileKind.profileRollback
    check completionFileKind(ProfileHandoffMsgKind.prepare) == WmFileKind.profilePrepared
    check completionFileKind(ProfileHandoffMsgKind.activate) == WmFileKind.profileActive
    check completionFileKind(ProfileHandoffMsgKind.rollback) ==
      WmFileKind.profileRolledBack
    let identity = ProfileIdentity(
      connectionEpoch: epoch, profileGeneration: 6, profileDigest: digest()
    )
    let command = event(18, profileBody(5, 6))
    check command.decodeProfileCommand(ProfileHandoffMsgKind.prepare, epoch, allCaps) ==
      ProfileCommand(transaction: 5, identity: identity)
    check eventHeader(WmFileKind.profilePrepare).encodeProfileCommand(
      ProfileCommand(transaction: 5, identity: identity), allCaps
    ) == command
    refuses WmFileErrorKind.kind:
      discard
        command.decodeProfileCommand(ProfileHandoffMsgKind.activate, epoch, allCaps)
    refuses WmFileErrorKind.capability:
      discard command.decodeProfileCommand(
        ProfileHandoffMsgKind.prepare, epoch, allCaps xor capabilityProfileActivation
      )
    for offset in [b, b + 8]:
      refuses WmFileErrorKind.identity:
        discard command.patch64(offset, 0).decodeProfileCommand(
            ProfileHandoffMsgKind.prepare, epoch, allCaps
          )
    var nullDigest = command
    for index in b + 16 ..< b + 48:
      nullDigest[index] = 0
    refuses WmFileErrorKind.identity:
      discard
        nullDigest.decodeProfileCommand(ProfileHandoffMsgKind.prepare, epoch, allCaps)
    let completion = candidate(258, profileBody(5, 6, 1, completion = true))
    check completion.decodeProfileCompletion(
      ProfileHandoffMsgKind.activate, epoch, allCaps
    ) ==
      ProfileCompletion(
        transaction: 5, identity: identity, outcome: ProfileOutcomeKind.accepted
      )
    check candidateHeader(WmFileKind.profileActive).encodeProfileCompletion(
      ProfileCompletion(
        transaction: 5, identity: identity, outcome: ProfileOutcomeKind.accepted
      ),
      allCaps,
    ) == completion
    for code in [0'u16, 4]:
      refuses WmFileErrorKind.value:
        discard completion.patch16(b + 48, code).decodeProfileCompletion(
            ProfileHandoffMsgKind.activate, epoch, allCaps
          )
    refuses WmFileErrorKind.reserved:
      discard completion.patch16(b + 54, 1).decodeProfileCompletion(
          ProfileHandoffMsgKind.activate, epoch, allCaps
        )
    refuses WmFileErrorKind.kind:
      discard eventHeader(WmFileKind.profilePrepare).encodeProfileCompletion(
          ProfileCompletion(transaction: 5, identity: identity), allCaps
        )

suite "WM file control bodies":
  test "Dirty carries one to sixteen distinct outputs under its capability":
    var le: Le
    le.u64(12).u16(2).zeros(6).u64(1).u64(2)
    let bytes = candidate(261, le.bytes)
    check bytes.decodeDirty(epoch, allCaps) ==
      WmFileDirty(policyGeneration: 12, affectedOutputs: @[1'u64, 2])
    check candidateHeader(WmFileKind.dirty).encodeDirty(
      WmFileDirty(policyGeneration: 12, affectedOutputs: @[1'u64, 2]), allCaps
    ) == bytes
    refuses WmFileErrorKind.capability:
      discard bytes.decodeDirty(epoch, allCaps xor capabilityPolicyDirty)
    for count in [0'u16, 17]:
      refuses WmFileErrorKind.value:
        discard bytes.patch16(b + 8, count).decodeDirty(epoch, allCaps)
    refuses WmFileErrorKind.length:
      discard bytes.patch16(b + 8, 1).decodeDirty(epoch, allCaps)
    refuses WmFileErrorKind.value:
      discard bytes.patch64(b + 24, 1).decodeDirty(epoch, allCaps)
    refuses WmFileErrorKind.value:
      discard bytes.patch64(b + 16, 0).decodeDirty(epoch, allCaps)
    refuses WmFileErrorKind.reserved:
      discard bytes.patch16(b + 12, 1).decodeDirty(epoch, allCaps)
    refuses WmFileErrorKind.identity:
      discard bytes.patch64(b, 0).decodeDirty(epoch, allCaps)

  test "SessionOperation targets are strict file surfaces":
    for (index, generation) in [(0'u32, 0'u32), (0'u32, 5'u32), (4'u32, 2'u32)]:
      var le: Le
      le.u64(21).u64(22).u64(23)
      le.bytes.add(surface(index, generation))
      let bytes = candidate(263, le.bytes)
      let value = bytes.decodeSessionOperation(epoch, allCaps)
      check value.intent.targetIndex == index
      check value.intent.targetGeneration == generation
      check candidateHeader(WmFileKind.sessionOperation).encodeSessionOperation(
        value, allCaps
      ) == bytes
    var le: Le
    le.u64(21).u64(22).u64(23)
    le.bytes.add(surface(4, 2))
    let bytes = candidate(263, le.bytes)
    refuses WmFileErrorKind.value:
      discard bytes.patch32(b + 24, maxIndex).decodeSessionOperation(epoch, allCaps)
    refuses WmFileErrorKind.value:
      discard bytes.patch32(b + 28, 0).decodeSessionOperation(epoch, allCaps)
    refuses WmFileErrorKind.identity:
      discard bytes.patch64(b + 16, 0).decodeSessionOperation(epoch, allCaps)
    refuses WmFileErrorKind.capability:
      discard
        bytes.decodeSessionOperation(epoch, allCaps xor capabilitySessionOperations)

  test "outcome events keep their correlation and only their own codes":
    var configuration: Le
    configuration.u64(31).u64(32).u16(2).zeros(6)
    let configurationBytes = event(21, configuration.bytes)
    check configurationBytes.decodeConfigurationOutcome(epoch, allCaps) ==
      WmFileConfigurationOutcome(
        transaction: 31, generation: 32, kind: ProjectionOutcomeKind.rejectedStale
      )
    for code in [0'u16, 6]:
      refuses WmFileErrorKind.value:
        discard configurationBytes.patch16(b + 16, code).decodeConfigurationOutcome(
            epoch, allCaps
          )
    refuses WmFileErrorKind.capability:
      discard configurationBytes.decodeConfigurationOutcome(
        epoch, allCaps xor capabilityConfiguration
      )
    var projection: Le
    projection.u64(33).u64(34).u64(35).u16(1).u16(1).u32(0)
    let projectionBytes = event(23, projection.bytes)
    let decoded = projectionBytes.decodeProjectionOutcome(epoch, allCaps)
    check decoded.outcome ==
      ProjectionOutcome(
        transaction: 33,
        connectionEpoch: epoch,
        requestId: 34,
        sceneGeneration: 35,
        kind: ProjectionOutcomeKind.committed,
      )
    check decoded.expectSessionOperation
    check eventHeader(WmFileKind.projectionOutcome).encodeProjectionOutcome(
      decoded, allCaps
    ) == projectionBytes
    refuses WmFileErrorKind.value:
      discard projectionBytes.patch16(b + 26, 2).decodeProjectionOutcome(epoch, allCaps)
    refuses WmFileErrorKind.capability:
      discard projectionBytes.decodeProjectionOutcome(
        epoch, allCaps xor capabilitySessionOperations
      )
    check projectionBytes
      .patch16(b + 26, 0)
      .decodeProjectionOutcome(epoch, 0).outcome.kind == ProjectionOutcomeKind.committed
    var operation: Le
    operation.u64(36).u64(37).u16(4).zeros(6)
    check event(24, operation.bytes).decodeSessionOperationOutcome(epoch, allCaps) ==
      WmFileSessionOperationOutcome(
        transaction: 36, requestId: 37, kind: ProjectionOutcomeKind.timedOut
      )

  test "receipts and Submitted keep their identities and roles":
    var receipt: Le
    receipt.u64(51).u64(52).u64(2).u64(53).u64(54).u16(2).zeros(6)
    let receiptBytes = event(25, receipt.bytes)
    let value = receiptBytes.decodePresentationReceipt(epoch, allCaps)
    check value.receipt ==
      PresentationReceipt(
        connectionEpoch: epoch,
        publicationGeneration: 52,
        output: 2,
        outputGeneration: 53,
        presentationEpoch: 54,
        outcome: PresentationOutcomeKind.revoked,
      )
    check eventHeader(WmFileKind.presentationReceipt).encodePresentationReceipt(
      value, allCaps
    ) == receiptBytes
    refuses WmFileErrorKind.value:
      discard receiptBytes.patch16(b + 40, 4).decodePresentationReceipt(epoch, allCaps)
    refuses WmFileErrorKind.identity:
      discard receiptBytes.patch64(b + 32, 0).decodePresentationReceipt(epoch, allCaps)
    var submitted: Le
    submitted.u64(9).u16(261).zeros(6)
    let submittedBytes = event(17, submitted.bytes)
    check submittedBytes.decodeSubmitted(epoch) ==
      WmFileSubmitted(acceptedSubmissionId: 9, candidateKind: WmFileKind.dirty)
    refuses WmFileErrorKind.class:
      discard submittedBytes.patch16(b + 8, 22).decodeSubmitted(epoch)
    refuses WmFileErrorKind.kind:
      discard submittedBytes.patch16(b + 8, 999).decodeSubmitted(epoch)
    refuses WmFileErrorKind.identity:
      discard submittedBytes.patch64(b, 0).decodeSubmitted(epoch)

suite "WM file cycle bodies":
  test "file cause codes are explicit: PointerFocus is 3 and Interaction 4":
    var pointer: Le
    pointer.u64(2)
    pointer.bytes.add(surface(0, 0))
    let pointerCycle = event(22, cycleBody(3, [1'u64, 2], pointer.bytes))
    check pointerCycle.decodeCycle(epoch, allCaps).request.cause.kind ==
      ProjectionCauseKind.pointerFocus
    var interaction: Le
    interaction.u16(3).u16(4).u16(2).u16(0)
    interaction.bytes.add(surface(0, 1))
    interaction.i32(0).i32(-5).i32(0).i32(0)
    let interactionCycle = event(22, cycleBody(4, [1'u64], interaction.bytes))
    let decoded = interactionCycle.decodeCycle(epoch, allCaps).request.cause
    check decoded.kind == ProjectionCauseKind.interaction
    check decoded.interactionPhase == InteractionPhase.finish
    check decoded.interactionKind == InteractionKind.scroll
    check decoded.interactionAxis == InteractionAxis.vertical
    check decoded.y == -5
    refuses WmFileErrorKind.value:
      discard interactionCycle.patch16(b + 40, 7).decodeCycle(epoch, allCaps)
    refuses WmFileErrorKind.value:
      discard interactionCycle.patch16(b + 56, 0).decodeCycle(epoch, allCaps)

  test "every cause round trips with its exact body size":
    var causes: seq[(uint16, seq[byte])]
    causes.add((0'u16, newSeq[byte]()))
    var action: Le
    action.u64(61).u64(62)
    causes.add((1'u16, action.bytes))
    causes.add((2'u16, surface(0, 1)))
    var pointer: Le
    pointer.u64(1)
    causes.add((3'u16, pointer.bytes & surface(8, 3)))
    var interaction: Le
    interaction.u16(1).u16(1).u16(0).u16(0)
    var geometry: Le
    geometry.i32(-4).i32(5).i32(640).i32(480)
    causes.add((4'u16, interaction.bytes & surface(8, 3) & geometry.bytes))
    var output: Le
    output.u64(61).u64(62).u64(2).u64(63)
    causes.add((5'u16, output.bytes))
    var presentation: Le
    presentation.u64(61).u64(62).u64(64).u64(2).u64(65).u64(66).u64(0).u64(0)
    causes.add((6'u16, presentation.bytes))
    for (code, causeBytes) in causes:
      let bytes = event(22, cycleBody(code, [1'u64, 2], causeBytes))
      let cycle = bytes.decodeCycle(epoch, allCaps)
      check cycle.snapshotTransaction == 41
      check cycle.requestTransaction == 42
      check cycle.request.connectionEpoch == epoch
      check cycle.request.affectedOutputs == @[1'u64, 2]
      check eventHeader(WmFileKind.cycle).encodeCycle(cycle, allCaps) == bytes
      var longer = bytes
      longer.add(0)
      longer = longer.patch32(0, uint32(longer.len))
      refuses WmFileErrorKind.length:
        discard longer.decodeCycle(epoch, allCaps)

  test "file surfaces accept index zero and refuse the all-ones index":
    let focusZero = event(22, cycleBody(2, [1'u64], surface(0, 1)))
    check focusZero.decodeCycle(epoch, allCaps).request.cause.targetIndex == 0
    refuses WmFileErrorKind.value:
      discard event(22, cycleBody(2, [1'u64], surface(maxIndex, 1))).decodeCycle(
          epoch, allCaps
        )
    refuses WmFileErrorKind.value:
      discard
        event(22, cycleBody(2, [1'u64], surface(3, 0))).decodeCycle(epoch, allCaps)

  test "each cause needs its own capabilities; coverage and identity are strict":
    var action: Le
    action.u64(61).u64(62)
    let actionCycle = event(22, cycleBody(1, [1'u64], action.bytes))
    refuses WmFileErrorKind.capability:
      discard actionCycle.decodeCycle(epoch, allCaps xor capabilityActions)
    var output: Le
    output.u64(61).u64(62).u64(3).u64(63)
    refuses WmFileErrorKind.value:
      discard
        event(22, cycleBody(5, [1'u64, 2], output.bytes)).decodeCycle(epoch, allCaps)
    let outputCycle = event(22, cycleBody(5, [3'u64], output.bytes))
    refuses WmFileErrorKind.capability:
      discard outputCycle.decodeCycle(epoch, allCaps xor capabilityOutputActions)
    refuses WmFileErrorKind.capability:
      discard outputCycle.decodeCycle(epoch, allCaps xor capabilityActions)
    refuses WmFileErrorKind.value:
      discard
        event(22, cycleBody(0, [1'u64, 1], newSeq[byte]())).decodeCycle(epoch, allCaps)
    refuses WmFileErrorKind.value:
      discard event(22, cycleBody(0, newSeq[uint64](), newSeq[byte]())).decodeCycle(
          epoch, allCaps
        )
    refuses WmFileErrorKind.identity:
      discard actionCycle.patch64(b + 16, 0).decodeCycle(epoch, allCaps)
    refuses WmFileErrorKind.reserved:
      discard actionCycle.patch16(b + 46, 1).decodeCycle(epoch, allCaps)
    refuses WmFileErrorKind.epoch:
      discard actionCycle.decodeCycle(8, allCaps)

  test "shared payload and identity rules hold on the file path too":
    # A scroll needs a delta unless it is cancelled.
    var scroll: Le
    scroll.u16(2).u16(4).u16(1).u16(0)
    scroll.bytes.add(surface(4, 1))
    scroll.i32(0).i32(0).i32(0).i32(0)
    refuses WmFileErrorKind.value:
      discard event(22, cycleBody(4, [1'u64], scroll.bytes)).decodeCycle(epoch, allCaps)
    # A presentation target is both halves or neither.
    var presentation: Le
    presentation.u64(61).u64(62).u64(64).u64(1).u64(65).u64(66).u64(7).u64(0)
    refuses WmFileErrorKind.value:
      discard
        event(22, cycleBody(6, [1'u64], presentation.bytes)).decodeCycle(epoch, allCaps)
    # Every outcome code 1..5, Disconnected included, in each outcome body.
    for (code, kind) in [
      (1'u16, ProjectionOutcomeKind.committed),
      (2'u16, ProjectionOutcomeKind.rejectedStale),
      (3'u16, ProjectionOutcomeKind.rejectedInvalid),
      (4'u16, ProjectionOutcomeKind.timedOut),
      (5'u16, ProjectionOutcomeKind.disconnected),
    ]:
      var configuration: Le
      configuration.u64(31).u64(32).u16(code).zeros(6)
      check event(21, configuration.bytes)
        .decodeConfigurationOutcome(epoch, allCaps).kind == kind
      var projection: Le
      projection.u64(33).u64(34).u64(35).u16(code).u16(0).u32(0)
      check event(23, projection.bytes)
        .decodeProjectionOutcome(epoch, allCaps).outcome.kind == kind
      var operation: Le
      operation.u64(36).u64(37).u16(code).zeros(6)
      check event(24, operation.bytes)
        .decodeSessionOperationOutcome(epoch, allCaps).kind == kind

  test "the encoder refuses a value the file cannot carry":
    var cycle =
      event(22, cycleBody(2, [1'u64], surface(0, 1))).decodeCycle(epoch, allCaps)
    cycle.request.cause.activationSerial = 5
    refuses WmFileErrorKind.value:
      discard eventHeader(WmFileKind.cycle).encodeCycle(cycle, allCaps)
    cycle.request.cause.activationSerial = 0
    cycle.request.connectionEpoch = 8
    refuses WmFileErrorKind.epoch:
      discard eventHeader(WmFileKind.cycle).encodeCycle(cycle, allCaps)

suite "legacy acceptance preserved beside strict file bodies":
  test "the legacy scalar decoder still refuses a Focus target at index zero":
    # Legacy layout: epoch, request, scene, policy, cause 2 (Focus), no
    # interaction, target (0, 1), one output.
    var le: Le
    le.u64(epoch).u64(43).u64(44).u64(45).u16(2).u16(0).u16(0).u16(0).u64(0).u64(0)
    le.u32(0).u32(1).i32(0).i32(0).i32(0).i32(0).u16(1).u16(0).u64(1)
    let frame =
      Frame(kind: MessageKind.projectionRequest, transaction: 1, payload: le.bytes)
    expect PolicyClientError:
      discard frame.decodeProjectionRequest(epoch, allCaps)
    check event(22, cycleBody(2, [1'u64], surface(0, 1)))
      .decodeCycle(epoch, allCaps).request.cause.targetGeneration == 1
