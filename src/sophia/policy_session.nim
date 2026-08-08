import std/options

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

proc fail(message: string) {.noreturn.} =
  raise newException(PolicySessionError, message)

proc initPolicySession*(): PolicySession =
  PolicySession(committed: initPolicyAdapter())

proc hasPending*(session: PolicySession): bool =
  session.pending.isSome

proc committedAdapter*(session: PolicySession): PolicyAdapter =
  session.committed

proc committedGeneration*(session: PolicySession): uint64 =
  session.committedSceneGeneration

proc pendingOperation*(session: PolicySession): Option[SessionOperationIntent] =
  if session.pending.isSome:
    session.pending.get().operation
  else:
    none(SessionOperationIntent)

proc operationFor(
    snapshot: PolicySnapshot, request: ProjectionRequest
): Option[SessionOperationIntent] =
  if request.cause.kind != ProjectionCauseKind.action or request.cause.action < 29 or
      request.cause.action > 32:
    return none(SessionOperationIntent)
  if request.cause.activationSerial == 0:
    fail("session operation activation is invalid")
  let slot = uint16(request.cause.action - 28)
  var selected: Option[SnapshotSessionOperation]
  for operation in snapshot.sessionOperations:
    if operation.slot == slot:
      if selected.isSome:
        fail("session operation slot is ambiguous")
      selected = some(operation)
  if selected.isNone:
    fail("session operation slot is unavailable")

  var targetIndex, targetGeneration: uint32
  if slot == 3:
    if (selected.get().targetBits and 1) == 0:
      fail("close operation does not permit a surface target")
    for output in snapshot.outputs:
      if output.output == request.affectedOutputs[0]:
        targetIndex = output.focusIndex
        targetGeneration = output.focusGeneration
        break
    if targetGeneration == 0:
      fail("close operation has no focused surface")
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
      request.sceneGeneration != snapshot.generation:
    fail("policy projection identity is invalid")
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
  session.pending = none(PendingProjection)

proc abort*(session: var PolicySession) =
  session.pending = none(PendingProjection)
