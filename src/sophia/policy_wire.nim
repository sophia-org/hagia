import std/[options, sets]
import ../policy/actions
import ../types/[actions, handoff, session, wm_presentation, wm_v1]
import ./policy_transport

## One admitted WM connection as the policy loop sees it, whatever carries it.
## Constructing a wire negotiates and admits; its epoch and selected
## capabilities are then fixed for its life, so there is no second phase model.
## Its operations are gcsafe, so a wire can serve a spawned thread as the
## startup handoff proof does.
## Each implementation owns its own bytes, refusals, ordering and timeouts, and
## `PolicySession` remains the only owner of policy state.

type PolicyWire* = object
  connectionEpoch*: uint64
  capabilities*: uint64
  ## The next profile command if it is one of `expected`, decoded; none, and
  ## undecoded, for any other message, so each phase refuses in its own terms.
  receiveProfileCommand*:
    proc(expected: set[ProfileHandoffMsgKind]): Option[ProfileHandoffMsg] {.gcsafe.}
  completeProfile*:
    proc(kind: ProfileHandoffMsgKind, completion: ProfileCompletion) {.gcsafe.}
  ## Profile handoff is over; ordinary policy traffic follows.
  enterPolicyTraffic*: proc() {.gcsafe.}
  allocateTransaction*: proc(): uint64 {.gcsafe.}
  installConfiguration*:
    proc(configuration: PolicyConfiguration): PolicyConfigurationOutcome {.gcsafe.}
  receiveSnapshot*: proc(): PolicySnapshot {.gcsafe.}
  receiveRequest*: proc(): ProjectionRequest {.gcsafe.}
  submitProjection*: proc(
    request: ProjectionRequest, transaction: uint64, projection: PolicyProjection
  ): ProjectionCompletion {.gcsafe.}
  submitSessionOperation*:
    proc(intent: SessionOperationIntent): ProjectionOutcomeKind {.gcsafe.}
  requestDirty*: proc(dirty: PolicyDirty) {.gcsafe.}
  ## Receipts that arrived since the last call, in arrival order.
  takeReceipts*: proc(): seq[PresentationReceipt] {.gcsafe.}
  close*: proc() {.gcsafe.}

proc hagiaConfiguration*(
    capabilities, connectionEpoch, transaction: uint64
): PolicyConfiguration =
  ## Hagia's fixed configuration: its action catalog, extended to the
  ## presentation actions when both presentation capabilities were selected,
  ## an Engine-owned frame and no focus ring.
  let lastAction =
    if (capabilities and (capabilitySurfaceInstances or capabilityPresentationActions)) ==
        (capabilitySurfaceInstances or capabilityPresentationActions):
      ord(high(PolicyAction))
    else:
      ord(PolicyAction.toggleOverview) - 1
  result = PolicyConfiguration(
    transaction: transaction,
    connectionEpoch: connectionEpoch,
    generation: 1,
    styleBits: 2,
    focusWidth: 0,
    focusRgb: 0xffb6b0,
    frameWidth: 1,
    frameFocusedRgb: 0xffb6b0,
    frameUnfocusedRgb: 0x7c7c7c,
  )
  for ordinal in ord(low(PolicyAction)) .. lastAction:
    let action = PolicyAction(ordinal)
    result.actions.add(
      SnapshotAction(
        action: action.raw(),
        sessionOperationSlot: action.sessionOperationSlot(),
        name: action.profileName(),
      )
    )

proc requireConfigurationOutcome*(
    outcome: PolicyConfigurationOutcome, configuration: PolicyConfiguration
) =
  if outcome.transaction != configuration.transaction or
      outcome.connectionEpoch != configuration.connectionEpoch or
      outcome.generation != configuration.generation or
      outcome.kind != ProjectionOutcomeKind.committed:
    fail("Sophia rejected Hagia's policy configuration")

proc policyDirty*(policyGeneration: uint64, snapshot: PolicySnapshot): PolicyDirty =
  ## A fresh cycle over every output of the snapshot, one generation on.
  if policyGeneration == high(uint64) or snapshot.outputs.len == 0 or
      snapshot.outputs.len > maxOutputs:
    fail("policy refresh identity is invalid")
  result.policyGeneration = policyGeneration + 1
  var outputs = initHashSet[uint64]()
  for output in snapshot.outputs:
    if output.output == 0 or output.output in outputs:
      fail("policy refresh output scope is invalid")
    outputs.incl(output.output)
    result.affectedOutputs.add(output.output)

proc requireSessionOperationExpectation*(
    completion: ProjectionCompletion, operation: Option[SessionOperationIntent]
) =
  ## Where the wire states an expectation, it must be exactly a committed
  ## projection that carries an operation; anything else would leave one side
  ## waiting for an operation the other never sends. Checked before settlement.
  if completion.expectSessionOperation.isSome and
      completion.expectSessionOperation.get() !=
      (completion.outcome.kind == ProjectionOutcomeKind.committed and operation.isSome):
    fail("Sophia's session-operation expectation disagrees with the projection")
