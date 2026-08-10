import std/options

import ../policy/actions
import ../runtime/reducer
import ./[policy_adapter, session_types, wm_v1]

type
  PolicySessionError* = object of CatchableError

  PendingProjection = object
    adapter: PolicyAdapter
    request: ProjectionRequest
    transaction: uint64
    operation: Option[SessionOperationIntent]

  PolicySession* = object
    committed: PolicyAdapter
    pending: Option[PendingProjection]
    committedSceneGeneration: uint64
    committedPolicyGeneration: uint64
    runtime: RuntimeModel

proc fail(message: string) {.noreturn.} =
  raise newException(PolicySessionError, message)

proc initPolicySession*(): PolicySession =
  PolicySession(committed: initPolicyAdapter())

proc initPolicySession*(adapter: PolicyAdapter): PolicySession =
  PolicySession(committed: adapter)

proc hasPending*(session: PolicySession): bool =
  session.pending.isSome

proc committedAdapter*(session: PolicySession): PolicyAdapter =
  session.committed

proc committedGeneration*(session: PolicySession): uint64 =
  session.committedSceneGeneration

proc policyGeneration*(session: PolicySession): uint64 =
  session.committedPolicyGeneration

proc runtimeModel*(session: PolicySession): RuntimeModel =
  session.runtime

proc pendingOperation*(session: PolicySession): Option[SessionOperationIntent] =
  if session.pending.isSome:
    session.pending.get().operation
  else:
    none(SessionOperationIntent)

proc operationFor(
    snapshot: PolicySnapshot, request: ProjectionRequest
): Option[SessionOperationIntent] =
  if request.cause.kind != ProjectionCauseKind.action:
    return none(SessionOperationIntent)
  var operationSlot = 0'u16
  var actionKnown = false
  for action in snapshot.actions:
    if action.action == request.cause.action:
      if actionKnown:
        fail("session operation action is ambiguous")
      actionKnown = true
      operationSlot = action.sessionOperationSlot
  if not actionKnown:
    # Semantic unit fixtures may omit the installed action catalog for pure
    # policy actions; live snapshots always carry it.
    if request.cause.action.isPolicyAction():
      return none(SessionOperationIntent)
    fail("policy action is not registered")
  if operationSlot == 0:
    return none(SessionOperationIntent)
  if request.cause.activationSerial == 0:
    fail("session operation activation is invalid")
  var selected: Option[SnapshotSessionOperation]
  for operation in snapshot.sessionOperations:
    if operation.slot == operationSlot:
      if selected.isSome:
        fail("session operation slot is ambiguous")
      selected = some(operation)
  if selected.isNone:
    fail("session operation slot is unavailable")

  var targetIndex, targetGeneration: uint32
  if (selected.get().targetBits and 1) != 0:
    for output in snapshot.outputs:
      if output.output == snapshot.activeOutput:
        targetIndex = output.focusIndex
        targetGeneration = output.focusGeneration
        break
    if targetGeneration == 0:
      fail("targeted session operation has no focused surface")
  some(
    SessionOperationIntent(
      requestId: request.cause.activationSerial,
      operation: selected.get().operation,
      targetIndex: targetIndex,
      targetGeneration: targetGeneration,
    )
  )

## Reconciliation is speculative until Sophia confirms the complete projection.
proc prepare*(
    session: var PolicySession,
    snapshot: PolicySnapshot,
    request: ProjectionRequest,
    transaction: uint64,
): PolicyProjection =
  if session.pending.isSome:
    fail("a policy projection is already pending")
  if transaction == 0 or request.connectionEpoch == 0 or request.requestId == 0 or
      request.sceneGeneration != snapshot.generation or request.policyGeneration == 0 or
      request.policyGeneration < session.committedPolicyGeneration:
    fail("policy projection identity is invalid")
  if session.runtime.connectionEpoch != request.connectionEpoch:
    session.runtime = session.runtime.reduceRuntime(
      RuntimeMsg(kind: RuntimeMsgKind.connectionStarted, epoch: request.connectionEpoch)
    ).model
  session.runtime = session.runtime.reduceRuntime(
    RuntimeMsg(
      kind: RuntimeMsgKind.snapshotCompleted,
      epoch: request.connectionEpoch,
      generation: snapshot.generation,
    )
  ).model
  var candidate = session.committed.clone()
  candidate.reconcile(snapshot)
  let operation = snapshot.operationFor(request)
  if operation.isNone:
    candidate.applyCause(request)
  result = candidate.projection(snapshot, request)
  session.pending = some(
    PendingProjection(
      adapter: candidate,
      request: request,
      transaction: transaction,
      operation: operation,
    )
  )
  session.runtime = session.runtime.reduceRuntime(
    RuntimeMsg(
      kind: RuntimeMsgKind.projectionPrepared,
      epoch: request.connectionEpoch,
      requestId: request.requestId,
      transaction: transaction,
    )
  ).model

proc settle*(session: var PolicySession, outcome: ProjectionOutcome) =
  if session.pending.isNone:
    fail("policy outcome has no pending projection")
  let pending = session.pending.get()
  if outcome.transaction != pending.transaction or
      outcome.connectionEpoch != pending.request.connectionEpoch or
      outcome.requestId != pending.request.requestId or outcome.sceneGeneration == 0:
    fail("policy outcome identity is invalid")
  if outcome.kind == ProjectionOutcomeKind.committed:
    session.committed = pending.adapter
    session.committedSceneGeneration = outcome.sceneGeneration
    session.committedPolicyGeneration = pending.request.policyGeneration
  session.runtime = session.runtime.reduceRuntime(
    RuntimeMsg(
      kind: RuntimeMsgKind.projectionSettled,
      epoch: outcome.connectionEpoch,
      requestId: outcome.requestId,
      transaction: outcome.transaction,
      committed: outcome.kind == ProjectionOutcomeKind.committed,
    )
  ).model
  session.pending = none(PendingProjection)

proc abort*(session: var PolicySession) =
  session.pending = none(PendingProjection)
  if session.runtime.phase != RuntimePhase.disconnected:
    session.runtime = session.runtime.reduceRuntime(
      RuntimeMsg(kind: RuntimeMsgKind.connectionLost)
    ).model
