import std/[options, sequtils, strutils, unittest]

import types/[actions, session, wm_v1, wm_presentation]
import policy/actions
import sophia/[policy_adapter, policy_session, policy_trace, wm_presentation]
import support/recent_windows_requests

## The recent-windows switcher through the adapter and session, as Sophia
## drives it. A plain invocation draws a modal Replace publication at once; a
## followed chord's ChordAction draws nothing until Sophia reports it held.

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

proc refuse(
    session: var PolicySession,
    snapshot: PolicySnapshot,
    request: ProjectionRequest,
    kind: ProjectionOutcomeKind,
) =
  discard session.prepare(snapshot, request, request.requestId)
  session.settle(
    ProjectionOutcome(
      connectionEpoch: request.connectionEpoch,
      requestId: request.requestId,
      transaction: request.requestId,
      sceneGeneration: request.sceneGeneration,
      kind: kind,
    )
  )

proc chordSession(): PolicySession =
  var adapter = initPolicyAdapter()
  adapter.setActionLifecycle(true)
  initPolicySession(adapter)

proc mode(projection: PolicyProjection): PresentationMode =
  projection.presentation.get().outputs[0].mode

proc selection(projection: PolicyProjection): uint32 =
  ## The source of the preview inside the emphasis.
  let publication = projection.presentation.get()
  let selected =
    publication.regions.filterIt(it.role == PresentationRegionRole.emphasis)
  doAssert selected.len == 1
  let around = selected[0].geometry
  for instance in publication.instances:
    let inner = instance.destination
    if inner.x >= around.x and inner.y >= around.y and
        inner.x + inner.width <= around.x + around.width and
        inner.y + inner.height <= around.y + around.height:
      return instance.sourceIndex
  doAssert false, "no preview is emphasized"

# Scene: windows 1..3, 3 focused, so the switcher offers 3, 1, 2 and opens on 1.

