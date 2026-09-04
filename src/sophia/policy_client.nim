import std/[net, options, sets]

import ../types/[actions, config_values, handoff, session, wm_v1]
import ../types/observability
import ../observability
import
  ./[
    policy_adapter, policy_checkpoint, policy_codec, policy_session, policy_transport,
    profile_handoff, wm_v1,
  ]

export PolicyClientError, policy_codec

type PolicyClient = ref object
  socket: Socket
  connectionEpoch: uint64
  capabilities: uint64
  nextTransaction: uint64
  readTimeoutMsec: int

const
  capabilityBindings = 1'u64 shl 0
  capabilityActions = 1'u64 shl 1
  capabilityMultiOutput = 1'u64 shl 2
  capabilityChrome = 1'u64 shl 4
  capabilityPolicyDirty = 1'u64 shl 5
  capabilityConfiguration = 1'u64 shl 6
  capabilitySessionOperations = 1'u64 shl 7
  capabilityIndicators = 1'u64 shl 8
  capabilityProfileActivation = 1'u64 shl 9
  capabilityLaunchPlacement = 1'u64 shl 10

proc receiveFrame(client: PolicyClient, kind: MessageKind): Frame =
  let header = client.socket.receiveExact(frameHeaderLen, client.readTimeoutMsec)
  let payloadLen = int(header.u32At(16))
  if payloadLen > maxPayloadLen:
    fail("policy frame payload is excessive")
  let payload = client.socket.receiveExact(payloadLen, client.readTimeoutMsec)
  var bytes = header
  bytes.add(payload)
  bytes.decodeFrame(kind)

proc receiveFrame(client: PolicyClient): Frame =
  let header = client.socket.receiveExact(frameHeaderLen, client.readTimeoutMsec)
  let payloadLen = int(header.u32At(16))
  if payloadLen > maxPayloadLen:
    fail("policy frame payload is excessive")
  let payload = client.socket.receiveExact(payloadLen, client.readTimeoutMsec)
  var bytes = header
  bytes.add(payload)
  bytes.decodeFrame()

proc sendFrame(client: PolicyClient, frame: Frame) =
  client.socket.send(frame.encodeFrame().toBinaryString())

proc negotiatePolicy(
    socket: Socket, requestConfiguration: bool, requestProfileActivation = false
): PolicyClient =
  result = PolicyClient(
    socket: socket,
    nextTransaction: 1,
    readTimeoutMsec: (if requestProfileActivation: 4_000 else: -1),
  )
  var payload: seq[byte]
  payload.addU16(3)
  payload.addU16(3)
  # Request only behavior implemented by this client. The independent codec
  # still checks every experimental revision-3 message in the shared corpus.
  var optional =
    if requestConfiguration:
      capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
        capabilitySessionOperations
    else:
      0'u64
  if requestProfileActivation:
    optional = optional or capabilityProfileActivation
  payload.addU64(
    capabilityBindings or capabilityActions or capabilityMultiOutput or
      capabilityIndicators or capabilityLaunchPlacement or optional
  )
  result.sendFrame(Frame(kind: MessageKind.clientHello, payload: payload))
  let welcome = result.receiveFrame(MessageKind.serverWelcome)
  if welcome.payload.u16At(0) != 3:
    fail("Sophia selected an unsupported policy revision")
  result.capabilities = welcome.payload.u64At(4)
  if (
    result.capabilities and (
      capabilityBindings or capabilityActions or capabilityMultiOutput or
      capabilityIndicators or capabilityLaunchPlacement
    )
  ) != (
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityIndicators or capabilityLaunchPlacement
  ):
    fail("Sophia omitted a required policy capability")
  if requestConfiguration and (result.capabilities and optional) != optional:
    fail("Sophia omitted native policy configuration")
  if requestProfileActivation and
      (result.capabilities and capabilityProfileActivation) == 0:
    fail("Sophia omitted desktop profile activation")
  result.connectionEpoch = welcome.payload.u64At(12)
  if result.connectionEpoch == 0 or welcome.payload.u16At(20) == 0 or
      welcome.payload.u16At(20) > uint16(maxOutputs) or welcome.payload.u32At(24) == 0 or
      welcome.payload.u32At(24) > uint32(maxSurfaces) or
      welcome.payload.u16At(22) > uint16(maxBindings) or welcome.payload.u32At(28) == 0 or
      welcome.payload.u32At(28) > uint32(maxPayloadLen):
    fail("Sophia advertised invalid policy limits")
  injectConfiguredFault("negotiated")

