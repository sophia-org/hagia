## A profile reload that changes only a gap, across two outputs whose columns
## carry different widths, taken through the checkpoint the running session
## actually writes.
##
## A reload rebuilds policy settings from the candidate and reconciles them
## against live logical state. Everything a strip carries that the profile does
## not state -- a column's width preference, its place in the order, which
## window holds focus, where the camera is looking -- has to survive a value
## the reload did change. The round trip is what makes that checkable: going
## 8 -> 9 -> 8 has to land on exactly the geometry it started from, because a
## preference quietly rebuilt from a default reappears as a different placement
## on the way back, and nothing else in a gap change would move it.
##
## The path here is the one `policy_client.nim` runs, not a shortcut through
## the model: every step is a prepared candidate that Sophia commits, the
## checkpoint is written from the committed adapter and read back from disk,
## and the new candidate is applied to what was read.

proc gapCandidate(generation: uint64, outerGap: int): AuthorityCandidate =
  ## What a profile stating only gaps produces. Every other setting returns to
  ## the compiled default, which is what a reload does to them.
  AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: generation,
    digest: repeat('b', 64),
    values: @[
      ProfileValue(key: "policy.outer-gap", encoded: "outer-gap " & $outerGap),
      ProfileValue(key: "policy.inner-gap", encoded: "inner-gap 8"),
    ],
  )

proc reloadScene(
    generation: uint64,
    active: uint64 = 10,
    leftFocus: uint32 = 1,
    rightFocus: uint32 = 4,
    rightFirst = false,
): PolicySnapshot =
  ## Two outputs side by side, three surfaces on the left and two on the right.
  ##
  ## The Engine states which window each output has focused and which output is
  ## active, and both matter here: reconciliation clears the focus of any
  ## output whose snapshot record carries none, so a scene that omitted it
  ## would settle into a strip with nothing focused and every width action
  ## would quietly do nothing. The identities are synthetic opaque handles.
  let left = SnapshotOutput(
    output: 10,
    generation: 1,
    width: 2560,
    height: 1440,
    focusIndex: leftFocus,
    focusGeneration: 1,
  )
  let right = SnapshotOutput(
    output: 20,
    generation: 1,
    x: 2560,
    width: 1920,
    height: 1080,
    focusIndex: rightFocus,
    focusGeneration: 1,
  )
  result = snapshot(
    generation,
    if rightFirst:
      @[right, left]
    else:
      @[left, right],
    @[surface(1, 10), surface(2, 10), surface(3, 10), surface(4, 20), surface(5, 20)],
  )
  result.activeOutput = active

proc actionCause(action: PolicyAction): ProjectionCause =
  ProjectionCause(
    kind: ProjectionCauseKind.action, activationSerial: 1, action: action.raw()
  )

proc runCommittedCycle(
    session: var PolicySession,
    scene: PolicySnapshot,
    transaction: uint64,
    cause = ProjectionCause(),
): PolicyProjection =
  ## One complete settlement: prepare a candidate, have Sophia commit it,
  ## promote. A projection is only policy after the commit, so nothing here
  ## reads the candidate directly.
  let request = ProjectionRequest(
    connectionEpoch: 1,
    requestId: transaction,
    sceneGeneration: scene.generation,
    policyGeneration: 1,
    affectedOutputs: @[10'u64, 20'u64],
    cause: cause,
  )
  result = session.prepare(scene, request, transaction)
  session.settle(
    ProjectionOutcome(
      transaction: transaction,
      connectionEpoch: 1,
      requestId: transaction,
      sceneGeneration: scene.generation,
      kind: ProjectionOutcomeKind.committed,
    )
  )

proc columnPreferences(
    model: PolicyModel, output: OutputId
): seq[(ColumnId, Scale, bool)] =
  ## The strip's order and what each column asked for. A reload may move where
  ## these land; it may not change what they are.
  for columnId in model.tiledColumnIds(output):
    result.add(
      (columnId, model.columns[columnId].widthScale, model.columns[columnId].fullWidth)
    )

