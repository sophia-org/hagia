import std/[os, strutils]
import
  types/[
    config_values, handoff, session, wm_files, wm_file_arrays, wm_file_bodies, wm_v1,
    wm_presentation,
  ]
import sophia/[profile_handoff, wm_files, wm_file_arrays, wm_file_bodies]
import support/wm_file_peer_io

## Independent codec/transport peer for Session's supplied-stream fixture.
## Configuration and placement are scripted. This is not the Hagia policy
## loop, authenticated launch, Engine acceptance, or physical presentation.

proc custody(peer: WmFileTestPeer, id: uint64, kind: WmFileKind) =
  let bytes = peer.nextEvent(WmFileKind.submitted)
  let value = bytes.decodeSubmitted(peer.epoch)
  requirePeer(
    value.acceptedSubmissionId == id and value.candidateKind == kind,
    "Submitted correlation mismatch",
  )
  peer.releaseCandidate(bytes)

proc startup(peer: WmFileTestPeer) =
  let api = peer.readObject("api")
  var apiText = newString(api.len)
  for index, value in api:
    apiText[index] = char(value)
  requirePeer(
    apiText == "sophia-wm-files version=1 output_transport=current_ipc\n",
    "wrong API/output-role discovery",
  )
  let limitsBytes = peer.readObject("limits")
  let header = limitsBytes.decodeRecord(WmFileClass.objectRecord)
  requirePeer(header.connectionEpoch == 9, "fixture admission epoch mismatch")
  peer.epoch = header.connectionEpoch
  let limits = limitsBytes.decodeLimits(peer.epoch)
  requirePeer(limits.profileRequired, "fixture must require profile activation")
  let required =
    capabilityConfiguration or capabilityProfileActivation or capabilitySurfaceInstances or
    capabilitySessionOperations
  requirePeer(
    (limits.capabilityCeiling and required) == required,
    "required fixture capabilities unavailable",
  )
  # The supplied fixture may select unused capabilities. A production adapter
  # must offer only its implemented vocabulary; this is not its offer policy.
  peer.submit(
    peer.candidateHeader(WmFileKind.negotiate, 1).encodeNegotiate(
      WmFileNegotiationOffer(
        required: required, optional: limits.capabilityCeiling and not required
      )
    )
  )
  peer.custody(1, WmFileKind.negotiate)
  let negotiated = peer.nextEvent(WmFileKind.negotiated)
  peer.selected = negotiated.decodeNegotiated(peer.epoch)
  requirePeer(
    (peer.selected and required) == required and
      (peer.selected and not limits.capabilityCeiling) == 0,
    "invalid capability selection",
  )
  peer.ack(negotiated)
  # The candidate identity is fixed independently of the server commands.
  var model = AuthorityCandidate(
    authority: ProfileAuthority.policy, generation: 3, digest: repeat("07", 32)
  ).initProfileHandoff(peer.epoch)
  for stage in [ProfileHandoffMsgKind.prepare, ProfileHandoffMsgKind.activate]:
    let bytes = peer.nextEvent(stage.commandFileKind())
    let command = bytes.decodeProfileCommand(stage, peer.epoch, peer.selected)
    requirePeer(
      command.transaction ==
        (if stage == ProfileHandoffMsgKind.prepare: 40'u64 else: 41'u64),
      "profile server transaction mismatch",
    )
    let update =
      model.reduceProfileHandoff(ProfileHandoffMsg(kind: stage, command: command))
    requirePeer(
      update.completion.outcome == ProfileOutcomeKind.accepted,
      "profile reducer refused fixture identity/order",
    )
    model = update.model
    peer.ack(bytes)
    let id = if stage == ProfileHandoffMsgKind.prepare: 2'u64 else: 3'u64
    peer.submit(
      peer.candidateHeader(stage.completionFileKind(), id).encodeProfileCompletion(
        update.completion, peer.selected
      )
    )
    peer.custody(id, stage.completionFileKind())
  requirePeer(model.phase == ProfileHandoffPhase.active, "profile never became active")

