suite "new-window focus admission":
  test "new terminals move focus and camera and retry after rejection":
    var output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 2560,
      height: 1408,
      y: 32,
    )
    var session = initPolicySession()
    var surfaces = @[surface(1, 10)]
    var transaction = 1'u64
    for admitted in 1'u32 .. 4'u32:
      if admitted > 1:
        surfaces.add(surface(admitted, 0))
      let scene = snapshot(transaction, @[output], surfaces)
      let request = ProjectionRequest(
        connectionEpoch: 7,
        requestId: transaction,
        sceneGeneration: transaction,
        policyGeneration: 1,
        affectedOutputs: @[10'u64],
      )
      let before = session.committedAdapter().checkpointPayload()
      let projected = session.prepare(scene, request, transaction)
      check projected.outputs[0].output.focusIndex == admitted
      var found = false
      for placement in projected.outputs[0].placements:
        if placement.surfaceIndex == admitted:
          found = true
          check placement.x >= output.x
          check placement.x + placement.width <= output.x + output.width
      check found
      if admitted == 3:
        session.settle(
          ProjectionOutcome(
            transaction: transaction,
            connectionEpoch: 7,
            requestId: transaction,
            sceneGeneration: transaction,
            kind: ProjectionOutcomeKind.rejectedStale,
          )
        )
        check session.committedAdapter().checkpointPayload() == before
        let retry = session.prepare(scene, request, transaction)
        check retry == projected
      session.settle(
        ProjectionOutcome(
          transaction: transaction,
          connectionEpoch: 7,
          requestId: transaction,
          sceneGeneration: transaction + 1,
          kind: ProjectionOutcomeKind.committed,
        )
      )
      output.focusIndex = admitted
      for item in surfaces.mitems:
        item.currentOutput = 10
      inc transaction

  test "initial snapshot and content updates preserve existing focus":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 1000,
      height: 700,
    )
    var adapter = initPolicyAdapter()
    let surfaces = @[surface(1, 10), surface(2, 10)]
    adapter.reconcile(snapshot(1, @[output], surfaces))
    let logical = adapter.logicalOutput(10).get()
    let original = adapter.logicalWindow(1, 1).get()
    check adapter.model().output(logical).get().focusedWindow == original
    adapter.reconcile(snapshot(2, @[output], surfaces))
    check adapter.model().output(logical).get().focusedWindow == original

  test "background and non-focusable admissions do not replace active focus":
    let active = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 1000,
      height: 700,
    )
    let other = SnapshotOutput(
      output: 20,
      generation: 1,
      focusIndex: 2,
      focusGeneration: 1,
      x: 1000,
      width: 1000,
      height: 700,
    )
    var adapter = initPolicyAdapter()
    var surfaces = @[surface(1, 10), surface(2, 20)]
    adapter.reconcile(snapshot(1, @[active, other], surfaces))
    var nonFocusable = surface(3, 10)
    nonFocusable.capabilityBits = 31 xor 4
    var minimized = surface(4, 10)
    minimized.currentStateBits = 4
    var popup = surface(5, 10)
    popup.kind = 4
    surfaces.add(@[nonFocusable, minimized, popup, surface(6, 20), surface(7, 10)])
    var scene = snapshot(2, @[active, other], surfaces)
    scene.classifications.add(
      SnapshotSurfaceClassification(
        surfaceIndex: 7, surfaceGeneration: 1, classification: 2
      )
    )
    adapter.reconcile(scene)
    let logical = adapter.logicalOutput(10).get()
    check adapter.model().output(logical).get().focusedWindow ==
      adapter.logicalWindow(1, 1).get()
    # Other outputs can have focus records; admission still follows activeOutput.
    surfaces.add(surface(8, 10))
    scene = snapshot(3, @[active, other], surfaces)
    adapter.reconcile(scene)
    check adapter.model().output(logical).get().focusedWindow ==
      adapter.logicalWindow(8, 1).get()

  test "unplaced admission follows the second output when it is active":
    let first = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 1000,
      height: 700,
    )
    let second = SnapshotOutput(
      output: 20,
      generation: 1,
      focusIndex: 2,
      focusGeneration: 1,
      x: 1000,
      width: 1000,
      height: 700,
    )
    var adapter = initPolicyAdapter()
    var scene = snapshot(1, @[first, second], @[surface(1, 10), surface(2, 20)])
    scene.activeOutput = 20
    adapter.reconcile(scene)
    scene.generation = 2
    scene.surfaces.add(surface(3, 0))
    adapter.reconcile(scene)
    let output = adapter.logicalOutput(20).get()
    let added = adapter.logicalWindow(3, 1).get()
    check adapter.model().window(added).get().homeOutput == output
    check adapter.model().output(output).get().focusedWindow == added
    let projected = adapter.projection(
      scene,
      ProjectionRequest(
        connectionEpoch: 7,
        requestId: 2,
        sceneGeneration: 2,
        policyGeneration: 1,
        affectedOutputs: @[20'u64],
      ),
    )
    check projected.outputs[0].output.focusIndex == 3
    for placement in projected.outputs[0].placements:
      if placement.surfaceIndex == 3:
        check placement.x >= second.x
        check placement.x + placement.width <= second.x + second.width
