import std/[monotimes, net, posix, sequtils, strutils, times, unittest]

import types/[config_values, session, wm_file_bodies, wm_files, wm_presentation, wm_v1]
import sophia/[policy_loop, policy_wire, wm_file_bodies, wm_file_wire, wm_files]
import support/wm_file_transcript

## Flow and refusal evidence for Hagia's file wire against a scripted 9P peer.
## The peer holds no journal, permit or admission state, so nothing here is
## conformance: the real Sophia peer remains the acceptance evidence.

const
  epoch = 9'u64
  everyBit = (1'u64 shl 20) - 1
  base =
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement
  configured =
    capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
    capabilitySessionOperations
  extras =
    capabilityTabGroups or capabilityTranslationGroups or capabilityOutputActions or
    capabilityOutputPolicyKeys or capabilityLaunchOrigin or capabilityOutputLaunchContext or
    capabilitySurfaceInstances or capabilityPresentationActions

peerResults.open()

proc event(kind: WmFileKind, sequence: uint64, at = epoch): WmFileHeader =
  WmFileHeader(kind: kind, connectionEpoch: at, sequence: sequence)

proc apiObject(): seq[byte] =
  for character in "sophia-wm-files version=1 output_transport=current_ipc\n":
    result.add(byte(character))

proc limitsObject(ceiling: uint64, profileRequired: bool): seq[byte] =
  WmFileHeader(kind: WmFileKind.limits, connectionEpoch: epoch).encodeLimits(
    WmFileLimits(capabilityCeiling: ceiling, profileRequired: profileRequired)
  )

proc submitted(id: uint64, kind: WmFileKind, sequence: uint64): seq[byte] =
  event(WmFileKind.submitted, sequence).encodeSubmitted(
    WmFileSubmitted(acceptedSubmissionId: id, candidateKind: kind)
  )

proc receipt(sequence: uint64): seq[byte] =
  event(WmFileKind.presentationReceipt, sequence).encodePresentationReceipt(
    WmFilePresentationReceipt(
      transaction: 102,
      receipt: PresentationReceipt(
        connectionEpoch: epoch,
        publicationGeneration: 1,
        output: 7,
        outputGeneration: 1,
        presentationEpoch: 1,
        outcome: PresentationOutcomeKind.presented,
      ),
    ),
    everyBit,
  )

proc cycle(sequence: uint64, at = epoch): seq[byte] =
  event(WmFileKind.cycle, sequence, at).encodeCycle(
    WmFileCycle(
      snapshotTransaction: 13,
      requestTransaction: 14,
      request: ProjectionRequest(
        connectionEpoch: at,
        requestId: 55,
        sceneGeneration: 19,
        policyGeneration: 1,
        affectedOutputs: @[7'u64],
        cause: ProjectionCause(kind: ProjectionCauseKind.sceneChanged),
      ),
    ),
    everyBit,
  )

proc snapshotObject(transaction = 13'u64): seq[byte] =
  ## Rows from the published layout; Hagia has no snapshot encoder.
  var output: seq[byte]
  output.addU64(7)
  output.addU64(1)
  output.addU32(0)
  output.addU32(1)
  for value in [0'i32, 0, 640, 480, 0, 0, 640, 480]:
    output.addI32(value)
  var surface: seq[byte]
  surface.addU32(0)
  surface.addU32(1)
  surface.addU64(1)
  surface.addU64(7)
  for value in [surfaceFocusable, 1'u16, 0, 0]:
    surface.addU16(value)
  surface.addU32(0)
  surface.addU32(0)
  for value in [0'i32, 0, 320, 240, 0, 0, 0, 0, 0, 0]:
    surface.addI32(value)
  let rows = @[
    WmFileSection(kind: 1, count: 1, rows: output),
    WmFileSection(kind: 2, count: 1, rows: surface),
  ]
  var body: seq[byte]
  body.addU64(transaction)
  body.addU64(19)
  body.addU64(7)
  body.addU16(uint16(rows.len))
  body.add(newSeq[byte](6))
  body.add(rows.encodeSections())
  WmFileHeader(kind: WmFileKind.snapshot, connectionEpoch: epoch).encodeRecord(body)

proc discoverySteps(ceiling: uint64, profileRequired = false): seq[PeerStep] =
  @[versionStep(), attachStep()] & objectSteps(apiObject(), 10) &
    objectSteps(limitsObject(ceiling, profileRequired), 11) &
    @[
      walkStep(20),
      openStep(3, 20),
      walkStep(21),
      openStep(4, 21),
      walkStep(22),
      openStep(5, 22),
    ]

proc stagingSteps(): seq[PeerStep] =
  @[walkStep(30), openStep(6, 30), writeStep(6)]

proc admissionSteps(
    ceiling, selected: uint64, profileRequired = false, after: seq[PeerEvent] = @[]
): seq[PeerStep] =
  ## Discovery, the Negotiate candidate and its custody, then Negotiated. The
  ## final acknowledgement releases `after`.
  discoverySteps(ceiling, profileRequired) & stagingSteps() &
    @[
      writeStep(
        4,
        released(
          submitted(1, WmFileKind.negotiate, 1),
          event(WmFileKind.negotiated, 2).encodeNegotiated(selected),
        ),
      ),
      writeStep(5),
      clunkStep(6),
      writeStep(5, after),
    ]

proc run(steps: seq[PeerStep], body: proc(socket: Socket)): PeerLog =
  var handles: array[0 .. 1, cint]
  doAssert posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, handles) == 0
  let socket =
    newSocket(SocketHandle(handles[0]), net.AF_UNIX, net.SOCK_STREAM, net.IPPROTO_IP)
  var thread: Thread[PeerScript]
  createThread(thread, serve, PeerScript(fd: handles[1], steps: steps))
  try:
    body(socket)
  finally:
    joinThread(thread)
  peerResults.recv()

proc raisedMessage(body: proc()): string =
  try:
    body()
  except CatchableError as error:
    return error.msg
  "no error"

proc writes(log: PeerLog, fid: uint32): seq[Seen] =
  log.seen.filterIt(it.kind == twrite and it.fid == fid)

proc acks(log: PeerLog): seq[uint64] =
  log.writes(5).mapIt(it.data.decodeAck().sequence)

proc submits(log: PeerLog): int =
  log.writes(4).len

let selectedAll = base or configured or extras

suite "Hagia file wire flow against a scripted peer":
  test "admission offers exactly the implemented vocabulary and adopts the selection":
    let steps = admissionSteps(everyBit, selectedAll)
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire()
        check wire.connectionEpoch == epoch
        check wire.capabilities == selectedAll
        wire.close()
    )
    check log.failure == ""
    check log.stepsDone == steps.len
    let staged = log.writes(6)
    require staged.len == 1
    let offer = staged[0].data.decodeNegotiate(epoch)
    check offer.required == (base or configured)
    check offer.optional == extras
    check log.writes(4)[0].data.decodeSubmit().candidateBytes ==
      uint32(staged[0].data.len)
    check log.acks() == @[1'u64, 2]

  test "requested focus, activation and assignments become required":
    let required =
      base or configured or capabilityPointerFocus or capabilityProfileActivation or
      capabilityOutputActions or capabilityOutputPolicyKeys
    let steps = admissionSteps(everyBit, required or extras, profileRequired = true)
    let log = steps.run(
      proc(socket: Socket) =
        socket.fileWire(true, true, true).close()
    )
    check log.failure == ""
    let offer = log.writes(6)[0].data.decodeNegotiate(epoch)
    check offer.required == required
    check offer.optional == (extras and not required)

  test "a selection outside the offer or the ceiling is refused and closes":
    let ceiling = everyBit and not capabilityTabGroups
    let steps = admissionSteps(ceiling, selectedAll)
    let log = steps.run(
      proc(socket: Socket) =
        check raisedMessage(
          proc() =
            discard socket.fileWire()
        ) == "Sophia selected capabilities outside Hagia's offer or its ceiling"
    )
    check log.failure == ""
    check log.stepsDone == steps.len - 1
    check log.acks() == @[1'u64]

  test "admission refuses before any candidate what the ceiling cannot hold":
    for (ceiling, profileRequired, message) in [
      (everyBit, true, "Sophia requires desktop profile activation"),
      (
        everyBit and not capabilityConfiguration,
        false,
        "Sophia omitted native policy configuration",
      ),
    ]:
      let steps = discoverySteps(ceiling, profileRequired)
      let log = steps.run(
        proc(socket: Socket) =
          check raisedMessage(
            proc() =
              discard socket.fileWire()
          ) == message
      )
      check log.failure == ""
      check log.stepsDone == steps.len
      check log.writes(6).len == 0

  test "the activated loop runs profile, configuration and one cycle over files":
    let selected = selectedAll or capabilityProfileActivation
    var identity = ProfileIdentity(connectionEpoch: epoch, profileGeneration: 3)
    for index in 0 ..< profileDigestLen:
      identity.profileDigest[index] = 0x07
    proc command(kind: WmFileKind, transaction, sequence: uint64): seq[byte] =
      event(kind, sequence).encodeProfileCommand(
        ProfileCommand(transaction: transaction, identity: identity), selected
      )

    let outcome = event(WmFileKind.projectionOutcome, 12).encodeProjectionOutcome(
        WmFileProjectionOutcome(
          outcome: ProjectionOutcome(
            transaction: 2,
            connectionEpoch: epoch,
            requestId: 55,
            sceneGeneration: 20,
            kind: ProjectionOutcomeKind.disconnected,
          ),
          expectSessionOperation: false,
        ),
        selected,
      )
    let configured = event(WmFileKind.configurationOutcome, 9)
      .encodeConfigurationOutcome(
        WmFileConfigurationOutcome(
          transaction: 1, generation: 1, kind: ProjectionOutcomeKind.committed
        ),
        selected,
      )
    let steps =
      admissionSteps(
        everyBit,
        selected,
        profileRequired = true,
        after = released(receipt(3), command(WmFileKind.profilePrepare, 40, 4)),
      ) & @[writeStep(5), writeStep(5)] & stagingSteps() &
      @[
        writeStep(
          4,
          released(
            submitted(2, WmFileKind.profilePrepared, 5),
            command(WmFileKind.profileActivate, 41, 6),
          ),
        ),
        writeStep(5),
        clunkStep(6),
        writeStep(5),
      ] & stagingSteps() &
      @[
        writeStep(4, released(submitted(3, WmFileKind.profileActive, 7))),
        writeStep(5),
        clunkStep(6),
      ] & stagingSteps() &
      @[
        writeStep(
          4, released(submitted(4, WmFileKind.configuration, 8), configured, cycle(10))
        ),
        writeStep(5),
        clunkStep(6),
        writeStep(5),
      ] & objectSteps(snapshotObject(), 40) & @[writeStep(5)] & stagingSteps() &
      @[
        writeStep(4, released(submitted(5, WmFileKind.projection, 11), outcome)),
        writeStep(5),
        clunkStep(6),
        writeStep(5),
      ]
    let candidate = AuthorityCandidate(
      authority: ProfileAuthority.policy, generation: 3, digest: repeat("07", 32)
    )
    let log = steps.run(
      proc(socket: Socket) =
        socket.fileWire(requestProfileActivation = true).runActivatedPolicy(candidate)
    )
    check log.failure == ""
    check log.stepsDone == steps.len
    check log.acks() == toSeq(1'u64 .. 12'u64)
    let staged = log.writes(6)
    require staged.len == 5
    check staged.mapIt(it.data.readU16(6)) ==
      @[
        uint16(WmFileKind.negotiate),
        uint16(WmFileKind.profilePrepared),
        uint16(WmFileKind.profileActive),
        uint16(WmFileKind.configuration),
        uint16(WmFileKind.projection),
      ]
    check staged.mapIt(it.data.readU64(16)) == @[1'u64, 2, 3, 4, 5]

  test "a refused submit drains receipts, then retries the same bytes":
    let accepted = released(submitted(2, WmFileKind.dirty, 5))
    let steps =
      admissionSteps(everyBit, selectedAll) & stagingSteps() &
      @[
        writeStep(4, released(receipt(3)), refusal = 11),
        writeStep(5),
        writeStep(4, released(receipt(4)), refusal = 11),
        writeStep(5),
        writeStep(4, accepted),
        writeStep(5),
        clunkStep(6),
      ]
    var receipts: seq[PresentationReceipt]
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire()
        wire.requestDirty(PolicyDirty(policyGeneration: 2, affectedOutputs: @[7'u64]))
        receipts = wire.takeReceipts()
        wire.close()
    )
    check log.failure == ""
    check log.stepsDone == steps.len
    check receipts.len == 2
    check log.acks() == @[1'u64, 2, 3, 4, 5]
    let tries = log.writes(4)[1 .. ^1]
    check tries.len == 3
    check tries.allIt(it.data == tries[0].data)
    check log.writes(6)[1].data.decodeDirty(epoch, selectedAll).policyGeneration == 2

  test "a Cycle met in custody is held while receipts keep draining behind it":
    let steps =
      admissionSteps(everyBit, selectedAll) & stagingSteps() &
      @[
        writeStep(4, released(cycle(3)), refusal = 11),
        writeStep(4, released(receipt(4)), refusal = 11),
        writeStep(5),
        writeStep(4, released(submitted(2, WmFileKind.dirty, 5))),
        writeStep(5),
        clunkStep(6),
      ] & objectSteps(snapshotObject(), 40)
    var request: ProjectionRequest
    var receipts: seq[PresentationReceipt]
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire()
        wire.requestDirty(PolicyDirty(policyGeneration: 2, affectedOutputs: @[7'u64]))
        check wire.receiveSnapshot().generation == 19
        request = wire.receiveRequest()
        receipts = wire.takeReceipts()
        wire.close()
    )
    check log.failure == ""
    check log.stepsDone == steps.len
    check request.requestId == 55
    check receipts.len == 1
    # The receipt's cumulative acknowledgement released the held Cycle's
    # retention; taking the Cycle later sends no older acknowledgement.
    check log.acks() == @[1'u64, 2, 4, 5]

  test "a second event met in custody fails closed rather than replace the held one":
    let second = event(WmFileKind.configurationOutcome, 4).encodeConfigurationOutcome(
        WmFileConfigurationOutcome(
          transaction: 1, generation: 1, kind: ProjectionOutcomeKind.committed
        ),
        selectedAll,
      )
    let steps =
      admissionSteps(everyBit, selectedAll) & stagingSteps() &
      @[
        writeStep(4, released(cycle(3), second), refusal = 11),
        writeStep(4, refusal = 11),
      ]
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire()
        check raisedMessage(
          proc() =
            wire.requestDirty(
              PolicyDirty(policyGeneration: 2, affectedOutputs: @[7'u64])
            )
        ) == "a second WM event arrived during candidate custody"
    )
    check log.failure == ""
    check log.stepsDone == steps.len

  test "a withheld permit ends at the candidate cap with paced retries":
    var refusals = stagingSteps()
    for _ in 0 ..< 600:
      refusals.add(writeStep(4, refusal = 11))
    let steps = admissionSteps(everyBit, selectedAll) & refusals
    var elapsed: int64
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire()
        let start = getMonoTime()
        check raisedMessage(
          proc() =
            wire.requestDirty(
              PolicyDirty(policyGeneration: 2, affectedOutputs: @[7'u64])
            )
        ) != "no error"
        elapsed = (getMonoTime() - start).inMilliseconds
    )
    check log.failure == ""
    check elapsed >= 3_900 and elapsed < 5_000
    # Paced at 10 ms: never a spin, never more than the cap allows.
    check log.submits() - 1 in 150 .. 410

  test "the snapshot must be the one its Cycle names":
    let steps =
      admissionSteps(everyBit, selectedAll, after = released(cycle(3))) &
      objectSteps(snapshotObject(99), 40)
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire()
        check raisedMessage(
          proc() =
            discard wire.receiveSnapshot()
        ) == "snapshot/Cycle publication mismatch"
    )
    check log.failure == ""
    check log.stepsDone == steps.len

  test "an event out of sequence or epoch closes":
    for (record, message) in [
      (cycle(4), "WM event sequence has a gap or replay"),
      (cycle(3, 8), "WM event belongs to another epoch"),
    ]:
      let steps = admissionSteps(everyBit, selectedAll, after = released(record))
      let log = steps.run(
        proc(socket: Socket) =
          let wire = socket.fileWire()
          check raisedMessage(
            proc() =
              discard wire.receiveSnapshot()
          ) == message
      )
      check log.failure == ""

  test "a started event must finish within its assembly bound; idle before it is not bounded":
    # A trickle of four-byte fragments 40 ms apart needs about 880 ms; the
    # test bound is 200 ms from the first byte. Expiry is observed by the
    # capped wait for the next fragment, or on taking one after the bound.
    let trickle = PeerEvent(bytes: cycle(3), perRead: 4, delayMs: 40)
    let steps = admissionSteps(everyBit, selectedAll, after = @[trickle])
    var elapsed: int64
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire(assemblyMillis = 200)
        let start = getMonoTime()
        check raisedMessage(
          proc() =
            discard wire.receiveSnapshot()
        ) != "no error"
        elapsed = (getMonoTime() - start).inMilliseconds
    )
    check log.failure == ""
    check elapsed < 600
    check log.eventReads < 2 + 22

    # Waiting 400 ms before the first byte is ordinary idle, not assembly.
    let late = PeerEvent(bytes: cycle(3), leadMs: 400)
    let idle =
      admissionSteps(everyBit, selectedAll, after = @[late]) &
      objectSteps(snapshotObject(), 40) & @[writeStep(5)]
    let quiet = idle.run(
      proc(socket: Socket) =
        let wire = socket.fileWire(assemblyMillis = 200)
        check wire.receiveSnapshot().generation == 19
        wire.close()
    )
    check quiet.failure == ""
    check quiet.stepsDone == idle.len

  test "an event completed during a slow request waits for its consumer uncapped":
    # The Cycle arrives whole while the retried submit's reply is held back
    # past the 200 ms assembly bound; once complete, only its consumer waits.
    let steps =
      admissionSteps(everyBit, selectedAll) & stagingSteps() &
      @[
        writeStep(4, refusal = 11),
        PeerStep(
          kind: twrite,
          fid: 4,
          early: released(cycle(3)),
          delayMs: 400,
          events: released(submitted(2, WmFileKind.dirty, 4)),
        ),
        writeStep(5),
        clunkStep(6),
      ] & objectSteps(snapshotObject(), 40)
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire(assemblyMillis = 200)
        wire.requestDirty(PolicyDirty(policyGeneration: 2, affectedOutputs: @[7'u64]))
        check wire.receiveSnapshot().generation == 19
        wire.close()
    )
    check log.failure == ""
    check log.stepsDone == steps.len
    check log.acks() == @[1'u64, 2, 4]

  test "an event still incomplete during a slow request stays capped":
    let prefix = PeerEvent(bytes: cycle(3)[0 ..< 40])
    let steps =
      admissionSteps(everyBit, selectedAll) & stagingSteps() &
      @[
        writeStep(4, refusal = 11),
        PeerStep(kind: twrite, fid: 4, early: @[prefix], delayMs: 1_000),
      ]
    var elapsed: int64
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire(assemblyMillis = 200)
        let start = getMonoTime()
        check raisedMessage(
          proc() =
            wire.requestDirty(
              PolicyDirty(policyGeneration: 2, affectedOutputs: @[7'u64])
            )
        ) != "no error"
        elapsed = (getMonoTime() - start).inMilliseconds
    )
    check log.failure == ""
    check elapsed < 800

  test "an object read is bounded as a whole, not per reply":
    # Eight bytes per reply, 30 ms apart, cannot finish the snapshot inside
    # the 200 ms test bound, though every single reply is prompt.
    let bytes = snapshotObject()
    var trickle = @[walkStep(40), openStep(2, 40)]
    trickle.add(objectSteps(bytes, 40)[2])
    var offset = 0
    while offset < bytes.len:
      let finish = min(offset + 8, bytes.len)
      var body: seq[byte]
      body.addU32(uint32(finish - offset))
      body.add(bytes[offset ..< finish])
      trickle.add(PeerStep(kind: tread, fid: 2, reply: body, delayMs: 30))
      offset = finish
    let steps =
      admissionSteps(everyBit, selectedAll, after = released(cycle(3))) & trickle
    var elapsed: int64
    let log = steps.run(
      proc(socket: Socket) =
        let wire = socket.fileWire(assemblyMillis = 200)
        let start = getMonoTime()
        check raisedMessage(
          proc() =
            discard wire.receiveSnapshot()
        ) != "no error"
        elapsed = (getMonoTime() - start).inMilliseconds
    )
    check log.failure == ""
    check elapsed < 600
    check log.stepsDone < steps.len
