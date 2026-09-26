import std/[options, os]

import ../config/policy_candidate
import ../types/[config_values, handoff, session, wm_presentation, wm_v1]
import ../types/observability
import ../observability
import
  ./[
    policy_adapter, policy_checkpoint, policy_session, policy_signals, policy_trace,
    policy_transport, policy_wire, profile_handoff,
  ]

## The policy loop over any admitted wire: startup profile activation, the
## optional configuration, and settled cycles with their session operations,
## refreshes, checkpoints and reload. The bytes live with each wire; the policy
## state lives in `PolicySession`. Moved unchanged from policy_client.nim, with
## each frame call replaced by its typed wire operation.

proc settleProfileCommand(
    wire: PolicyWire,
    model: var ProfileHandoffModel,
    message: Option[ProfileHandoffMsg],
    outOfPhase: string,
): ProfileOutcomeKind =
  ## A command the phase does not admit arrives as none and is refused in the
  ## phase's own words before it is decoded.
  if message.isNone:
    fail(outOfPhase)
  let update = model.reduceProfileHandoff(message.get())
  model = update.model
  wire.completeProfile(message.get().kind, update.completion)
  update.completion.outcome

proc activateProfileCandidate*(
    wire: PolicyWire, candidate: AuthorityCandidate
): StartupProfileHandoffDisposition =
  ## Bounded participant barrier shared by startup and exact-key reattachment.
  ## The caller decides whether an accepted client enters the normal cycle.
  var model = candidate.initProfileHandoff(wire.connectionEpoch)
  let prepared = wire.settleProfileCommand(
    model,
    wire.receiveProfileCommand({ProfileHandoffMsgKind.prepare}),
    "desktop profile command is out of phase",
  )
  if prepared != ProfileOutcomeKind.accepted:
    operationalLog(OperationalLevel.failure, "profile_prepare", "rejected_identity")

  for _ in 0 ..< 2:
    let message = wire.receiveProfileCommand(
      {ProfileHandoffMsgKind.activate, ProfileHandoffMsgKind.rollback}
    )
    let outcome = wire.settleProfileCommand(
      model, message, "normal policy traffic preceded desktop profile activation"
    )
    case message.get().kind
    of ProfileHandoffMsgKind.activate:
      if outcome == ProfileOutcomeKind.accepted:
        return StartupProfileHandoffDisposition.activated
    of ProfileHandoffMsgKind.rollback:
      if outcome == ProfileOutcomeKind.accepted:
        return StartupProfileHandoffDisposition.rolledBack
      return StartupProfileHandoffDisposition.rejected
    of ProfileHandoffMsgKind.prepare:
      discard
  StartupProfileHandoffDisposition.rejected

proc settlePresentationReceipts(
    wire: PolicyWire, session: var PolicySession
): seq[PresentationReceipt] =
  ## Receipts that arrived since the last cycle, applied after that cycle's
  ## settlement and before the next reduction.
  result = wire.takeReceipts()
  for receipt in result:
    session.receivePresentationReceipt(receipt)

proc requestFreshCycle(
    wire: PolicyWire, policyGeneration: uint64, snapshot: PolicySnapshot
) =
  wire.requestDirty(policyDirty(policyGeneration, snapshot))
  operationalLog(
    OperationalLevel.info, "policy_refresh", "requested", "checkpoint_reconciled"
  )
  recordEvidence(
    EvidenceEvent(
      kind: EvidenceKind.reducer,
      event: "policy_refresh",
      epoch: wire.connectionEpoch,
      generation: policyGeneration + 1,
      status: "refresh_requested",
    )
  )

