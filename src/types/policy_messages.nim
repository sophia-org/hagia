import ./[actions, core, model]

## Passive reducer vocabulary for the private policy model. The transition
## itself lives in `src/policy/reducer.nim`; nothing here carries transport,
## filesystem, or commit authority.

type
  PolicyMsgKind* {.pure.} = enum
    sceneChanged
    action
    focus
    interaction

  PolicyInteractionKind* {.pure.} = enum
    move
    resize

  PolicyMsg* = object
    output*: OutputId
    case kind*: PolicyMsgKind
    of PolicyMsgKind.sceneChanged:
      discard
    of PolicyMsgKind.action:
      action*: PolicyAction
    of PolicyMsgKind.focus:
      focusWindow*: WindowId
    of PolicyMsgKind.interaction:
      interactionWindow*: WindowId
      interactionKind*: PolicyInteractionKind
      geometry*: Rect

  PolicyIntentKind* {.pure.} = enum
    project

  PolicyIntent* = object
    kind*: PolicyIntentKind
    outputs*: seq[OutputId]

  PolicyUpdate* = object
    candidate*: PolicyModel
    affectedViews*: seq[ViewId]
    affectedOutputs*: seq[OutputId]
    intents*: seq[PolicyIntent]
