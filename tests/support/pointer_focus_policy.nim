## Focus that follows the pointer: the profile switch, the cause that carries
## an Engine observation, and what the reducer does with it.
##
## Hagia never sees motion. Sophia hit-tests its own presented pixels and says
## which output the pointer settled on and, when there is one, which window.
## Everything here is about refusing a malformed or unnegotiated observation
## and about the setting deciding whether a well-formed one changes anything.

proc pointerFocusCandidate(generation: uint64, enabled: bool): AuthorityCandidate =
  AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: generation,
    digest: repeat('c', 64),
    values: @[
      ProfileValue(
        key: "policy.focus-follows-mouse",
        encoded: "focus-follows-mouse " & (if enabled: "#true" else: "#false"),
      )
    ],
  )

proc pointerFocusFrame(
    output: uint64,
    index: uint32 = 0,
    generation: uint32 = 0,
    serial: uint64 = 0,
    width: int32 = 0,
    affected: uint64 = 0,
): Frame =
  ## The wire shape the contract fixes: the output rides the action slot, the
  ## target pair is the only optional part, and every interaction slot is zero.
  var payload: seq[byte]
  payload.addU64(7)
  payload.addU64(1)
  payload.addU64(1)
  payload.addU64(1)
  payload.addU16(uint16(ord(ProjectionCauseKind.pointerFocus)))
  payload.addU16(0)
  payload.addU16(0)
  payload.addU16(0)
  payload.addU64(serial)
  payload.addU64(output)
  payload.addU32(index)
  payload.addU32(generation)
  payload.addU32(0)
  payload.addU32(0)
  payload.addU32(cast[uint32](width))
  payload.addU32(0)
  payload.addU16(1)
  payload.addU16(0)
  payload.addU64(if affected == 0: output else: affected)
  Frame(kind: MessageKind.projectionRequest, transaction: 1, payload: payload)

proc pointerFocusRequest(
    output: uint64, index: uint32 = 0, generation: uint32 = 0, requestId = 1'u64
): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 1,
    requestId: requestId,
    sceneGeneration: 1,
    policyGeneration: 1,
    affectedOutputs: @[10'u64, 20'u64],
    cause: ProjectionCause(
      kind: ProjectionCauseKind.pointerFocus,
      action: output,
      targetIndex: index,
      targetGeneration: generation,
    ),
  )

proc twoOutputScene(generation: uint64): PolicySnapshot =
  ## A window on the left output and nothing at all on the right, which is the
  ## case an empty-monitor crossing has to handle.
  result = snapshot(
    generation,
    @[
      SnapshotOutput(
        output: 10,
        generation: 1,
        width: 2560,
        height: 1440,
        focusIndex: 1,
        focusGeneration: 1,
      ),
      SnapshotOutput(output: 20, generation: 1, x: 2560, width: 1920, height: 1080),
    ],
    @[surface(1, 10)],
  )

