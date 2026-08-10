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

  RuntimeReducerError* = object of CatchableError

proc reduceRuntime*(model: RuntimeModel, message: RuntimeMsg): RuntimeUpdate =
  result.model = model
  case message.kind
  of RuntimeMsgKind.connectionStarted:
    if message.epoch == 0:
      raise newException(RuntimeReducerError, "connection epoch must be nonzero")
    result.model = RuntimeModel(
      phase: RuntimePhase.idle,
      connectionEpoch: message.epoch,
      activeProfileDigest: model.activeProfileDigest,
      profileGeneration: model.profileGeneration,
    )
  of RuntimeMsgKind.connectionLost:
    result.model.phase = RuntimePhase.disconnected
    result.model.pendingRequest = 0
    result.model.pendingTransaction = 0
    result.model.candidateProfileDigest.setLen(0)
  of RuntimeMsgKind.snapshotCompleted:
    if message.epoch != model.connectionEpoch or message.generation == 0 or
        model.phase == RuntimePhase.disconnected:
      raise newException(RuntimeReducerError, "snapshot identity is invalid")
    result.model.snapshotGeneration = message.generation
    result.model.phase = RuntimePhase.awaitingProjection
  of RuntimeMsgKind.configurationPrepared:
    if message.digest.len == 0 or message.generation <= model.profileGeneration:
      raise newException(RuntimeReducerError, "profile candidate identity is invalid")
    result.model.candidateProfileDigest = message.digest
    result.model.phase = RuntimePhase.preparing
    result.effects.add(
      RuntimeEffect(
        kind: RuntimeEffectKind.prepareProfile,
        epoch: model.connectionEpoch,
        generation: message.generation,
        digest: message.digest,
      )
    )
  of RuntimeMsgKind.configurationRejected:
    result.model.candidateProfileDigest.setLen(0)
    result.model.phase = RuntimePhase.idle
  of RuntimeMsgKind.projectionPrepared:
    if message.epoch != model.connectionEpoch or message.requestId == 0 or
        message.transaction == 0:
      raise newException(RuntimeReducerError, "projection identity is invalid")
    result.model.pendingRequest = message.requestId
    result.model.pendingTransaction = message.transaction
    result.model.phase = RuntimePhase.awaitingOutcome
    result.effects.add(
      RuntimeEffect(
        kind: RuntimeEffectKind.emitProjection,
        epoch: message.epoch,
        generation: model.snapshotGeneration,
        requestId: message.requestId,
        transaction: message.transaction,
      )
    )
  of RuntimeMsgKind.projectionSettled:
    if message.epoch != model.connectionEpoch or
        message.requestId != model.pendingRequest or
        message.transaction != model.pendingTransaction:
      raise newException(RuntimeReducerError, "projection outcome identity is invalid")
    result.model.pendingRequest = 0
    result.model.pendingTransaction = 0
    result.model.phase = RuntimePhase.idle
    if message.committed:
      result.model.checkpointDirty = true
  of RuntimeMsgKind.checkpointRequested:
    if model.checkpointDirty:
      result.effects.add(
        RuntimeEffect(
          kind: RuntimeEffectKind.persistCheckpoint,
          epoch: model.connectionEpoch,
          generation: model.snapshotGeneration,
        )
      )
  of RuntimeMsgKind.effectCompleted:
    if message.success and message.completedEffect == RuntimeEffectKind.persistCheckpoint:
      result.model.checkpointDirty = false
    if message.completedEffect == RuntimeEffectKind.prepareProfile and
        message.digest.len > 0 and message.digest == model.candidateProfileDigest:
      if message.success:
        result.model.activeProfileDigest = message.digest
        result.model.profileGeneration = message.generation
      result.model.candidateProfileDigest.setLen(0)
      result.model.phase = RuntimePhase.idle
