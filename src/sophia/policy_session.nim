import std/options

import ./[policy_adapter, session_types]

type
  PolicySessionError* = object of CatchableError

  PendingProjection = object
    adapter: PolicyAdapter
    request: ProjectionRequest
    transaction: uint64

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
  candidate.applyCause(request)
  result = candidate.projection(snapshot, request)
  session.pending = some(
    PendingProjection(adapter: candidate, request: request, transaction: transaction)
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