proc connectPolicy(
    path: string, requestConfiguration: bool, requestProfileActivation = false
): PolicyClient =
  path.connectWhenReady().negotiatePolicy(
    requestConfiguration, requestProfileActivation
  )

proc settleProfileCommand(
    client: PolicyClient,
    model: var ProfileHandoffModel,
    kind: ProfileHandoffMsgKind,
    frame: Frame,
): ProfileOutcomeKind =
  let expected =
    case kind
    of ProfileHandoffMsgKind.prepare: MessageKind.profilePrepare
    of ProfileHandoffMsgKind.activate: MessageKind.profileActivate
    of ProfileHandoffMsgKind.rollback: MessageKind.profileRollback
  if frame.kind != expected:
    fail("desktop profile command is out of phase")
  let update = model.reduceProfileHandoff(
    ProfileHandoffMsg(kind: kind, command: frame.decodeProfileCommand())
  )
  model = update.model
  let response =
    case kind
    of ProfileHandoffMsgKind.prepare: MessageKind.profilePrepared
    of ProfileHandoffMsgKind.activate: MessageKind.profileActive
    of ProfileHandoffMsgKind.rollback: MessageKind.profileRolledBack
  client.sendFrame(
    response.profileCompletionFrame(
      update.completion.transaction, update.completion.identity,
      update.completion.outcome,
    )
  )
  update.completion.outcome

proc activateProfileCandidate(
    client: PolicyClient, candidate: AuthorityCandidate
): StartupProfileHandoffDisposition =
  ## Bounded participant barrier shared by startup and exact-key reattachment.
  ## The caller decides whether an accepted client enters the normal cycle.
  var model = candidate.initProfileHandoff(client.connectionEpoch)
  let prepared = client.settleProfileCommand(
    model, ProfileHandoffMsgKind.prepare, client.receiveFrame()
  )
  if prepared != ProfileOutcomeKind.accepted:
    operationalLog(OperationalLevel.failure, "profile_prepare", "rejected_identity")

  for _ in 0 ..< 2:
    let frame = client.receiveFrame()
    case frame.kind
    of MessageKind.profileActivate:
      let outcome =
        client.settleProfileCommand(model, ProfileHandoffMsgKind.activate, frame)
      if outcome == ProfileOutcomeKind.accepted:
        return StartupProfileHandoffDisposition.activated
    of MessageKind.profileRollback:
      let outcome =
        client.settleProfileCommand(model, ProfileHandoffMsgKind.rollback, frame)
      if outcome == ProfileOutcomeKind.accepted:
        return StartupProfileHandoffDisposition.rolledBack
      return StartupProfileHandoffDisposition.rejected
    else:
      fail("normal policy traffic preceded desktop profile activation")
  StartupProfileHandoffDisposition.rejected

proc runStartupProfileHandoff*(
    socket: Socket, candidate: AuthorityCandidate
): StartupProfileHandoffDisposition =
  ## Startup-only proof entry point. It never enters the normal policy cycle.
  socket.negotiatePolicy(false, true).activateProfileCandidate(candidate)

