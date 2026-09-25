import std/options

import ../types/[core, model, policy_messages]
import ./[actions, entity_store, state]
import ../entities/tab_tree_ops
import ../systems/overview

proc reducePolicy*(model: PolicyModel, message: PolicyMsg): PolicyUpdate =
  ## The reducer has no transport or filesystem authority. A caller promotes
  ## the returned candidate only after Sophia commits its projection.
  result.candidate = model.clone()
  if message.output notin result.candidate.outputs:
    raise newException(PolicyStateError, "policy message output does not exist")
  case message.kind
  of PolicyMsgKind.sceneChanged:
    discard
  of PolicyMsgKind.overviewSelection:
    result.candidate.selectOverview(
      OverviewSelection(
        output: message.output,
        view: message.overviewView,
        window: message.overviewWindow,
      )
    )
  of PolicyMsgKind.action:
    result.candidate.applyAction(message.output, message.action)
  of PolicyMsgKind.focus:
    result.candidate.setActiveOutput(message.output)
    result.candidate.setFocus(message.output, message.focusWindow)
    result.candidate.focusTabWindow(message.output, message.focusWindow)
  of PolicyMsgKind.pointerFocus:
    # Disabled is a no-op, not a rejection: the observation is well formed and
    # the operator simply did not ask for it. Leaving the candidate untouched
    # keeps the active output, the focused window, and the camera exactly where
    # the last committed cycle put them.
    if result.candidate.settings.focusFollowsMouse:
      result.candidate.setActiveOutput(message.output)
      if message.pointerWindow != nullWindowId:
        result.candidate.setFocus(message.output, message.pointerWindow)
        result.candidate.focusTabWindow(message.output, message.pointerWindow)
  of PolicyMsgKind.interaction:
    let window = result.candidate.window(message.interactionWindow)
    if window.isNone or window.get().homeOutput != message.output:
      raise newException(PolicyStateError, "policy interaction target is invalid")
    case message.interactionKind
    of PolicyInteractionKind.move:
      if not window.get().capabilities.movable:
        raise newException(PolicyStateError, "policy interaction target is immovable")
    of PolicyInteractionKind.resize:
      if not window.get().capabilities.resizable:
        raise newException(PolicyStateError, "policy interaction target is fixed-size")
    result.candidate.setActiveOutput(message.output)
    result.candidate.setFloatingGeometry(
      message.output, message.interactionWindow, message.geometry
    )
  result.candidate.syncTabTrees()
  result.candidate.validate()
  # Projection replacement is complete per affected output. Return all outputs
  # for now because existing actions can move membership across authorities.
  result.affectedOutputs = result.candidate.outputIds()
  for outputId in result.affectedOutputs:
    let output = result.candidate.output(outputId)
    if output.isSome and output.get().activeView notin result.affectedViews:
      result.affectedViews.add(output.get().activeView)
  result.intents.add(
    PolicyIntent(kind: PolicyIntentKind.project, outputs: result.affectedOutputs)
  )
