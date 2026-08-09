import ./reducer

type
  RuntimeEffectHandler* = proc(effect: RuntimeEffect): bool {.closure.}

  RuntimeEffectExecutor* = object
    prepareProfile*: RuntimeEffectHandler
    emitProjection*: RuntimeEffectHandler
    persistCheckpoint*: RuntimeEffectHandler
    recordEvidence*: RuntimeEffectHandler

proc executeEffect*(
    executor: RuntimeEffectExecutor, effect: RuntimeEffect
): RuntimeMsg =
  ## I/O implementations are injected at the outer runtime boundary. The
  ## executor returns only a typed completion message to the reducer.
  var success = false
  case effect.kind
  of RuntimeEffectKind.none:
    success = true
  of RuntimeEffectKind.prepareProfile:
    success = executor.prepareProfile != nil and executor.prepareProfile(effect)
  of RuntimeEffectKind.emitProjection:
    success = executor.emitProjection != nil and executor.emitProjection(effect)
  of RuntimeEffectKind.persistCheckpoint:
    success = executor.persistCheckpoint != nil and executor.persistCheckpoint(effect)
  of RuntimeEffectKind.recordEvidence:
    success = executor.recordEvidence != nil and executor.recordEvidence(effect)
  RuntimeMsg(
    kind: RuntimeMsgKind.effectCompleted,
    epoch: effect.epoch,
    generation: effect.generation,
    requestId: effect.requestId,
    transaction: effect.transaction,
    digest: effect.digest,
    success: success,
    completedEffect: effect.kind,
  )