## Exercise a bounded sequence of complete public-policy cycles without Triad
## machinery. The shared revision-3 corpus uses one connection so output loss
## and generational return exercise the client's retained private identity.
proc runPolicyCycles*(wire: PolicyWire, cycleCount: int) =
  let tracePath = getEnv("HAGIA_POLICY_TRACE")
  var session = initPolicySession()
  try:
    if cycleCount < 1 or cycleCount > 16:
      fail("policy proof cycle count is invalid")
    for _ in 0 ..< cycleCount:
      let snapshot = wire.receiveSnapshot()
      let request = wire.receiveRequest()
      let transaction = wire.allocateTransaction()
      let receipts = wire.settlePresentationReceipts(session)
      if tracePath.len > 0:
        # Recorded before the reduction, so a trace replays the inputs rather
        # than a conclusion already drawn from them.
        tracePath.appendTrace(
          PolicyTraceEntry(
            snapshot: snapshot,
            request: request,
            transaction: transaction,
            presentationReceipts: receipts,
          )
        )
      let projection = session.prepare(snapshot, request, transaction)
      let completion = wire.submitProjection(request, transaction, projection)
      completion.requireSessionOperationExpectation(session.pendingOperation())
      session.settle(completion.outcome)
  finally:
    session.abort()
    wire.close()