proc cycle(peer: WmFileTestPeer) =
  let configuration =
    WmFileConfiguration(transaction: 10, connectionEpoch: peer.epoch, generation: 3)
  peer.submit(
    peer.candidateHeader(WmFileKind.configuration, 4).encodeFileConfiguration(
      configuration, peer.selected
    )
  )
  peer.custody(4, WmFileKind.configuration)
  let configBytes = peer.nextEvent(WmFileKind.configurationOutcome)
  let config = configBytes.decodeConfigurationOutcome(peer.epoch, peer.selected)
  requirePeer(
    config.transaction == 10 and config.generation == 3 and
      config.kind == ProjectionOutcomeKind.committed,
    "scripted configuration outcome mismatch",
  )
  peer.ack(configBytes)
  let cycleBytes = peer.nextEvent(WmFileKind.cycle)
  let cycle = cycleBytes.decodeCycle(peer.epoch, peer.selected)
  requirePeer(
    cycle.snapshotTransaction == 100 and cycle.requestTransaction == 101 and
      cycle.request.requestId == 55 and cycle.request.policyGeneration == 3,
    "Cycle fixture identity mismatch",
  )
  let snapshot =
    peer.readObject("snapshot").decodeFileSnapshot(peer.epoch, peer.selected)
  requirePeer(
    snapshot.transaction == cycle.snapshotTransaction and
      snapshot.snapshot.generation == cycle.request.sceneGeneration,
    "snapshot/Cycle publication mismatch",
  )
  requirePeer(
    snapshot.snapshot.generation == 7 and snapshot.snapshot.activeOutput == 1 and
      snapshot.snapshot.outputs.len == 1 and snapshot.snapshot.surfaces.len == 1,
    "snapshot fixture shape mismatch",
  )
  let output = snapshot.snapshot.outputs[0]
  let surface = snapshot.snapshot.surfaces[0]
  requirePeer(
    output.output == 1 and output.generation == 3 and output.policyKey == 22 and
      surface.surfaceIndex == 3 and surface.surfaceGeneration == 1 and
      surface.stateGeneration == 8,
    "snapshot row identity mismatch",
  )
  peer.ack(cycleBytes)
  let projection = PolicyProjection(
    activeOutput: output.output,
    outputs: @[
      PolicyOutputProjection(
        output: ProjectionOutput(
          output: output.output,
          placementCount: 1,
          focusIndex: surface.surfaceIndex,
          focusGeneration: surface.surfaceGeneration,
        ),
        placements: @[
          ProjectionPlacement(
            surfaceIndex: surface.surfaceIndex,
            surfaceGeneration: surface.surfaceGeneration,
            stateGeneration: surface.stateGeneration,
            x: surface.x,
            y: surface.y,
            width: surface.width,
            height: surface.height,
            transform: 1,
          )
        ],
      )
    ],
  )
  peer.submit(
    peer.candidateHeader(WmFileKind.projection, 5).encodeFileProjection(
      11, cycle.request, projection, peer.selected
    )
  )
  peer.custody(5, WmFileKind.projection)
  let outcomeBytes = peer.nextEvent(WmFileKind.projectionOutcome)
  let outcome = outcomeBytes.decodeProjectionOutcome(peer.epoch, peer.selected)
  requirePeer(
    outcome.outcome.transaction == 11 and
      outcome.outcome.requestId == cycle.request.requestId and
      outcome.outcome.sceneGeneration == cycle.request.sceneGeneration and
      outcome.outcome.kind == ProjectionOutcomeKind.committed and
      outcome.expectSessionOperation,
    "scripted projection outcome mismatch",
  )
  peer.ack(outcomeBytes)
  peer.submit(
    peer.candidateHeader(WmFileKind.sessionOperation, 6).encodeSessionOperation(
      WmFileSessionOperation(
        transaction: 12, intent: SessionOperationIntent(requestId: 55, operation: 1)
      ),
      peer.selected,
    )
  )
  peer.custody(6, WmFileKind.sessionOperation)
  let operationBytes = peer.nextEvent(WmFileKind.sessionOperationOutcome)
  let operation =
    operationBytes.decodeSessionOperationOutcome(peer.epoch, peer.selected)
  requirePeer(
    operation.transaction == 12 and operation.requestId == 55 and
      operation.kind == ProjectionOutcomeKind.committed,
    "scripted session-operation outcome mismatch",
  )
  peer.ack(operationBytes)
  let receiptBytes = peer.nextEvent(WmFileKind.presentationReceipt)
  let receipt = receiptBytes.decodePresentationReceipt(peer.epoch, peer.selected)
  requirePeer(
    receipt.transaction == 102 and receipt.receipt.publicationGeneration == 1 and
      receipt.receipt.output == 1 and receipt.receipt.outputGeneration == 3 and
      receipt.receipt.presentationEpoch == 1 and
      receipt.receipt.outcome == PresentationOutcomeKind.presented,
    "scripted receipt mismatch",
  )
  peer.ack(receiptBytes)

if paramCount() != 2 or paramStr(2) notin ["startup", "cycle"]:
  quit("usage: wm_file_session_peer SOCKET_PATH startup|cycle", 2)
try:
  let peer = connectFilePeer(paramStr(1))
  try:
    peer.startup()
    if paramStr(2) == "cycle":
      peer.cycle()
    echo "hagia_wm_file_peer schema=1 status=pass scenario=" & paramStr(2) &
      " supplied_admission=true scripted_outcomes=true native_presentation=false"
  finally:
    peer.close()
except CatchableError as error:
  quit(
    "hagia_wm_file_peer schema=1 status=failed scenario=" & paramStr(2) & " reason=" &
      error.msg,
    1,
  )
