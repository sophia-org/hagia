## Passive runtime lifecycle records. The unidirectional settlement contract in
## `docs/data-oriented-design.md` is enforced by `src/runtime/reducer.nim`;
## these records carry no transport, filesystem, or commit authority.

type
  RuntimePhase* {.pure.} = enum
    disconnected
    idle
    preparing
    awaitingProjection
    awaitingOutcome

  RuntimeModel* = object
    phase*: RuntimePhase
    connectionEpoch*: uint64
    snapshotGeneration*: uint64
    profileGeneration*: uint64
    activeProfileDigest*: string
    candidateProfileDigest*: string
    pendingRequest*: uint64
    pendingTransaction*: uint64
    checkpointDirty*: bool

  RuntimeMsgKind* {.pure.} = enum
    connectionStarted
    connectionLost
    snapshotCompleted
    configurationPrepared
    configurationRejected
    projectionPrepared
    projectionSettled
    checkpointRequested
    effectCompleted

  RuntimeEffectKind* {.pure.} = enum
    none
    prepareProfile
    emitProjection
    persistCheckpoint
    recordEvidence

  RuntimeMsg* = object
    epoch*, generation*, requestId*, transaction*: uint64
    digest*: string
    success*, committed*: bool
    completedEffect*: RuntimeEffectKind
    kind*: RuntimeMsgKind

  RuntimeEffect* = object
    kind*: RuntimeEffectKind
    epoch*, generation*, requestId*, transaction*: uint64
    digest*: string

  RuntimeUpdate* = object
    model*: RuntimeModel
    effects*: seq[RuntimeEffect]
