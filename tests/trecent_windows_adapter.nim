import std/[options, sequtils, unittest]

import types/[actions, session, wm_v1, wm_presentation]
import policy/actions
import sophia/[policy_adapter, policy_session, wm_presentation]

## The recent-windows switcher through the adapter and session, as Sophia
## drives it. Without the chord lifecycle the strip is a modal Replace
## publication; with it nothing is drawn until Sophia reports the chord held.

proc scene(): PolicySnapshot =
  ## Three windows on one output; the third is focused.
  result = PolicySnapshot(
    generation: 1,
    activeOutput: 10,
    outputs: @[
      SnapshotOutput(
        output: 10,
        generation: 1,
        width: 1920,
        height: 1080,
        focusIndex: 3,
        focusGeneration: 1,
      )
    ],
  )
  for index in 1'u32 .. 3:
    result.surfaces.add(
      SnapshotSurface(
        surfaceIndex: index,
        surfaceGeneration: 1,
        stateGeneration: 1,
        currentOutput: 10,
        capabilityBits: 31,
        width: 800,
        height: 600,
      )
    )

proc twoOutputs(active: uint64, leftFocus: uint32): PolicySnapshot =
  ## Left (10) holds a (1) and c (3); right (20) holds b (2) and keeps it
  ## focused. Both outputs report a focus, as Sophia's snapshots do.
  result = PolicySnapshot(generation: 1, activeOutput: active)
  for (output, x, focus) in [(10'u64, 0'i32, leftFocus), (20'u64, 1920'i32, 2'u32)]:
    result.outputs.add(
      SnapshotOutput(
        output: output,
        generation: 1,
        x: x,
        width: 1920,
        height: 1080,
        focusIndex: focus,
        focusGeneration: 1,
      )
    )
  for (index, output) in [(1'u32, 10'u64), (2'u32, 20'u64), (3'u32, 10'u64)]:
    result.surfaces.add(
      SnapshotSurface(
        surfaceIndex: index,
        surfaceGeneration: 1,
        stateGeneration: 1,
        currentOutput: output,
        capabilityBits: 31,
        width: 800,
        height: 600,
      )
    )

proc request(
    snapshot: PolicySnapshot, id: uint64, action: PolicyAction
): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 7,
    requestId: id,
    sceneGeneration: snapshot.generation,
    policyGeneration: 1,
    affectedOutputs: @[10'u64],
    cause: ProjectionCause(
      kind: ProjectionCauseKind.action, activationSerial: id, action: action.raw()
    ),
  )

proc cycle(
    session: var PolicySession, snapshot: PolicySnapshot, request: ProjectionRequest
): PolicyProjection =
  result = session.prepare(snapshot, request, request.requestId)
  session.settle(
    ProjectionOutcome(
      connectionEpoch: request.connectionEpoch,
      requestId: request.requestId,
      transaction: request.requestId,
      sceneGeneration: request.sceneGeneration,
      kind: ProjectionOutcomeKind.committed,
    )
  )

proc presented(
    publication: WmPresentation,
    snapshot: PolicySnapshot,
    id: uint64,
    action: PolicyAction,
    target = SurfaceInstance(),
): ProjectionRequest =
  result = snapshot.request(id, action)
  result.cause.kind = ProjectionCauseKind.presentationAction
  result.cause.presentation = PresentationIdentity(
    publicationGeneration: publication.generation,
    output: 10,
    outputGeneration: 1,
    presentationEpoch: 9,
    targetId: target.id,
    targetGeneration: target.generation,
  )

proc focus(projection: PolicyProjection): uint32 =
  projection.outputs[0].output.focusIndex

suite "recent-windows switcher presentation":
  test "without the chord lifecycle the switcher is a modal strip":
    var session = initPolicySession()
    let snapshot = scene()
    let opened =
      session.cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext))
    let publication = opened.presentation.get()
    publication.validatePresentation()
    check publication.outputs.len == 1
    check publication.outputs[0].mode == PresentationMode.replaceApplications
    check publication.keyboardOutput == 10
    check publication.instances.mapIt(it.sourceIndex) == @[3'u32, 1, 2]
    check publication.instances.allIt(
      it.action == PolicyAction.recentWindowConfirm.raw() and it.destination.width < 800
    )
    check publication.regions.anyIt(it.role == PresentationRegionRole.emphasis)
    # Capture matches modifiers exactly, so every chord the operator may still
    # hold must step, confirm, or cancel rather than be swallowed.
    proc bound(keycode, modifiers: uint32): uint64 =
      for binding in publication.bindings:
        if binding.keycode == keycode and binding.modifiers == modifiers:
          return binding.action

    check publication.bindings.len == 96
    check publication.bindings.mapIt((it.keycode, it.modifiers)).deduplicate().len == 96
    check bound(15, 2) == PolicyAction.recentWindowNext.raw()
    check bound(15, 5) == PolicyAction.recentWindowPrevious.raw()
    check bound(15, 15) == PolicyAction.recentWindowPrevious.raw()
    check bound(28, 4) == PolicyAction.recentWindowConfirm.raw()
    check bound(1, 4) == PolicyAction.recentWindowCancel.raw()
    check opened.focus() == 3

  test "a keyboard confirm commits the selection and withdraws the strip":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session
      .cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext)).presentation
      .get()
    let confirmed = session.cycle(
      snapshot, publication.presented(snapshot, 2, PolicyAction.recentWindowConfirm)
    )
    check confirmed.presentation.isNone
    check confirmed.focus() == 1

  test "a click on a preview commits that window":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session
      .cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext)).presentation
      .get()
    let target = publication.instances.filterIt(it.sourceIndex == 2)[0]
    let clicked = session.cycle(
      snapshot,
      publication.presented(snapshot, 2, PolicyAction.recentWindowConfirm, target),
    )
    check clicked.presentation.isNone
    check clicked.focus() == 2

  test "a stale target cannot change policy":
    var session = initPolicySession()
    let snapshot = scene()
    let publication = session
      .cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext)).presentation
      .get()
    var target = publication.instances[0]
    target.generation += 1
    expect PolicyAdapterError:
      discard session.cycle(
        snapshot,
        publication.presented(snapshot, 2, PolicyAction.recentWindowConfirm, target),
      )

  test "with the chord lifecycle nothing is drawn before the chord is held":
    var adapter = initPolicyAdapter()
    adapter.setActionLifecycle(true)
    var session = initPolicySession(adapter)
    let snapshot = scene()
    let opened =
      session.cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext))
    check opened.presentation.isNone
    check opened.focus() == 3

  test "another action closes the switcher":
    var session = initPolicySession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext))
    let overview =
      session.cycle(snapshot, snapshot.request(2, PolicyAction.toggleOverview))
    let publication = overview.presentation.get()
    check publication.bindings.anyIt(it.action == PolicyAction.closeOverview.raw())
    check not publication.bindings.anyIt(
      it.action == PolicyAction.recentWindowConfirm.raw()
    )

  test "restoring each output's focus does not reorder the recent windows":
    # The operator works in b on the right, then focuses a on the left. Every
    # later snapshot still reports both outputs' focus, left first; the
    # previous window must stay b, not the never-used c beside a.
    var session = initPolicySession()
    let onRight = twoOutputs(20, 3)
    discard session.cycle(onRight, onRight.request(1, PolicyAction.recentWindowCancel))
    var focusA = onRight.request(2, PolicyAction.recentWindowCancel)
    focusA.cause = ProjectionCause(
      kind: ProjectionCauseKind.focus, targetIndex: 1, targetGeneration: 1
    )
    discard session.cycle(onRight, focusA)
    let onLeft = twoOutputs(10, 1)
    let opened = session.cycle(onLeft, onLeft.request(3, PolicyAction.recentWindowNext))
    let publication = opened.presentation.get()
    check publication.instances.mapIt(it.sourceIndex) == @[1'u32, 2, 3]
    var confirm = publication.presented(onLeft, 4, PolicyAction.recentWindowConfirm)
    confirm.affectedOutputs = @[10'u64, 20]
    let confirmed = session.cycle(onLeft, confirm)
    check confirmed.presentation.isNone
    check confirmed.activeOutput == 20
    check confirmed.outputs.filterIt(it.output.output == 20)[0].output.focusIndex == 2