proc committedMixedWidthSession(): PolicySession =
  ## Three columns on the left output at three different widths and two on the
  ## right, each step committed. The scene states the focus each step acts on,
  ## which is what the Engine does.
  result = initPolicySession(initPolicyAdapter(gapCandidate(1, 8)))
  let steps = [
    (10'u64, 2'u32, 4'u32, PolicyAction.cycleColumnWidth),
    (10'u64, 3'u32, 4'u32, PolicyAction.growColumn),
    (20'u64, 3'u32, 5'u32, PolicyAction.cycleColumnWidthBack),
  ]
  var transaction = 0'u64
  for step in steps:
    inc transaction
    discard result.runCommittedCycle(
      reloadScene(transaction, step[0], step[1], step[2]),
      transaction,
      actionCause(step[3]),
    )

proc reloadWithGap(
    session: PolicySession, path: string, outerGap: int, generation: uint64
): PolicySession =
  ## What a restarted Hagia does with a changed gap, in the order
  ## `policy_client.nim` does it: write the committed checkpoint, read it back
  ## from disk, apply the new candidate to what was read, open a session on it.
  path.savePolicyCheckpoint(session.committedAdapter())
  var candidate = path.loadPolicyCheckpoint().get()
  candidate.applyPolicyCandidate(gapCandidate(generation, outerGap))
  initPolicySession(candidate)

proc leftEdge(projection: PolicyProjection, output: uint64): int32 =
  ## The left edge of the leftmost placement an output shows. With the camera
  ## at the strip origin this is the first column's edge, and it is the one
  ## coordinate a gap change is meant to move.
  result = high(int32)
  for entry in projection.outputs:
    if entry.output.output == output:
      for placement in entry.placements:
        result = min(result, placement.x)

suite "scroller reload across two outputs":
  test "an action reduces against the output the Engine says is active":
    ## `setFocus` makes its own output active, so restoring every output's
    ## focus during reconciliation walks the active output to whichever one the
    ## snapshot happened to list last. Sophia names the active output; a width
    ## action has to land there whatever order the outputs arrive in.
    for rightFirst in [false, true]:
      for active in [10'u64, 20'u64]:
        var session = initPolicySession(initPolicyAdapter(gapCandidate(1, 8)))
        discard session.runCommittedCycle(reloadScene(1, active, 1, 4, rightFirst), 1)
        let committed = session.committedAdapter()
        let left = committed.logicalOutput(10).get()
        let right = committed.logicalOutput(20).get()
        let before = committed.model()
        discard session.runCommittedCycle(
          reloadScene(2, active, 1, 4, rightFirst),
          2,
          actionCause(PolicyAction.cycleColumnWidth),
        )
        let after = session.committedAdapter().model()
        let acted = (if active == 10: left else: right)
        let untouched = (if active == 10: right else: left)
        check after.columnPreferences(acted) != before.columnPreferences(acted)
        check after.columnPreferences(untouched) == before.columnPreferences(untouched)
        after.validate()

  test "a committed gap round trip moves the gap and nothing else":
    let directory = createTempDir("hagia-scroller-reload-", "")
    defer:
      removeDir(directory)
    let path = directory / "policy.checkpoint"
    var session = committedMixedWidthSession()
    let scene = reloadScene(9)
    let left = session.committedAdapter().logicalOutput(10).get()
    let right = session.committedAdapter().logicalOutput(20).get()

    let atEight = session.runCommittedCycle(scene, 9)
    let preferencesBefore = (
      session.committedAdapter().model().columnPreferences(left),
      session.committedAdapter().model().columnPreferences(right),
    )
    # The fixture has to carry genuinely different widths, or the round trip
    # below would be preserving one value three times over.
    check preferencesBefore[0].len == 3
    check preferencesBefore[1].len == 2
    check not (
      preferencesBefore[0][0][1] == preferencesBefore[0][1][1] and
      preferencesBefore[0][1][1] == preferencesBefore[0][2][1]
    )
    let focusBefore = (
      session.committedAdapter().model().outputs[left].focusedWindow,
      session.committedAdapter().model().outputs[right].focusedWindow,
    )
    let model = session.committedAdapter().model()
    let cameraBefore = (
      model.views[model.outputs[left].activeView].camera,
      model.views[model.outputs[right].activeView].camera,
    )

    # A committed projection repeated against an unchanged scene is the same
    # projection. The camera is written back by the first one, so a second that
    # moved would mean the strip never settles while nothing happens to it.
    check session.runCommittedCycle(scene, 10) == atEight

    # The right strip's columns fit, so its first column sits one outer gap and
    # one inner gap in from the output and the gap is legible as a literal
    # coordinate. The left strip is centred on its focused column, so there a
    # gap change means a shift rather than an absolute edge.
    check atEight.leftEdge(20) == 2560 + 16
    let centredAtEight = atEight.leftEdge(10)

    session = session.reloadWithGap(path, 9, 2)
    let atNine = session.runCommittedCycle(scene, 11)
    check atNine != atEight
    check atNine.leftEdge(20) == 2560 + 17
    check atNine.leftEdge(10) == centredAtEight + 1
    # A wider gap moves placements. It does not add, drop, or reorder them, and
    # it does not move focus.
    check atNine.outputs.len == atEight.outputs.len
    for index, entry in atNine.outputs:
      check entry.output.output == atEight.outputs[index].output.output
      check entry.output.focusIndex == atEight.outputs[index].output.focusIndex
      check entry.placements.len == atEight.outputs[index].placements.len
      for slot, placement in entry.placements:
        check placement.surfaceIndex ==
          atEight.outputs[index].placements[slot].surfaceIndex

    session = session.reloadWithGap(path, 8, 3)
    check session.runCommittedCycle(scene, 12) == atEight
    let after = session.committedAdapter().model()
    check after.columnPreferences(left) == preferencesBefore[0]
    check after.columnPreferences(right) == preferencesBefore[1]
    check after.outputs[left].focusedWindow == focusBefore[0]
    check after.outputs[right].focusedWindow == focusBefore[1]
    check after.views[after.outputs[left].activeView].camera == cameraBefore[0]
    check after.views[after.outputs[right].activeView].camera == cameraBefore[1]
    after.validate()

  test "a checkpoint restored with a scrolled camera keeps the same strip":
    let directory = createTempDir("hagia-scroller-restore-", "")
    defer:
      removeDir(directory)
    let path = directory / "policy.checkpoint"
    var session = committedMixedWidthSession()

    # Scroll the left strip off its origin before saving. A camera preserved at
    # zero would be preserved by doing nothing, so the case has to carry one
    # that is not.
    let scene = reloadScene(9, 10, 3, 4)
    let scrolled = session.runCommittedCycle(scene, 9)
    let committed = session.committedAdapter()
    let before = committed.model()
    let left = committed.logicalOutput(10).get()
    let right = committed.logicalOutput(20).get()
    let leftView = before.outputs[left].activeView
    # A strip resting at its origin still carries a nonzero offset, so scrolled
    # has to mean a positive one anchored on the column that was focused --
    # otherwise the preservation checks below would pass on an unmoved camera.
    let scrolledWindow = committed.logicalWindow(3, 1).get()
    check before.views[leftView].viewportOffset > 0
    check before.views[leftView].camera.column == before.windows[scrolledWindow].column

    path.savePolicyCheckpoint(session.committedAdapter())
    var restored = initPolicySession(path.loadPolicyCheckpoint().get())

    # Reconciliation runs inside prepare, so this cycle is the restart's first
    # complete settlement against a live scene.
    check restored.runCommittedCycle(scene, 10) == scrolled
    let after = restored.committedAdapter().model()
    check restored.committedAdapter().logicalOutput(10) == some(left)
    check restored.committedAdapter().logicalOutput(20) == some(right)
    for index in 1'u32 .. 5'u32:
      check restored.committedAdapter().logicalWindow(index, 1) ==
        committed.logicalWindow(index, 1)
    check after.columnPreferences(left) == before.columnPreferences(left)
    check after.columnPreferences(right) == before.columnPreferences(right)
    check after.outputs[left].focusedWindow == before.outputs[left].focusedWindow
    check after.outputs[right].focusedWindow == before.outputs[right].focusedWindow
    check after.views[after.outputs[left].activeView].viewportOffset ==
      before.views[leftView].viewportOffset
    check after.views[after.outputs[left].activeView].camera ==
      before.views[leftView].camera
    after.validate()

    # A checkpoint that is not one is refused rather than half-trusted.
    writeFile(path, "not a checkpoint")
    expect PolicyCheckpointError:
      discard path.loadPolicyCheckpoint()

  test "legacy to uniform migration and gap reload retain both outputs' column choices":
    var session = committedMixedWidthSession()
    let scene = reloadScene(9)
    discard session.runCommittedCycle(scene, 9)
    let committed = session.committedAdapter()
    let left = committed.logicalOutput(10).get()
    let right = committed.logicalOutput(20).get()
    let before = committed.model()
    var transaction = 10'u64
    var atEight: PolicyProjection
    for gap in [8, 9, 8]:
      var restored =
        restoreCheckpointPayload(session.committedAdapter().checkpointPayload())
      restored.applyPolicyCandidate(
        AuthorityCandidate(
          authority: ProfileAuthority.policy,
          generation: transaction,
          digest: repeat('c', 64),
          values: @[ProfileValue(key: "policy.gaps", encoded: "gaps " & $gap)],
        )
      )
      session = initPolicySession(restored)
      let projected = session.runCommittedCycle(scene, transaction)
      inc transaction
      check session.runCommittedCycle(scene, transaction) == projected
      inc transaction
      let after = session.committedAdapter().model()
      for output in [left, right]:
        check after.columnPreferences(output) == before.columnPreferences(output)
        check after.outputs[output].focusedWindow == before.outputs[output].focusedWindow
        check after.views[after.outputs[output].activeView].camera.column ==
          before.views[before.outputs[output].activeView].camera.column
      if transaction == 12:
        atEight = projected
      elif gap == 8:
        # niri's fit rule keeps a column still when the smaller padding fits.
        # The right camera retains its nine-pixel inset; pane sizes return to
        # eight-pixel geometry without forcing an unnecessary camera move.
        for outputIndex, output in projected.outputs:
          for index, placement in output.placements:
            let original = atEight.outputs[outputIndex].placements[index]
            check placement.surfaceIndex == original.surfaceIndex
            check placement.width == original.width
            check placement.height == original.height
            check placement.y == original.y
            check placement.x == original.x + (if output.output.output == 20: 1 else: 0)
      else:
        check projected != atEight
      check projected.leftEdge(20) == (if transaction == 12: 2568 else: 2569)
      after.validate()
