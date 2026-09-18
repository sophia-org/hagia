## Launching an application from another one.
##
## Hagia publishes an opaque token for every live managed window, standing for
## the place that window occupies rather than for the window itself. Sophia
## freezes one when a child connects and echoes it back when the child's first
## surface appears. Hagia never learns what launched what; it only recognises a
## token it minted and opens the new window where that token points.

proc toplevel(index: uint32, output: uint64): SnapshotSurface =
  ## Surface kind 1 is a managed top-level. The default zero is unknown, which
  ## deliberately publishes no context.
  result = surface(index, output)
  result.kind = 1

proc originRequest(
    requestId: uint64, generation: uint64, outputs: seq[uint64]
): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 1,
    requestId: requestId,
    sceneGeneration: generation,
    policyGeneration: 1,
    affectedOutputs: outputs,
  )

proc originScene(generation: uint64, surfaces: seq[SnapshotSurface]): PolicySnapshot =
  snapshot(
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
    surfaces,
  )

proc contextFor(
    contexts: seq[LaunchOriginRecord], index: uint32
): Option[LaunchOriginRecord] =
  for record in contexts:
    if record.surfaceIndex == index:
      return some(record)
  none(LaunchOriginRecord)

proc originRecord(index: uint32, token: uint64, epoch = 1'u64): LaunchOriginRecord =
  LaunchOriginRecord(
    surfaceIndex: index, surfaceGeneration: 1, epoch: epoch, token: token
  )

suite "launch origin":
  test "a context is published for every live managed window, hidden ones too":
    ## The case this exists for is a launcher on a view the operator has since
    ## left: the child still belongs where the launcher lives, so a context
    ## limited to what is on screen would lose exactly the launches that need it.
    var adapter = initPolicyAdapter()
    adapter.reconcile(originScene(1, @[toplevel(1, 10), toplevel(2, 10)]))
    check adapter.logicalWindow(2, 1).isSome

    let projection = adapter.projection(
      originScene(1, @[toplevel(1, 10), toplevel(2, 10)]),
      originRequest(1, 1, @[10'u64, 20'u64]),
    )
    check projection.launchContexts.len == 2
    for record in projection.launchContexts:
      check record.epoch == 1
      check record.token != 0
      check record.surfaceGeneration == 1

  test "windows sharing a place share a token":
    var adapter = initPolicyAdapter()
    let scene = originScene(1, @[toplevel(1, 10), toplevel(2, 10)])
    adapter.reconcile(scene)
    let contexts =
      adapter.projection(scene, originRequest(1, 1, @[10'u64])).launchContexts
    check contexts.contextFor(1).get().token == contexts.contextFor(2).get().token

  test "an echoed token opens the child where the launcher lives, quietly":
    var adapter = initPolicyAdapter()
    var scene = originScene(1, @[toplevel(1, 10)])
    scene.activeOutput = 10
    adapter.reconcile(scene)
    let left = adapter.logicalOutput(10).get()
    let right = adapter.logicalOutput(20).get()

    # The launcher is moved to the second output and a context is published.
    var moved = originScene(2, @[toplevel(1, 20)])
    moved.activeOutput = 10
    adapter.reconcile(moved)
    let contexts =
      adapter.projection(moved, originRequest(1, 2, @[10'u64, 20'u64])).launchContexts
    let token = contexts.contextFor(1).get().token
    let sourceTags = adapter.model().windowTagIds(adapter.logicalWindow(1, 1).get())

    # The operator has gone back to the first output. The child still opens
    # where its launcher is, and nothing follows it there.
    var admission = originScene(3, @[toplevel(1, 20), toplevel(2, 0)])
    admission.activeOutput = 10
    admission.launchOrigins = @[originRecord(2, token)]
    adapter.reconcile(admission)
    let child = adapter.logicalWindow(2, 1).get()
    check adapter.model().windows[child].homeOutput == right
    check adapter.model().windowTagIds(child) == sourceTags
    check adapter.model().activeOutput == left
    check adapter.model().outputs[right].focusedWindow != child
    adapter.model().validate()

  test "a token the cache no longer knows places the window ordinarily":
    var adapter = initPolicyAdapter()
    var scene = originScene(1, @[toplevel(1, 10)])
    adapter.reconcile(scene)
    discard adapter.projection(scene, originRequest(1, 1, @[10'u64]))

    var admission = originScene(2, @[toplevel(1, 10), toplevel(2, 10)])
    admission.launchOrigins = @[originRecord(2, 999_999'u64)]
    adapter.reconcile(admission)
    check adapter.logicalWindow(2, 1).isSome
    adapter.model().validate()

  test "a malformed or duplicate echo is refused":
    var adapter = initPolicyAdapter()
    var scene = originScene(1, @[toplevel(1, 10)])
    adapter.reconcile(scene)
    discard adapter.projection(scene, originRequest(1, 1, @[10'u64]))
    let token = 1'u64

    for records in [
      @[originRecord(high(uint32), token)], # not a surface identity
      @[
        LaunchOriginRecord(
          surfaceIndex: 2, surfaceGeneration: 0, epoch: 1, token: token
        )
      ],
      @[LaunchOriginRecord(surfaceIndex: 2, surfaceGeneration: 1, epoch: 1, token: 0)],
      @[originRecord(2, token, 7)], # another connection's token space
      @[originRecord(2, token), originRecord(2, token)], # one surface twice
    ]:
      var admission = originScene(2, @[toplevel(1, 10), toplevel(2, 10)])
      admission.launchOrigins = records
      var candidate = adapter.clone()
      expect PolicyClientError:
        candidate.reconcile(admission)

  test "an explicit classification outranks the origin":
    var adapter = initPolicyAdapter()
    var scene = originScene(1, @[toplevel(1, 20)])
    scene.activeOutput = 10
    adapter.reconcile(scene)
    let contexts =
      adapter.projection(scene, originRequest(1, 1, @[10'u64, 20'u64])).launchContexts
    let token = contexts.contextFor(1).get().token

    var admission = originScene(2, @[toplevel(1, 20), toplevel(2, 0)])
    admission.activeOutput = 10
    admission.launchOrigins = @[originRecord(2, token)]
    admission.classifications = @[
      SnapshotSurfaceClassification(
        surfaceIndex: 2, surfaceGeneration: 1, classification: 2
      )
    ]
    adapter.reconcile(admission)
    let child = adapter.logicalWindow(2, 1).get()
    # The class placed it on the active output's second view, not the origin's.
    check adapter.model().windows[child].homeOutput == adapter.logicalOutput(10).get()
    adapter.model().validate()

  test "a new connection clears the token space":
    var adapter = initPolicyAdapter()
    let scene = originScene(1, @[toplevel(1, 10)])
    adapter.reconcile(scene)
    let first = adapter.projection(scene, originRequest(1, 1, @[10'u64])).launchContexts
    check first.len == 1

    # A later epoch mints afresh, and the old token no longer resolves.
    var request = originRequest(2, 1, @[10'u64])
    request.connectionEpoch = 2
    let second = adapter.projection(scene, request).launchContexts
    check second[0].epoch == 2
    var admission = originScene(2, @[toplevel(1, 10), toplevel(2, 10)])
    admission.launchOrigins = @[originRecord(2, first[0].token, 2)]
    adapter.reconcile(admission)
    check adapter.logicalWindow(2, 1).isSome

  test "a token naming an output that has gone dormant places ordinarily":
    ## The model keeps a dormant output so its windows can return to it. A
    ## launch must not be sent somewhere the operator cannot see, so the token
    ## resolves to nothing and the window opens where it otherwise would have.
    var adapter = initPolicyAdapter()
    var both = originScene(1, @[toplevel(1, 20)])
    both.activeOutput = 10
    adapter.reconcile(both)
    let contexts =
      adapter.projection(both, originRequest(1, 1, @[10'u64, 20'u64])).launchContexts
    let token = contexts.contextFor(1).get().token

    # The second monitor is unplugged. Its windows migrate and it goes dormant.
    var alone = snapshot(
      2,
      @[
        SnapshotOutput(
          output: 10,
          generation: 1,
          width: 2560,
          height: 1440,
          focusIndex: 1,
          focusGeneration: 1,
        )
      ],
      @[toplevel(1, 10), toplevel(2, 0)],
    )
    alone.launchOrigins = @[originRecord(2, token)]
    adapter.reconcile(alone)
    let child = adapter.logicalWindow(2, 1).get()
    check adapter.model().windows[child].homeOutput == adapter.logicalOutput(10).get()
    adapter.model().validate()

  test "a token stays put while other destinations churn past the bound":
    ## The cache is bounded, and the bug this pins is evicting the oldest token
    ## even when the place it names is still in use. One source sits on a
    ## monitor that never changes while another output is replaced over and
    ## over; the stable source must keep its token and still place a child.
    var adapter = initPolicyAdapter()
    var scene = originScene(1, @[toplevel(1, 20), toplevel(2, 10)])
    scene.activeOutput = 10
    adapter.reconcile(scene)
    let stable = adapter
      .projection(scene, originRequest(1, 1, @[10'u64, 20'u64])).launchContexts
      .contextFor(1)
      .get().token

    var generation = 2'u64
    for _ in 0 ..< 1100:
      var churn = snapshot(
        generation,
        @[
          SnapshotOutput(
            output: 10,
            generation: uint32(generation),
            width: 2560,
            height: 1440,
            focusIndex: 2,
            focusGeneration: 1,
          ),
          SnapshotOutput(output: 20, generation: 1, x: 2560, width: 1920, height: 1080),
        ],
        @[toplevel(1, 20), toplevel(2, 10)],
      )
      churn.activeOutput = 10
      adapter.reconcile(churn)
      discard adapter.projection(
        churn, originRequest(generation, generation, @[10'u64, 20'u64])
      )
      generation += 1

    let after = adapter.projection(
      originScene(generation, @[toplevel(1, 20), toplevel(2, 10)]),
      originRequest(generation, generation, @[10'u64, 20'u64]),
    )
    check after.launchContexts.contextFor(1).get().token == stable

    var admission =
      originScene(generation + 1, @[toplevel(1, 20), toplevel(2, 10), toplevel(3, 0)])
    admission.activeOutput = 10
    admission.launchOrigins = @[originRecord(3, stable)]
    adapter.reconcile(admission)
    let child = adapter.logicalWindow(3, 1).get()
    check adapter.model().windows[child].homeOutput == adapter.logicalOutput(20).get()
    check adapter.model().activeOutput == adapter.logicalOutput(10).get()
    adapter.model().validate()

  test "tokens never reach the checkpoint":
    var adapter = initPolicyAdapter()
    let scene = originScene(1, @[toplevel(1, 10)])
    adapter.reconcile(scene)
    discard adapter.projection(scene, originRequest(1, 1, @[10'u64]))
    check "launchToken" notin adapter.checkpointPayload()
    # A restored session mints its own, so a stale echo cannot point a launch
    # at a place the operator has since rearranged.
    var restored = adapter.checkpointPayload().restoreCheckpointPayload()
    restored.reconcile(scene)
    var admission = originScene(2, @[toplevel(1, 10), toplevel(2, 10)])
    admission.launchOrigins = @[originRecord(2, 1'u64)]
    expect PolicyClientError:
      restored.reconcile(admission)

suite "output launch destinations":
  test "empty output bookmark wins over another output's focus and survives cloning":
    var adapter = initPolicyAdapter()
    var scene = originScene(1, @[])
    scene.activeOutput = 20
    adapter.reconcile(scene)
    let projection = adapter.projection(scene, originRequest(1, 1, @[10'u64, 20'u64]))
    check projection.outputLaunchContexts.len == 2
    var token = 0'u64
    for record in projection.outputLaunchContexts:
      check record.generation == 1
      check record.epoch == 1
      if record.output == 10:
        token = record.token
    check token != 0
    var candidate = adapter.clone()
    var admission = originScene(2, @[toplevel(2, 0)])
    admission.activeOutput = 20
    admission.launchOrigins = @[originRecord(2, token)]
    candidate.reconcile(admission)
    let child = candidate.logicalWindow(2, 1).get()
    let left = candidate.logicalOutput(10).get()
    check candidate.model().windows[child].homeOutput == left
    check candidate.model().windowTagIds(child) ==
      candidate.model().viewTagIds(candidate.model().outputs[left].activeView)
    check candidate.model().activeOutput == candidate.logicalOutput(20).get()
    let repeated = adapter.projection(scene, originRequest(2, 1, @[10'u64, 20'u64]))
    for record in repeated.outputLaunchContexts:
      if record.output == 10:
        check record.token == token
