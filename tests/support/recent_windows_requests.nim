import types/[actions, session, wm_v1]
import policy/actions

## Snapshots and requests for the recent-windows switcher tests, shared by the
## adapter suite and the replay CLI check.

proc scene*(): PolicySnapshot =
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

proc request*(
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

proc chordAction*(
    snapshot: PolicySnapshot,
    id, chord: uint64,
    action = PolicyAction.recentWindowNext,
    epoch = 7'u64,
): ProjectionRequest =
  ## A followed chord's own activation `id`; the opener has `id == chord`.
  result = snapshot.request(id, action)
  result.connectionEpoch = epoch
  result.cause.kind = ProjectionCauseKind.chordAction
  result.cause.chordSerial = chord

proc lifecycle*(
    snapshot: PolicySnapshot,
    id: uint64,
    phase, reason: uint16,
    count = 1'u32,
    chord = 1'u64,
    action = PolicyAction.recentWindowNext,
): ProjectionRequest =
  ## Held or Ended of the chord whose opening activation was `chord`.
  result = snapshot.request(id, action)
  result.cause.kind = ProjectionCauseKind.actionLifecycle
  result.cause.activationSerial = chord
  result.cause.lifecyclePhase = phase
  result.cause.lifecycleReason = reason
  result.cause.lifecycleCount = count

proc sceneChanged*(
    snapshot: PolicySnapshot, id: uint64, epoch = 7'u64
): ProjectionRequest =
  result = snapshot.request(id, PolicyAction.recentWindowNext)
  result.connectionEpoch = epoch
  result.cause = ProjectionCause(kind: ProjectionCauseKind.sceneChanged)
