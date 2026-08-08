import std/[options, unittest]

import policy/[projection, state, types]
import sophia/[policy_adapter, session_types, wm_v1]

proc focusableCapabilities(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

proc surface(
    index: uint32, output: uint64, stateGeneration: uint64 = 1, minWidth: int32 = 0
): SnapshotSurface =
  SnapshotSurface(
    surfaceIndex: index,
    surfaceGeneration: 1,
    stateGeneration: stateGeneration,
    currentOutput: output,
    capabilityBits: 31,
    width: 400,
    height: 300,
    minWidth: minWidth,
    minHeight: (if minWidth == 0: 0 else: 100),
  )

proc snapshot(
    generation: uint64, outputs: seq[SnapshotOutput], surfaces: seq[SnapshotSurface]
): PolicySnapshot =
  PolicySnapshot(generation: generation, outputs: outputs, surfaces: surfaces)

suite "Hagia private policy model":
  test "tag views select ordered windows without changing their identities":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 800))
    let first = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())

    let secondTags = tagForSlot(2)
    model.setWindowTags(second, secondTags)
    check model.eligibleWindows(output) == @[first]

    let secondView = model.addView(output, secondTags)
    model.activateView(output, secondView)
    check model.eligibleWindows(output) == @[second]
    check model.window(first).get().id == first
    check model.window(second).get().id == second
    model.validate()

  test "column projection respects constraints and deterministic order":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(x: 10, y: 20, width: 1000, height: 700))
    let first = model.addWindow(
      output, focusableCapabilities(), SizeConstraints(minWidth: 700, minHeight: 100)
    )
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    model.setFocus(output, second)

    let projected = model.projectColumns([output])
    require projected.len == 1
    check projected[0].focus == second
    check projected[0].placements.len == 2
    check projected[0].placements[0].window == first
    check projected[0].placements[0].geometry ==
      Rect(x: 10, y: 20, width: 500, height: 700)
    check projected[0].placements[0].requestedWidth == 700
    check projected[0].placements[1].geometry ==
      Rect(x: 510, y: 20, width: 500, height: 700)

  test "output removal migrates private views and windows":
    var model = initPolicyModel()
    let firstOutput = model.addOutput(Rect(width: 1000, height: 700))
    let secondOutput = model.addOutput(Rect(x: 1000, width: 1000, height: 700))
    let window =
      model.addWindow(secondOutput, focusableCapabilities(), SizeConstraints())

    model.removeOutput(secondOutput, firstOutput)
    check model.outputIds() == @[firstOutput]
    check model.window(window).get().homeOutput == firstOutput
    model.validate()

suite "Sophia snapshot adapter":
  test "complete snapshots preserve logical ids and admit hidden surfaces":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 1000,
      height: 700,
    )
    var adapter = initPolicyAdapter()
    let firstSnapshot = snapshot(1, @[output], @[surface(1, 10), surface(2, 0)])
    adapter.reconcile(firstSnapshot)
    let firstId = adapter.logicalWindow(1, 1)
    let secondId = adapter.logicalWindow(2, 1)
    require firstId.isSome and secondId.isSome

    let request = ProjectionRequest(
      connectionEpoch: 7, requestId: 9, sceneGeneration: 1, affectedOutputs: @[10'u64]
    )
    let projection = adapter.projection(firstSnapshot, request)
    require projection.outputs.len == 1
    check projection.outputs[0].output.output == 10
    check projection.outputs[0].placements.len == 2
    check projection.outputs[0].placements[0].width == 500
    check projection.outputs[0].placements[1].x == 500

    var nextOutput = output
    nextOutput.generation = 2
    let nextSnapshot =
      snapshot(2, @[nextOutput], @[surface(1, 10, 2), surface(2, 10, 2)])
    adapter.reconcile(nextSnapshot)
    check adapter.logicalWindow(1, 1) == firstId
    check adapter.logicalWindow(2, 1) == secondId

  test "projection rejects an output outside the complete snapshot":
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let scene = snapshot(1, @[output], @[surface(1, 10)])
    var adapter = initPolicyAdapter()
    adapter.reconcile(scene)

    expect PolicyAdapterError:
      discard adapter.projection(
        scene,
        ProjectionRequest(
          connectionEpoch: 7,
          requestId: 9,
          sceneGeneration: 1,
          affectedOutputs: @[11'u64],
        ),
      )
