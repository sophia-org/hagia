import ../types/desktop_sdk
import ../types/session
import ../types/wm_presentation
import ./policy_transport

proc policyRequest*(record: WfRecord): ProjectionRequest =
  if record.header.kind != 22:
    fail("expected SDK Cycle")
  let cycle = record.value.cycle
  result = ProjectionRequest(
    connectionEpoch: record.header.epoch,
    requestId: cycle.requestId,
    sceneGeneration: cycle.sceneGeneration,
    policyGeneration: cycle.policyGeneration,
  )
  for i in 0 ..< int(cycle.outputCount):
    result.affectedOutputs.add(cycle.outputs[i])
  case cycle.cause
  of 0:
    result.cause.kind = ProjectionCauseKind.sceneChanged
  of 1:
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.action,
      activationSerial: cycle.value.action.serial,
      action: cycle.value.action.action,
    )
  of 2:
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.focus,
      targetIndex: cycle.value.focus.index,
      targetGeneration: cycle.value.focus.generation,
    )
  of 3:
    let v = cycle.value.pointerFocus
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.pointerFocus,
      # The existing reducer carries pointer-focus output in action.
      action: v.output,
      targetIndex: v.target.index,
      targetGeneration: v.target.generation,
    )
  of 4:
    let v = cycle.value.interaction
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.interaction,
      interactionPhase: InteractionPhase(v.phase),
      interactionKind: InteractionKind(v.kind),
      interactionAxis: InteractionAxis(v.axis),
      targetIndex: v.target.index,
      targetGeneration: v.target.generation,
      x: v.x,
      y: v.y,
      width: v.width,
      height: v.height,
    )
  of 5:
    let v = cycle.value.outputAction
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.outputAction,
      activationSerial: v.serial,
      action: v.action,
      output: v.output,
      outputGeneration: v.outputGeneration,
    )
  of 6:
    let v = cycle.value.presentationAction
    result.cause = ProjectionCause(
      kind: ProjectionCauseKind.presentationAction,
      activationSerial: v.serial,
      action: v.action,
      presentation: PresentationIdentity(
        publicationGeneration: v.publicationGeneration,
        output: v.output,
        outputGeneration: v.outputGeneration,
        presentationEpoch: v.presentationEpoch,
        targetId: v.targetId,
        targetGeneration: v.targetGeneration,
      ),
    )
  else:
    fail("unsupported SDK Cycle cause")
