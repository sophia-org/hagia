import std/[options, sequtils, unittest]

import types/[actions, session, wm_v1, wm_presentation]
import policy/actions
import sophia/[policy_adapter, policy_session, wm_presentation]

proc scene(generation = 1'u64): PolicySnapshot =
  PolicySnapshot(
    generation: generation,
    activeOutput: 10,
    outputs: @[
      SnapshotOutput(output: 10, generation: 1, width: 1200, height: 900),
      SnapshotOutput(output: 20, generation: 1, x: 1200, width: 1200, height: 900),
    ],
    surfaces: @[
      SnapshotSurface(
        surfaceIndex: 1,
        surfaceGeneration: 1,
        stateGeneration: generation,
        currentOutput: 10,
        capabilityBits: 31,
        width: 400,
        height: 300,
      ),
      SnapshotSurface(
        surfaceIndex: 2,
        surfaceGeneration: 1,
        stateGeneration: generation,
        currentOutput: 20,
        capabilityBits: 31,
        width: 400,
        height: 300,
      ),
    ],
  )

proc request(
    snapshot: PolicySnapshot, id = 1'u64, action = PolicyAction.toggleOverview
): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 7,
    requestId: id,
    sceneGeneration: snapshot.generation,
    policyGeneration: 1,
    affectedOutputs: @[10'u64, 20],
    cause: ProjectionCause(
      kind: ProjectionCauseKind.action, activationSerial: id, action: action.raw()
    ),
  )

proc settle(session: var PolicySession, request: ProjectionRequest, committed = true) =
  session.settle(
    ProjectionOutcome(
      connectionEpoch: request.connectionEpoch,
      requestId: request.requestId,
      transaction: request.requestId,
      sceneGeneration: request.sceneGeneration,
      kind: (
        if committed: ProjectionOutcomeKind.committed
        else: ProjectionOutcomeKind.rejectedStale
      ),
    )
  )

proc cycle(
    session: var PolicySession,
    snapshot: PolicySnapshot,
    request: ProjectionRequest,
    committed = true,
): PolicyProjection =
  result = session.prepare(snapshot, request, request.requestId)
  session.settle(request, committed)

proc keyboard(
    publication: WmPresentation,
    snapshot: PolicySnapshot,
    id: uint64,
    action: PolicyAction,
): ProjectionRequest =
  result = snapshot.request(id, action)
  result.cause.kind = ProjectionCauseKind.presentationAction
  result.cause.presentation = PresentationIdentity(
    publicationGeneration: publication.generation,
    output: publication.keyboardOutput,
    outputGeneration: 1,
    presentationEpoch: 9,
  )

proc changed(snapshot: PolicySnapshot, id: uint64): ProjectionRequest =
  result = snapshot.request(id)
  result.cause = ProjectionCause(kind: ProjectionCauseKind.sceneChanged)

suite "overview generic presentation lifecycle":
  test "opening publishes all outputs without resizing or refocusing applications":
    let snapshot = scene()
    var ordinary = initPolicySession()
    let normal = ordinary.cycle(snapshot, snapshot.changed(1))
    var session = initPolicySession()
    let opened = session.cycle(snapshot, snapshot.request())
    check opened.outputs == normal.outputs
    let publication = opened.presentation.get()
    publication.validatePresentation()
    check publication.outputs.mapIt(it.output) == @[10'u64, 20]
    check publication.instances.len == 2
    check publication.keyboardOutput == 10
    check publication.bindings.anyIt(it.action == PolicyAction.closeOverview.raw())
    check publication.instances.allIt(it.destination.width < 1200)

  test "content-only scene updates retain exact publication and target identities":
    var session = initPolicySession()
    let first = scene()
    let publication = session.cycle(first, first.request()).presentation.get()
    let repaint = scene(2)
    check session.cycle(repaint, repaint.changed(2)).presentation.get() == publication

  test "fullscreen strip selection changes emphasis without rescaling source instances":
    var snapshot = scene()
    snapshot.outputs[0].focusIndex = 1
    snapshot.outputs[0].focusGeneration = 1
    snapshot.surfaces[0].currentStateBits = 1
    snapshot.surfaces[0].requestStateBits = 1
    snapshot.surfaces[1].currentOutput = 10
    var session = initPolicySession()
    discard session.cycle(snapshot, snapshot.request(1, PolicyAction.maximizeColumn))
    let opened = session.cycle(snapshot, snapshot.request(2))
    let publication = opened.presentation.get()
    let selection = publication.keyboard(snapshot, 3, PolicyAction.overviewRight)
    let moved = session.cycle(snapshot, selection)
    let movedPublication = moved.presentation.get()
    check moved.outputs == opened.outputs
    check movedPublication.instances == publication.instances
    check movedPublication.regions.filterIt(it.role == PresentationRegionRole.frame) ==
      publication.regions.filterIt(it.role == PresentationRegionRole.frame)
    check movedPublication.regions.filterIt(it.role == PresentationRegionRole.emphasis) !=
      publication.regions.filterIt(it.role == PresentationRegionRole.emphasis)
    let returned = session
      .cycle(
        snapshot, movedPublication.keyboard(snapshot, 4, PolicyAction.overviewLeft)
      ).presentation
      .get()
    check returned.instances == publication.instances

  test "cancel withdraws, reopening mints fresh ids, and an old action is refused":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session.cycle(snapshot, snapshot.request()).presentation.get()
    let cancel = publication.keyboard(snapshot, 2, PolicyAction.closeOverview)
    check session.cycle(snapshot, cancel).presentation.isNone
    let reopened = session.cycle(snapshot, snapshot.request(3)).presentation.get()
    check reopened.generation > publication.generation
    let priorIds = publication.instances.mapIt(it.id) & publication.regions.mapIt(it.id)
    check reopened.instances.allIt(it.id notin priorIds)
    expect PolicyAdapterError:
      discard session.prepare(
        snapshot, publication.keyboard(snapshot, 4, PolicyAction.confirmOverview), 4
      )

  test "rejection keeps the committed publication and its action mapping":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session.cycle(snapshot, snapshot.request()).presentation.get()
    let cancelled = session.cycle(
      snapshot, publication.keyboard(snapshot, 2, PolicyAction.closeOverview), false
    )
    check cancelled.presentation.isNone
    check session.cycle(snapshot, snapshot.changed(3)).presentation.get() == publication

  test "pointer selection confirms the exact target on its owning monitor":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session.cycle(snapshot, snapshot.request()).presentation.get()
    let target = publication.instances.filterIt(it.output == 20)[0]
    var choose = publication.keyboard(snapshot, 2, PolicyAction.confirmOverview)
    choose.cause.presentation.output = 20
    choose.cause.presentation.targetId = target.id
    choose.cause.presentation.targetGeneration = target.generation
    let selected = session.cycle(snapshot, choose)
    check selected.presentation.isNone
    check selected.activeOutput == 20
    check selected.outputs.filterIt(it.output.output == 20)[0].output.focusIndex == 2

  test "wrong target generation cannot change policy":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session.cycle(snapshot, snapshot.request()).presentation.get()
    let target = publication.instances[0]
    var choose = publication.keyboard(snapshot, 2, PolicyAction.confirmOverview)
    choose.cause.presentation.targetId = target.id
    choose.cause.presentation.targetGeneration = target.generation + 1
    expect PolicyAdapterError:
      discard session.prepare(snapshot, choose, 2)
    check session.cycle(snapshot, snapshot.changed(3)).presentation.get() == publication

  test "source loss and topology replacement close the publication":
    for sourceLoss in [true, false]:
      var session = initPolicySession()
      let snapshot = scene()
      discard session.cycle(snapshot, snapshot.request())
      var replacement = scene(2)
      if sourceLoss:
        replacement.surfaces.setLen(1)
      else:
        replacement.outputs[1].generation = 2
      check session.cycle(replacement, replacement.changed(2)).presentation.isNone

  test "work area changes and lost focus eligibility revoke the modal selection":
    for workAreaChange in [true, false]:
      var session = initPolicySession()
      let snapshot = scene()
      discard session.cycle(snapshot, snapshot.request())
      var changedScene = scene(2)
      if workAreaChange:
        changedScene.outputs[0].workX = 10
        changedScene.outputs[0].workWidth = 1190
        changedScene.outputs[0].workHeight = 900
      else:
        changedScene.surfaces[0].capabilityBits = 0
      check session.cycle(changedScene, changedScene.changed(2)).presentation.isNone

  test "connection changes and checkpoint restoration never restore modal authority":
    var session = initPolicySession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.request())
    let checkpoint = session.committedAdapter().checkpointPayload()
    var restored = initPolicySession(checkpoint.restoreCheckpointPayload())
    check restored.cycle(snapshot, snapshot.changed(2)).presentation.isNone
    var reconnect = snapshot.changed(2)
    reconnect.connectionEpoch = 8
    check session.cycle(snapshot, reconnect).presentation.isNone

  test "revocation closes current publication but late receipts never revoke a successor":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session.cycle(snapshot, snapshot.request()).presentation.get()
    let receipt = PresentationReceipt(
      connectionEpoch: 7,
      publicationGeneration: publication.generation,
      output: 10,
      outputGeneration: 1,
      presentationEpoch: 9,
      outcome: PresentationOutcomeKind.revoked,
    )
    session.receivePresentationReceipt(receipt)
    check session.cycle(snapshot, snapshot.changed(2)).presentation.isNone
    let next = session.cycle(snapshot, snapshot.request(3)).presentation.get()
    session.receivePresentationReceipt(receipt)
    check session.cycle(snapshot, snapshot.changed(4)).presentation.get() == next