proc receiveSnapshot(client: PolicyClient): PolicySnapshot =
  let begin = client.receiveFrame(MessageKind.snapshotBegin)
  let connectionEpoch = begin.payload.u64At(0)
  let generation = begin.payload.u64At(8)
  let activeOutput = begin.payload.u64At(16)
  let chunkCount = int(begin.payload.u16At(24))
  let declaredOutputs = int(begin.payload.u16At(26))
  let declaredSurfaces = int(begin.payload.u32At(28))
  let declaredActions = int(begin.payload.u16At(32))
  let declaredSessionOperations = int(begin.payload.u16At(34))
  if connectionEpoch != client.connectionEpoch or generation == 0 or chunkCount == 0 or
      activeOutput == 0 or declaredOutputs == 0 or declaredOutputs > maxOutputs or
      declaredSurfaces > maxSurfaces or declaredActions > maxBindings or
      declaredSessionOperations > maxBindings:
    fail("policy snapshot header is invalid")
  var outputs: seq[SnapshotOutput]
  var surfaces: seq[SnapshotSurface]
  var actions: seq[SnapshotAction]
  var sessionOperations: seq[SnapshotSessionOperation]
  var classifications: seq[SnapshotSurfaceClassification]
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
      if chunk.payload.len != 16 + itemCount * snapshotActionSize or
          actions.len + itemCount > declaredActions:
        fail("policy action chunk count is invalid")
      for index in 0 ..< itemCount:
        actions.add(
          chunk.payload.recordBytes(index, snapshotActionSize).decodeSnapshotAction()
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
  # Frozen begin/end counts cover only ordinary chunks. A negotiated extension
  # is appended after that prefix with dense ordinals, then SnapshotEnd closes
  # the transfer without changing either frozen message layout.
  var nextOrdinal = chunkCount
  var finish = client.receiveFrame()
  while finish.kind == MessageKind.snapshotChunk:
    if (client.capabilities and capabilityLaunchPlacement) == 0 or
        finish.transaction != begin.transaction or
        finish.payload.u64At(0) != client.connectionEpoch or
        int(finish.payload.u16At(8)) != nextOrdinal or
        finish.payload.u16At(10) != snapshotSurfaceClassificationRecordKind:
      fail("policy snapshot extension identity is invalid")
    let itemCount = int(finish.payload.u32At(12))
    if itemCount == 0 or
        finish.payload.len != 16 + itemCount * snapshotSurfaceClassificationSize or
        classifications.len + itemCount > maxSurfaces:
      fail("policy surface-classification chunk count is invalid")
    for index in 0 ..< itemCount:
      classifications.add(
        finish.payload
          .recordBytes(index, snapshotSurfaceClassificationSize)
          .decodeSnapshotSurfaceClassification()
      )
    inc nextOrdinal
    finish = client.receiveFrame()
  if finish.kind != MessageKind.snapshotEnd:
    fail("policy snapshot extension was not followed by its end")
  if finish.transaction != begin.transaction or
      finish.payload.u64At(0) != client.connectionEpoch or
      finish.payload.u64At(8) != generation or
      finish.payload.u16At(16) != uint16(chunkCount) or outputs.len != declaredOutputs or
      surfaces.len != declaredSurfaces or actions.len != declaredActions or
      sessionOperations.len != declaredSessionOperations:
    fail("policy snapshot did not settle exactly")
  result = PolicySnapshot(
    generation: generation,
    activeOutput: activeOutput,
    outputs: outputs,
    surfaces: surfaces,
    actions: actions,
    sessionOperations: sessionOperations,
    classifications: classifications,
  )
  result.validateSnapshot()

proc receiveProjectionRequest(client: PolicyClient): ProjectionRequest =
  client.receiveFrame(MessageKind.projectionRequest).decodeProjectionRequest(
    client.connectionEpoch
  )

proc allocateTransaction(client: PolicyClient): uint64 =
  result = client.nextTransaction
  inc client.nextTransaction
  if result == 0 or client.nextTransaction == 0:
    fail("policy transaction identity space is exhausted")

proc installConfiguration(client: PolicyClient) =
  var payload: seq[byte]
  payload.addU64(client.connectionEpoch)
  payload.addU64(1)
  payload.addU16(uint16(ord(high(PolicyAction))))
  payload.addU16(2) # Engine-owned frame; no focus ring.
  payload.addU32(0)
  payload.addU32(0xffffb6b0'u32)
  payload.addU32(1)
  payload.addU32(0xffffb6b0'u32)
  payload.addU32(0xff7c7c7c'u32)
  for ordinal in ord(low(PolicyAction)) .. ord(high(PolicyAction)):
    payload.addAction(PolicyAction(ordinal))
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
  operationalLog(
    OperationalLevel.info, "policy_refresh", "requested", "checkpoint_reconciled"
  )
  recordEvidence(
    EvidenceEvent(
      kind: EvidenceKind.reducer,
      epoch: client.connectionEpoch,
      generation: policyGeneration + 1,
      status: "refresh_requested",
    )
  )

## Exercise a bounded sequence of complete public-policy cycles without Triad
## machinery. The shared revision-3 corpus uses one connection so output loss
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
proc runPolicySession(
    client: PolicyClient,
    configure: bool,
    policyCandidate: Option[AuthorityCandidate] = none(AuthorityCandidate),
) =
  let privateCheckpoint = checkpointPath()
  var checkpointEnabled = privateCheckpoint.len > 0
  var restoredCheckpoint = false
  var session =
    if policyCandidate.isSome:
      initPolicySession(initPolicyAdapter(policyCandidate.get()))
    else:
      initPolicySession()
  if checkpointEnabled:
    try:
      let restored = privateCheckpoint.loadPolicyCheckpoint()
      if restored.isSome:
        var candidate = restored.get()
        if policyCandidate.isSome:
          candidate.applyPolicyCandidate(policyCandidate.get())
        operationalLog(
          OperationalLevel.info,
          "checkpoint",
          "loaded",
          "candidate_nonempty=" & $candidate.hasWindows(),
        )
        recordEvidence(EvidenceEvent(kind: EvidenceKind.checkpoint, status: "loaded"))
        session = initPolicySession(candidate)
        restoredCheckpoint = true
    except PolicyCheckpointError as error:
      operationalLog(OperationalLevel.warning, "checkpoint", "discarded", error.msg)
      recordEvidence(EvidenceEvent(kind: EvidenceKind.checkpoint, status: "discarded"))
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
        operationalLog(OperationalLevel.info, "projection", "active_output_changed")
      injectConfiguredFault("projection_prepared")
      let operation = session.pendingOperation()
      let outcome = client.sendProjection(request, transaction, projection)
      injectConfiguredFault("outcome_received")
      session.settle(outcome)
      recordEvidence(
        EvidenceEvent(
          kind: EvidenceKind.settlement,
          epoch: request.connectionEpoch,
          generation: outcome.sceneGeneration,
          requestId: request.requestId,
          transaction: transaction,
          status: $outcome.kind,
        )
      )
      if outcome.kind == ProjectionOutcomeKind.committed and checkpointEnabled:
        try:
          privateCheckpoint.savePolicyCheckpoint(session.committedAdapter())
          let candidateNonempty = session.committedAdapter().hasWindows()
          operationalLog(
            OperationalLevel.info,
            "checkpoint",
            "saved",
            "candidate_nonempty=" & $candidateNonempty,
          )
          recordEvidence(
            EvidenceEvent(
              kind: EvidenceKind.checkpoint,
              epoch: request.connectionEpoch,
              generation: outcome.sceneGeneration,
              status: "saved",
            )
          )
          injectConfiguredFault("checkpoint_saved")
          if restoredCheckpoint:
            operationalLog(
              OperationalLevel.info,
              "checkpoint",
              "reconciled",
              "candidate_nonempty=" & $candidateNonempty,
            )
        except PolicyCheckpointError as error:
          checkpointEnabled = false
          operationalLog(OperationalLevel.warning, "checkpoint", "disabled", error.msg)
          recordEvidence(
            EvidenceEvent(kind: EvidenceKind.checkpoint, status: "disabled")
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

proc runPolicySession*(path: string, candidate: AuthorityCandidate) =
  path.connectPolicy(true).runPolicySession(true, some(candidate))

proc runActivatedPolicyClient(client: PolicyClient, candidate: AuthorityCandidate) =
  if client.activateProfileCandidate(candidate) !=
      StartupProfileHandoffDisposition.activated:
    client.socket.close()
    fail("desktop profile activation did not admit normal policy traffic")
  client.readTimeoutMsec = -1
  client.runPolicySession(true, some(candidate))

proc runProfileActivatedPolicySession*(path: string, candidate: AuthorityCandidate) =
  ## Reuses the authenticated connection only after exact Active settlement.
  path.connectPolicy(true, true).runActivatedPolicyClient(candidate)

proc runPolicySessionOnSocket*(socket: Socket) =
  socket.negotiatePolicy(false).runPolicySession(false)

proc runProfileActivatedPolicySessionOnSocket*(
    socket: Socket, candidate: AuthorityCandidate
) =
  ## Socket-injected conformance entry point with production-equivalent
  ## activation and configuration ordering.
  socket.negotiatePolicy(true, true).runActivatedPolicyClient(candidate)