suite "recent-windows switcher on Sophia's chord lifecycle":
  test "held draws an overlay; joins step it; the released chord commits":
    var session = chordSession()
    let snapshot = scene()
    let opened = session.cycle(snapshot, snapshot.chordAction(1, 1))
    check opened.presentation.isNone
    check opened.focus() == 3
    let held = session.cycle(snapshot, snapshot.lifecycle(2, 1, 0))
    let publication = held.presentation.get()
    publication.validatePresentation()
    check publication.outputs[0].mode == PresentationMode.overlay
    check publication.keyboardOutput == 0
    check publication.bindings.len == 0
    check publication.instances.mapIt(it.sourceIndex) == @[3'u32, 1, 2]
    check held.selection() == 1
    # Two joins with their own activation serials and the opener's chord.
    check session.cycle(snapshot, snapshot.chordAction(3, 1)).selection() == 2
    check session.cycle(snapshot, snapshot.chordAction(4, 1)).selection() == 3
    let released = session.cycle(snapshot, snapshot.lifecycle(5, 2, 1, 3))
    check released.presentation.isNone
    check released.focus() == 3

  test "a quick tap switches with no strip":
    var session = chordSession()
    let snapshot = scene()
    check session.cycle(snapshot, snapshot.chordAction(1, 1)).presentation.isNone
    let released = session.cycle(snapshot, snapshot.lifecycle(2, 2, 1))
    check released.presentation.isNone
    check released.focus() == 1

  test "next and previous are separate chords sharing one switcher":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    discard session.cycle(snapshot, snapshot.chordAction(2, 1))
    let previous = snapshot.chordAction(3, 3, PolicyAction.recentWindowPrevious)
    check session.cycle(snapshot, previous).presentation.isNone
    # The previous chord's Held draws the strip it shares.
    let held = session.cycle(
      snapshot,
      snapshot.lifecycle(4, 1, 0, chord = 3, action = PolicyAction.recentWindowPrevious),
    )
    check held.mode() == PresentationMode.overlay
    check held.selection() == 1
    # The modifier ends both; the first Ended commits, the second is harmless.
    let committed = session.cycle(snapshot, snapshot.lifecycle(5, 2, 1, 2))
    check committed.focus() == 1
    var after = snapshot
    after.outputs[0].focusIndex = 1
    let late = session.cycle(
      after,
      after.lifecycle(6, 2, 1, chord = 3, action = PolicyAction.recentWindowPrevious),
    )
    check late.presentation.isNone
    check late.focus() == 1

  test "a join after its switcher closed does not reopen it":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    discard
      session.cycle(snapshot, snapshot.request(2, PolicyAction.recentWindowCancel))
    check session.cycle(snapshot, snapshot.chordAction(3, 1)).presentation.isNone
    # A plain invocation opens afresh on the previous window, not one step on.
    let opened =
      session.cycle(snapshot, snapshot.request(4, PolicyAction.recentWindowNext))
    check opened.mode() == PresentationMode.replaceApplications
    check opened.selection() == 1

  test "chords of closed switchers are forgotten, not accumulated":
    var session = chordSession()
    let snapshot = scene()
    for use in 1'u64 .. 12:
      discard session.cycle(snapshot, snapshot.chordAction(2 * use, 2 * use))
      discard session.cycle(
        snapshot, snapshot.request(2 * use + 1, PolicyAction.recentWindowCancel)
      )
    discard session.cycle(snapshot, snapshot.chordAction(100, 100))
    check session.cycle(snapshot, snapshot.lifecycle(101, 2, 1, chord = 100)).focus() ==
      1

  test "a chord ended otherwise closes the switcher without moving focus":
    for reason in [2'u16, 3, 4, 5]:
      var session = chordSession()
      let snapshot = scene()
      discard session.cycle(snapshot, snapshot.chordAction(1, 1))
      discard session.cycle(snapshot, snapshot.lifecycle(2, 1, 0))
      let ended = session.cycle(snapshot, snapshot.lifecycle(3, 2, reason))
      check ended.presentation.isNone
      check ended.focus() == 3

  test "a cancelled switcher's chord cannot act on a reopened one":
    # Chord 1 (one seat) opens the switcher and the operator cancels it with
    # its keys still down; chord 4 (another seat, same action) reopens it.
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    let cancelled =
      session.cycle(snapshot, snapshot.request(2, PolicyAction.recentWindowCancel))
    check cancelled.presentation.isNone
    check session.cycle(snapshot, snapshot.chordAction(4, 4)).presentation.isNone
    # The old chord's Held does not draw it early, its join does not step it,
    # and its release does not commit it.
    check session.cycle(snapshot, snapshot.lifecycle(5, 1, 0)).presentation.isNone
    check session.cycle(snapshot, snapshot.chordAction(6, 1)).presentation.isNone
    let oldEnd = session.cycle(snapshot, snapshot.lifecycle(7, 2, 1, 2))
    check oldEnd.presentation.isNone
    check oldEnd.focus() == 3
    let held = session.cycle(snapshot, snapshot.lifecycle(8, 1, 0, chord = 4))
    check held.mode() == PresentationMode.overlay
    check held.selection() == 1
    let released = session.cycle(snapshot, snapshot.lifecycle(9, 2, 1, chord = 4))
    check released.focus() == 1

  test "a plain invocation opens a modal switcher":
    var session = chordSession()
    let snapshot = scene()
    let opened =
      session.cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext))
    check opened.mode() == PresentationMode.replaceApplications
    check opened.presentation.get().bindings.anyIt(
      it.action == PolicyAction.recentWindowConfirm.raw()
    )

  test "a plain invocation steps a chord's switcher and owes no end of its own":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    # Still hidden until the chord's own Held.
    let stepped =
      session.cycle(snapshot, snapshot.request(2, PolicyAction.recentWindowNext))
    check stepped.presentation.isNone
    let held = session.cycle(snapshot, snapshot.lifecycle(3, 1, 0))
    check held.mode() == PresentationMode.overlay
    check held.selection() == 2
    let released = session.cycle(snapshot, snapshot.lifecycle(4, 2, 1))
    check released.presentation.isNone
    check released.focus() == 2

  test "a chord opening a modal switcher takes it over":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.request(1, PolicyAction.recentWindowNext))
    let claimed = session.cycle(snapshot, snapshot.chordAction(2, 2))
    check claimed.mode() == PresentationMode.overlay
    check claimed.selection() == 2
    check session.cycle(snapshot, snapshot.lifecycle(3, 2, 1, chord = 2)).focus() == 2

  test "chord causes the WM never negotiated or declared are refused":
    let snapshot = scene()
    for request in [snapshot.lifecycle(1, 1, 0), snapshot.chordAction(1, 1)]:
      var session = initPolicySession()
      expect PolicyAdapterError:
        discard session.cycle(snapshot, request)
    for request in [
      snapshot.chordAction(1, 1, PolicyAction.toggleOverview),
      snapshot.lifecycle(1, 1, 0, action = PolicyAction.toggleOverview),
      snapshot.lifecycle(1, 1, 1),
      snapshot.lifecycle(1, 2, 0),
      snapshot.lifecycle(1, 2, 6),
      snapshot.lifecycle(1, 3, 0),
      snapshot.lifecycle(1, 1, 0, count = 0),
      snapshot.chordAction(1, 0),
    ]:
      var session = chordSession()
      expect PolicyAdapterError:
        discard session.cycle(snapshot, request)
    var session = chordSession()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    var again = snapshot.chordAction(2, 1)
    again.cause.activationSerial = 1
    expect PolicyAdapterError:
      discard session.cycle(snapshot, again)

  test "a refused opener leaves its chord unknown":
    var session = chordSession()
    let snapshot = scene()
    session.refuse(
      snapshot, snapshot.chordAction(1, 1), ProjectionOutcomeKind.rejectedStale
    )
    check session.cycle(snapshot, snapshot.chordAction(2, 1)).presentation.isNone
    check session.cycle(snapshot, snapshot.lifecycle(3, 1, 0)).presentation.isNone
    check session.cycle(snapshot, snapshot.lifecycle(4, 2, 1)).focus() == 3

  test "a refused join changes nothing and the chord still commits":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    session.refuse(
      snapshot, snapshot.chordAction(2, 1), ProjectionOutcomeKind.rejectedInvalid
    )
    check session.cycle(snapshot, snapshot.lifecycle(3, 2, 1)).focus() == 1

  test "a refused Held leaves the switcher hidden and its chord still commits":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    session.refuse(
      snapshot, snapshot.lifecycle(2, 1, 0), ProjectionOutcomeKind.timedOut
    )
    check session.cycle(snapshot, snapshot.sceneChanged(3)).presentation.isNone
    check session.cycle(snapshot, snapshot.lifecycle(4, 2, 1)).focus() == 1

  test "a refused end retires its chord without promoting its candidate":
    for kind in [
      ProjectionOutcomeKind.rejectedStale, ProjectionOutcomeKind.rejectedInvalid,
      ProjectionOutcomeKind.timedOut, ProjectionOutcomeKind.disconnected,
    ]:
      var session = chordSession()
      let snapshot = scene()
      discard session.cycle(snapshot, snapshot.chordAction(1, 1))
      discard session.cycle(snapshot, snapshot.lifecycle(2, 1, 0))
      session.refuse(snapshot, snapshot.lifecycle(3, 2, 1), kind)
      let next = session.cycle(snapshot, snapshot.sceneChanged(4))
      check next.presentation.isNone
      check next.focus() == 3
      # The next ordinary use of the switcher starts afresh.
      let reopened = session.cycle(snapshot, snapshot.chordAction(5, 5))
      check reopened.presentation.isNone
      check session.cycle(snapshot, snapshot.lifecycle(6, 2, 1, chord = 5)).focus() == 1

  test "a refused end of a detached chord leaves the newer switcher":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    discard
      session.cycle(snapshot, snapshot.request(2, PolicyAction.recentWindowCancel))
    discard session.cycle(snapshot, snapshot.chordAction(3, 3))
    discard session.cycle(snapshot, snapshot.lifecycle(4, 1, 0, chord = 3))
    session.refuse(
      snapshot, snapshot.lifecycle(5, 2, 2), ProjectionOutcomeKind.rejectedStale
    )
    check session.cycle(snapshot, snapshot.sceneChanged(6)).mode() ==
      PresentationMode.overlay
    check session.cycle(snapshot, snapshot.lifecycle(7, 2, 1, chord = 3)).focus() == 1

  test "a new connection forgets the old one's chords":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    discard session.cycle(snapshot, snapshot.lifecycle(2, 1, 0))
    discard session.prepare(snapshot, snapshot.lifecycle(3, 2, 1), 3)
    session.abort()
    session.setActionLifecycle(true)
    let reconnected = session.cycle(snapshot, snapshot.sceneChanged(4, epoch = 8))
    check reconnected.presentation.isNone
    check reconnected.focus() == 3
    # Chord serials start over: serial 1 is a new chord, never the old one.
    var fresh = snapshot.chordAction(5, 1, epoch = 8)
    fresh.cause.activationSerial = 1
    check session.cycle(snapshot, fresh).presentation.isNone
    fresh = snapshot.lifecycle(6, 2, 1)
    fresh.connectionEpoch = 8
    check session.cycle(snapshot, fresh).focus() == 1

  test "a new connection closes a switcher its chords owned":
    var session = chordSession()
    let snapshot = scene()
    discard session.cycle(snapshot, snapshot.chordAction(1, 1))
    discard session.cycle(snapshot, snapshot.lifecycle(2, 1, 0))
    let next = session.cycle(snapshot, snapshot.sceneChanged(3, epoch = 8))
    check next.presentation.isNone
    check next.focus() == 3

