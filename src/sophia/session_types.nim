import ./wm_v1

type
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
