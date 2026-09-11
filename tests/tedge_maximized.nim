import std/[json, options, strutils, unittest]
import policy/[actions, entity_store, projection, state]
import types/[actions, config_values, core, model, projection, session, wm_v1]
import sophia/[policy_adapter, policy_session]

proc edgeSession(): PolicySession =
  initPolicySession(
    initPolicyAdapter(
      AuthorityCandidate(
        authority: ProfileAuthority.policy,
        generation: 1,
        digest: repeat('e', 64),
        values: @[
          ProfileValue(key: "policy.outer-gap", encoded: "outer-gap 8"),
          ProfileValue(key: "policy.inner-gap", encoded: "inner-gap 8"),
        ],
      )
    )
  )

proc sceneFixture(): PolicySnapshot =
  result = PolicySnapshot(generation: 1, activeOutput: 10)
  result.outputs.add(
    SnapshotOutput(
      output: 10,
      generation: 1,
      width: 1600,
      height: 1000,
      workY: 32,
      workWidth: 1600,
      workHeight: 968,
      focusIndex: 1,
      focusGeneration: 1,
    )
  )
  for index in 1'u32 .. 3'u32:
    result.surfaces.add(
      SnapshotSurface(
        surfaceIndex: index,
        surfaceGeneration: 1,
        stateGeneration: 1,
        currentOutput: 10,
        capabilityBits: 31,
        width: 700,
        height: 900,
      )
    )

