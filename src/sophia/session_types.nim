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
    sessionOperations*: seq[SnapshotSessionOperation]

  ProjectionCauseKind* {.pure.} = enum
    sceneChanged = 0
    action = 1
    focus = 2
    interaction = 3

  InteractionPhase* {.pure.} = enum
    none = 0
    begin = 1
    update = 2
    finish = 3
    cancel = 4

  InteractionKind* {.pure.} = enum
    none = 0
    move = 1
    resize = 2

  ProjectionCause* = object
    kind*: ProjectionCauseKind
    interactionPhase*: InteractionPhase
    interactionKind*: InteractionKind
    activationSerial*: uint64
    action*: uint64
    targetIndex*: uint32
    targetGeneration*: uint32
    x*, y*, width*, height*: int32

  ProjectionRequest* = object
    connectionEpoch*: uint64
    requestId*: uint64
    sceneGeneration*: uint64
    affectedOutputs*: seq[uint64]
    cause*: ProjectionCause

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

  SessionOperationIntent* = object
    requestId*: uint64
    operation*: uint64
    targetIndex*: uint32
    targetGeneration*: uint32