suite "pointer focus":
  test "the cause is refused without its negotiated capability":
    ## An observation Hagia never agreed to receive is a protocol error, not
    ## something to ignore: the peer is sending a cause this connection did not
    ## admit, and carrying on would hide that.
    expect PolicyClientError:
      discard pointerFocusFrame(10).decodeProjectionRequest(7, 0)
    let request =
      pointerFocusFrame(10).decodeProjectionRequest(7, capabilityPointerFocus)
    check request.cause.kind == ProjectionCauseKind.pointerFocus
    check request.cause.action == 10
    check request.cause.targetIndex == 0
    check request.cause.targetGeneration == 0

  test "a target is present exactly when its generation is":
    ## Index zero is a valid surface index, so generation is what says a target
    ## is there. An index without a generation is the malformed case.
    let present =
      pointerFocusFrame(10, 0, 1).decodeProjectionRequest(7, capabilityPointerFocus)
    check present.cause.targetIndex == 0
    check present.cause.targetGeneration == 1
    let alsoPresent =
      pointerFocusFrame(10, 4, 2).decodeProjectionRequest(7, capabilityPointerFocus)
    check alsoPresent.cause.targetIndex == 4
    expect PolicyClientError:
      discard
        pointerFocusFrame(10, 4, 0).decodeProjectionRequest(7, capabilityPointerFocus)

  test "a malformed observation is refused":
    for frame in [
      pointerFocusFrame(0), # no output
      pointerFocusFrame(10, 0, 0, 5), # an activation serial it must not carry
      pointerFocusFrame(10, 0, 0, 0, 64), # geometry belongs to interactions
      pointerFocusFrame(10, 0, 0, 0, 0, 20), # an output this cycle cannot change
      pointerFocusFrame(10, high(uint32), 1), # not a surface identity
    ]:
      expect PolicyClientError:
        discard frame.decodeProjectionRequest(7, capabilityPointerFocus)

  test "enabled, the pointer moves focus between windows and onto empty outputs":
    var adapter = initPolicyAdapter(pointerFocusCandidate(2, true))
    adapter.reconcile(twoOutputScene(1))
    let left = adapter.logicalOutput(10).get()
    let right = adapter.logicalOutput(20).get()
    let window = adapter.logicalWindow(1, 1).get()
    check adapter.model().settings.focusFollowsMouse

    # Onto the window on the left output.
    adapter.applyCause(pointerFocusRequest(10, 1, 1))
    check adapter.model().activeOutput == left
    check adapter.model().outputs[left].focusedWindow == window

    # Onto the right output, which holds nothing. The active output moves and
    # the left output keeps remembering what it had focused.
    adapter.applyCause(pointerFocusRequest(20, requestId = 2))
    check adapter.model().activeOutput == right
    check adapter.model().outputs[right].focusedWindow == nullWindowId
    check adapter.model().outputs[left].focusedWindow == window
    adapter.model().validate()

  test "disabled, a well-formed observation changes nothing":
    ## The default. The cause is accepted and reduced; the reducer declines to
    ## act on it, and active output, focus, and camera all stay where the last
    ## committed cycle left them.
    var adapter = initPolicyAdapter(pointerFocusCandidate(2, false))
    adapter.reconcile(twoOutputScene(1))
    let before = adapter.checkpointPayload()
    adapter.applyCause(pointerFocusRequest(20))
    adapter.applyCause(pointerFocusRequest(10, 1, 1, 2))
    check adapter.checkpointPayload() == before
    adapter.model().validate()

  test "an unknown output or a target on another output is refused":
    var adapter = initPolicyAdapter(pointerFocusCandidate(2, true))
    adapter.reconcile(twoOutputScene(1))
    expect PolicyAdapterError:
      adapter.applyCause(pointerFocusRequest(30))
    # Surface 1 lives on output 10, so naming it against output 20 is a stale
    # observation rather than a focus change.
    expect PolicyAdapterError:
      adapter.applyCause(pointerFocusRequest(20, 1, 1))

  test "a hover onto a window that cannot take focus is refused":
    ## The Engine hit-tests presented pixels, which is not the same question as
    ## whether policy may focus what it found. Eligibility is the entity
    ## layer's to answer, so the reducer asks it rather than trusting the
    ## observation: a panel, a minimized window, or one whose tags the active
    ## view does not select all refuse here.
    var adapter = initPolicyAdapter(pointerFocusCandidate(2, true))
    var unfocusable = surface(2, 10)
    unfocusable.capabilityBits = 31 xor 4
    var minimized = surface(3, 10)
    minimized.currentStateBits = 4
    var scene = twoOutputScene(1)
    scene.surfaces.add(@[unfocusable, minimized])
    adapter.reconcile(scene)
    let settled = adapter.checkpointPayload()

    for index in [2'u32, 3'u32]:
      expect PolicyStateError:
        adapter.applyCause(pointerFocusRequest(10, index, 1))
    # A refused observation is a refused cycle, so nothing moved.
    check adapter.checkpointPayload() == settled
    adapter.model().validate()

  test "a rejected cycle leaves the committed strip alone":
    var session = initPolicySession(initPolicyAdapter(pointerFocusCandidate(2, true)))
    let scene = twoOutputScene(1)
    let before = session.committedAdapter().checkpointPayload()
    discard session.prepare(scene, pointerFocusRequest(20), 1)
    session.settle(
      ProjectionOutcome(
        transaction: 1,
        connectionEpoch: 1,
        requestId: 1,
        sceneGeneration: 1,
        kind: ProjectionOutcomeKind.rejectedStale,
      )
    )
    check session.committedAdapter().checkpointPayload() == before

    # The same observation, committed, is the one that lands.
    discard session.prepare(scene, pointerFocusRequest(20, requestId = 2), 2)
    session.settle(
      ProjectionOutcome(
        transaction: 2,
        connectionEpoch: 1,
        requestId: 2,
        sceneGeneration: 1,
        kind: ProjectionOutcomeKind.committed,
      )
    )
    check session.committedAdapter().model().activeOutput ==
      session.committedAdapter().logicalOutput(20).get()

  test "the setting survives a checkpoint and a reload turns it off":
    var adapter = initPolicyAdapter(pointerFocusCandidate(2, true))
    adapter.reconcile(twoOutputScene(1))
    var restored = adapter.checkpointPayload().restoreCheckpointPayload()
    check restored.model().settings.focusFollowsMouse
    restored.reconcile(twoOutputScene(2))
    check restored.model().settings.focusFollowsMouse

    # A reload that turns it off leaves the observation inert without any
    # further ceremony.
    restored.applyPolicyCandidate(pointerFocusCandidate(3, false))
    check not restored.model().settings.focusFollowsMouse
    let settled = restored.checkpointPayload()
    restored.applyCause(pointerFocusRequest(20))
    check restored.checkpointPayload() == settled

  test "a checkpoint written before the setting existed restores it off":
    var adapter = initPolicyAdapter(pointerFocusCandidate(2, true))
    adapter.reconcile(twoOutputScene(1))
    var payload = parseJson(adapter.checkpointPayload().dumpCheckpointJson())
    payload["schema"] = %12
    payload["settings"].delete("focusFollowsMouse")
    let restored = restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-12\n" & $payload)
    check not restored.model().settings.focusFollowsMouse
    check restored.checkpointPayload().startsWith("HAGIA-POLICY-CHECKPOINT-14\n")