proc replay(entries: openArray[PolicyTraceEntry]): seq[PolicyProjection] =
  ## As `hagia replay` does: each entry restores its connection context, then
  ## reduces and settles as committed.
  var session = initPolicySession()
  for entry in entries:
    session.setActionLifecycle(entry.actionLifecycle)
    let projection = session.prepare(entry.snapshot, entry.request, entry.transaction)
    session.settle(
      ProjectionOutcome(
        kind: ProjectionOutcomeKind.committed,
        connectionEpoch: entry.request.connectionEpoch,
        requestId: entry.request.requestId,
        transaction: entry.transaction,
        sceneGeneration: entry.snapshot.generation,
      )
    )
    result.add(projection)

suite "recent-windows switcher replay":
  test "a live-mode trace replays the hidden switcher and its held strip":
    let snapshot = scene()
    var entries: seq[PolicyTraceEntry]
    for request in [snapshot.chordAction(1, 1), snapshot.lifecycle(2, 1, 0)]:
      let recorded = PolicyTraceEntry(
        snapshot: snapshot,
        request: request,
        transaction: request.requestId,
        actionLifecycle: true,
      )
      entries.add(recorded.traceLine().parseTraceLine())
    check entries.allIt(it.actionLifecycle)
    let projections = entries.replay()
    check projections[0].presentation.isNone
    check projections[1].presentation.get().outputs[0].mode == PresentationMode.overlay

  test "a trace from before the lifecycle replays as the modal fallback":
    let snapshot = scene()
    let line = PolicyTraceEntry(
      snapshot: snapshot,
      request: snapshot.request(1, PolicyAction.recentWindowNext),
      transaction: 1,
    ).traceLine()
    let old = line.replace(""","actionLifecycle":false""", "")
    check "actionLifecycle" notin old
    let entry = old.parseTraceLine()
    check not entry.actionLifecycle
    check [entry].replay()[0].presentation.get().outputs[0].mode ==
      PresentationMode.replaceApplications