proc request(scene: PolicySnapshot, id: uint64, action: uint64): ProjectionRequest =
  ProjectionRequest(
    connectionEpoch: 1,
    requestId: id,
    sceneGeneration: scene.generation,
    policyGeneration: id,
    affectedOutputs: @[10'u64],
    cause: ProjectionCause(
      kind: (
        if action == 0: ProjectionCauseKind.sceneChanged else: ProjectionCauseKind.action
      ),
      activationSerial: id,
      action: action,
    ),
  )

proc echo(scene: var PolicySnapshot, projection: PolicyProjection) =
  for output in projection.outputs:
    scene.outputs[0].focusIndex = output.output.focusIndex
    scene.outputs[0].focusGeneration = output.output.focusGeneration
    for placement in output.placements:
      for surface in scene.surfaces.mitems:
        if surface.surfaceIndex == placement.surfaceIndex:
          surface.currentStateBits = placement.presentationBits
          surface.requestStateBits = placement.presentationBits
          surface.x = placement.x
          surface.y = placement.y
          surface.width = placement.width
          surface.height = placement.height
  inc scene.generation

proc step(
    session: var PolicySession,
    scene: var PolicySnapshot,
    id: var uint64,
    action: uint64 = 0,
): PolicyProjection =
  let req = scene.request(id, action)
  result = session.prepare(scene, req, id)
  session.settle(
    ProjectionOutcome(
      transaction: id,
      connectionEpoch: 1,
      requestId: id,
      sceneGeneration: scene.generation,
      kind: ProjectionOutcomeKind.committed,
    )
  )
  scene.echo(result)
  inc id

proc placement(projection: PolicyProjection, index: uint32): ProjectionPlacement =
  for value in projection.outputs[0].placements:
    if value.surfaceIndex == index:
      return value
  raise newException(ValueError, "missing placement")

proc translated(projection: PolicyProjection, index: uint32): bool =
  for group in projection.translationGroups:
    for member in group.members:
      if member.surfaceIndex == index:
        return true

proc maximizedIntent(session: PolicySession): bool =
  session.committedAdapter.model.window(WindowId(1)).get().maximized

suite "edge maximization follows scrolling focus":
  test "leaving restores strip geometry and returning restores edge presentation":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    let expanded = session.step(scene, id, PolicyAction.toggleMaximized.raw())
    check expanded.placement(1).width == 1600
    check expanded.placement(1).y == 32
    check expanded.placement(1).height == 968
    check (expanded.placement(1).presentationBits and 2) != 0
    let moved = session.step(scene, id, PolicyAction.focusColumnNext.raw())
    check moved.outputs[0].output.focusIndex == 2
    check moved.placement(1).width < 1600
    check (moved.placement(1).presentationBits and 2) == 0
    check moved.translated(1)
    check moved.placement(2).x >= 0
    check moved.placement(2).x + moved.placement(2).width <= 1600
    check session.maximizedIntent()
    discard session.step(scene, id)
    check session.maximizedIntent()
    let returned = session.step(scene, id, PolicyAction.focusColumnPrevious.raw())
    check returned.outputs[0].output.focusIndex == 1
    check returned.placement(1).width == 1600
    check (returned.placement(1).presentationBits and 2) != 0

  test "suspended intent survives checkpoint restoration":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    discard session.step(scene, id, PolicyAction.toggleMaximized.raw())
    discard session.step(scene, id, PolicyAction.focusColumnNext.raw())
    session = initPolicySession(
      restoreCheckpointPayload(session.committedAdapter.checkpointPayload())
    )
    discard session.step(scene, id)
    check session.maximizedIntent()
    let returned = session.step(scene, id, PolicyAction.focusColumnPrevious.raw())
    check returned.placement(1).width == 1600
    check (returned.placement(1).presentationBits and 2) != 0

  test "rejecting navigation preserves the committed maximized presentation":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    discard session.step(scene, id, PolicyAction.toggleMaximized.raw())
    let before = session.committedAdapter.checkpointPayload()
    let req = scene.request(id, PolicyAction.focusColumnNext.raw())
    discard session.prepare(scene, req, id)
    session.settle(
      ProjectionOutcome(
        transaction: id,
        connectionEpoch: 1,
        requestId: id,
        sceneGeneration: scene.generation,
        kind: ProjectionOutcomeKind.rejectedInvalid,
      )
    )
    check session.committedAdapter.checkpointPayload() == before
    inc id
    let redraw = session.step(scene, id)
    check redraw.placement(1).width == 1600
    check session.maximizedIntent()

  test "column maximize and edge maximize retain distinct geometry":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    discard session.step(scene, id, PolicyAction.maximizeColumn.raw())
    let edges = session.step(scene, id, PolicyAction.toggleMaximized.raw())
    check edges.placement(1).width == 1600
    let model = session.committedAdapter.model
    check not model.columns[model.window(WindowId(1)).get().column].fullWidth

  test "an external presentation change still clears active edge intent":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    discard session.step(scene, id, PolicyAction.toggleMaximized.raw())
    scene.surfaces[0].currentStateBits = 0
    scene.surfaces[0].requestStateBits = 0
    let restored = session.step(scene, id)
    check not session.maximizedIntent()
    check restored.placement(1).width < 1600

  test "legacy checkpoint preserves expansion while separating old combined modes":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    discard session.step(scene, id, PolicyAction.toggleMaximized.raw())
    var node =
      session.committedAdapter.checkpointPayload().split('\n', 1)[1].parseJson()
    node["schema"] = %14
    for surface in node["surfaces"]:
      surface.delete("presentedMaximized")
    node["columns"][0]["fullWidth"] = %true
    let restored = restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-14\n" & $node)
    check restored.model.window(WindowId(1)).get().maximized
    check not restored.model
      .column(restored.model.window(WindowId(1)).get().column)
      .get().fullWidth
    session = initPolicySession(restored)
    let expanded = session.step(scene, id)
    check expanded.placement(1).width == 1600

  test "horizontal and vertical scrolling leave an expanded pane through normal geometry":
    for mode in [LayoutMode.scroller, LayoutMode.verticalScroller]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(x: -1600, y: 32, width: 1600, height: 968))
      var windows: seq[WindowId]
      for _ in 0 .. 2:
        windows.add(
          model.addWindow(
            output, WindowCapabilities(focusable: true), SizeConstraints()
          )
        )
        model.setFocus(output, windows[^1])
      model.setLayout(output, mode)
      model.setFocus(output, windows[0])
      model.applyAction(output, PolicyAction.toggleMaximized)
      let expanded = model.projectLayout([output], 8, 8)[0]
      model.rememberViewportOffset(output, expanded.viewportOffset, expanded.camera)
      model.focusColumnRelative(output, 1)
      let moved = model.projectLayout([output], 8, 8)[0]
      for placement in moved.placements:
        if placement.window == windows[0]:
          check not placement.maximized
          check placement.geometry != Rect(x: -1600, y: 32, width: 1600, height: 968)
        if placement.window == windows[1]:
          check placement.geometry.x >= -1600
          check placement.geometry.x + placement.geometry.width <= 0
          check placement.geometry.y >= 32
          check placement.geometry.y + placement.geometry.height <= 1000
      check model.window(windows[0]).get().maximized

  test "M suspends edge presentation and F restores it without replacing column width":
    var session = edgeSession()
    var scene = sceneFixture()
    var id = 1'u64
    let ordinary = session.step(scene, id).placement(1)
    discard session.step(scene, id, PolicyAction.toggleMaximized.raw())
    let column = session.step(scene, id, PolicyAction.maximizeColumn.raw())
    check column.placement(1).width < 1600
    check (column.placement(1).presentationBits and 2) == 0
    check session.maximizedIntent()
    let edges = session.step(scene, id, PolicyAction.toggleMaximized.raw())
    check edges.placement(1).width == 1600
    let restored = session.step(scene, id, PolicyAction.toggleMaximized.raw())
    check restored.placement(1).width == ordinary.width
    check not session.maximizedIntent()
