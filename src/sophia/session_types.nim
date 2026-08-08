import ./wm_v1

type
  ProjectionOutcomeKind* {.pure.} = enum
    committed = 1
    rejectedStale = 2
    rejectedInvalid = 3
    timedOut = 4
    disconnected = 5

  PolicySnapshot* = object
    generation*: uint64
    outputs*: seq[SnapshotOutput]
    surfaces*: seq[SnapshotSurface]
    bindings*: seq[SnapshotBinding]

  ProjectionRequest* = object
    connectionEpoch*: uint64
    requestId*: uint64
    sceneGeneration*: uint64
    affectedOutputs*: seq[uint64]

  PolicyOutputProjection* = object
    output*: ProjectionOutput
    placements*: seq[ProjectionPlacement]

  PolicyProjection* = object
    outputs*: seq[PolicyOutputProjection]

  ProjectionOutcome* = object
    transaction*: uint64
    connectionEpoch*: uint64
    requestId*: uint64
    sceneGeneration*: uint64
    kind*: ProjectionOutcomeKind