## Process several settled projections on one authenticated connection. Sophia's
## supervisor, rather than this client, owns restart policy after transport loss.
proc runPolicySession*(
    wire: PolicyWire,
    configure: bool,
    policyCandidate: Option[AuthorityCandidate] = none(AuthorityCandidate),
    preparedAdapter: Option[PolicyAdapter] = none(PolicyAdapter),
) =
  if policyCandidate.isSome and
      policyCandidate.get().policyCandidateSettings().workspaceAssignments.len > 0 and
      (wire.capabilities and (capabilityOutputActions or capabilityOutputPolicyKeys)) !=
      (capabilityOutputActions or capabilityOutputPolicyKeys):
    fail("assigned workspaces require output_actions and output_policy_keys")
  installPolicySignals()
  let tracePath = getEnv("HAGIA_POLICY_TRACE")
  let privateCheckpoint = checkpointPath()
  var checkpointEnabled = privateCheckpoint.len > 0
  var restoredCheckpoint = false
  var session =
    if preparedAdapter.isSome:
      initPolicySession(preparedAdapter.get())
    elif policyCandidate.isSome:
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
        recordEvidence(
          EvidenceEvent(
            kind: EvidenceKind.checkpoint, event: "checkpoint", status: "loaded"
          )
        )
        session = initPolicySession(candidate)
        restoredCheckpoint = true
    except PolicyCheckpointError as error:
      operationalLog(OperationalLevel.warning, "checkpoint", "discarded", error.msg)
      recordEvidence(
        EvidenceEvent(
          kind: EvidenceKind.checkpoint, event: "checkpoint", status: "discarded"
        )
      )
  try:
    if configure:
      let configuration = hagiaConfiguration(
        wire.capabilities, wire.connectionEpoch, wire.allocateTransaction()
      )
      wire.installConfiguration(configuration).requireConfigurationOutcome(
        configuration
      )
      injectConfiguredFault("configuration_installed")
    while true:
      let snapshot = wire.receiveSnapshot()
      injectConfiguredFault("snapshot_received")
      let request = wire.receiveRequest()
      let transaction = wire.allocateTransaction()
      let receipts = wire.settlePresentationReceipts(session)
      if tracePath.len > 0:
        tracePath.appendTrace(
          PolicyTraceEntry(
            snapshot: snapshot,
            request: request,
            transaction: transaction,
            presentationReceipts: receipts,
          )
        )
      let projection = session.prepare(snapshot, request, transaction)
      if projection.activeOutput != snapshot.activeOutput:
        operationalLog(OperationalLevel.info, "projection", "active_output_changed")
      injectConfiguredFault("projection_prepared")
      let operation = session.pendingOperation()
      let completion = wire.submitProjection(request, transaction, projection)
      injectConfiguredFault("outcome_received")
      # Checked before settlement, checkpoint or promotion.
      completion.requireSessionOperationExpectation(operation)
      let outcome = completion.outcome
      session.settle(outcome)
      recordEvidence(
        EvidenceEvent(
          kind: EvidenceKind.settlement,
          event: "projection",
          epoch: request.connectionEpoch,
          generation: outcome.sceneGeneration,
          requestId: request.requestId,
          transaction: transaction,
          status: $outcome.kind,
        )
      )
      if takeDumpRequest():
        # Read-only: the dump reuses the checkpoint DTO, so it says exactly what
        # a restored generation would see, and writing it changes nothing.
        let dumpPath = getEnv("HAGIA_POLICY_DUMP")
        if dumpPath.len == 0:
          operationalLog(
            OperationalLevel.warning, "dump", "refused", "HAGIA_POLICY_DUMP is unset"
          )
        else:
          try:
            dumpPath.savePolicyCheckpoint(session.committedAdapter())
            operationalLog(OperationalLevel.info, "dump", "written", dumpPath)
            recordEvidence(
              EvidenceEvent(
                kind: EvidenceKind.checkpoint,
                event: "dump",
                epoch: request.connectionEpoch,
                generation: outcome.sceneGeneration,
                status: "written",
              )
            )
          except PolicyCheckpointError as error:
            operationalLog(OperationalLevel.warning, "dump", "failed", error.msg)
      if not checkpointEnabled and takeReloadRequest():
        # Without a checkpoint an exit would drop the session rather than
        # reload it, so the request is refused rather than half-honoured.
        operationalLog(
          OperationalLevel.warning, "reload", "refused",
          "HAGIA_POLICY_CHECKPOINT is unset",
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
              event: "checkpoint",
              epoch: request.connectionEpoch,
              generation: outcome.sceneGeneration,
              status: "saved",
            )
          )
          injectConfiguredFault("checkpoint_saved")
          if takeReloadRequest():
            # The checkpoint for this cycle is on disk, so exiting is a reload
            # rather than a loss: Sophia restarts the process from the same
            # path and the next generation reconciles this state against a
            # complete snapshot.
            operationalLog(OperationalLevel.info, "reload", "requested")
            recordEvidence(
              EvidenceEvent(
                kind: EvidenceKind.connection,
                event: "reload",
                epoch: request.connectionEpoch,
                generation: outcome.sceneGeneration,
                status: "reload_requested",
              )
            )
            quit(0)
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
            EvidenceEvent(
              kind: EvidenceKind.checkpoint, event: "checkpoint", status: "disabled"
            )
          )
      # Both sends are capability-gated by Sophia, which answers an
      # unnegotiated one with UnsupportedCapability and drops the connection.
      # A session started without configuration never requested either bit, so
      # the enhancement is skipped rather than allowed to kill the session.
      if outcome.kind == ProjectionOutcomeKind.committed and operation.isSome:
        if (wire.capabilities and capabilitySessionOperations) == 0:
          operationalLog(
            OperationalLevel.warning, "session_operation", "skipped",
            "session_operations was not negotiated",
          )
        else:
          let operationOutcome = wire.submitSessionOperation(operation.get())
          if operationOutcome == ProjectionOutcomeKind.disconnected:
            return
      if outcome.kind == ProjectionOutcomeKind.committed and restoredCheckpoint:
        if (wire.capabilities and capabilityPolicyDirty) == 0:
          operationalLog(
            OperationalLevel.warning, "policy_refresh", "skipped",
            "policy_dirty was not negotiated",
          )
        else:
          wire.requestFreshCycle(session.policyGeneration(), snapshot)
        restoredCheckpoint = false
      if outcome.kind == ProjectionOutcomeKind.disconnected:
        return
  finally:
    session.abort()
    wire.close()

proc runActivatedPolicy*(wire: PolicyWire, candidate: AuthorityCandidate) =
  try:
    # Active permits Sophia to open its graphical gate. Build the actual
    # policy first, so a value-level rejection cannot arrive after that promise.
    if candidate.policyCandidateSettings().workspaceAssignments.len > 0 and
        (wire.capabilities and (capabilityOutputActions or capabilityOutputPolicyKeys)) !=
        (capabilityOutputActions or capabilityOutputPolicyKeys):
      fail("assigned workspaces require output_actions and output_policy_keys")
    let prepared = initPolicyAdapter(candidate)
    if wire.activateProfileCandidate(candidate) !=
        StartupProfileHandoffDisposition.activated:
      fail("desktop profile activation did not admit normal policy traffic")
    wire.enterPolicyTraffic()
    wire.runPolicySession(true, some(candidate), some(prepared))
  finally:
    wire.close()
