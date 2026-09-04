import std/[options, sequtils, tables]

import ../types/[core, model]
import ../policy/entity_store
import ../state/[queries, values]

## Focus assignment and the bounded focus history an output keeps. Both window
## and output lifecycle need this, so it owns no other concern.

proc setFocus*(model: var PolicyModel, outputId: OutputId, windowId: WindowId) =
  let output = model.output(outputId)
  let window = model.window(windowId)
  if output.isNone or window.isNone:
    fail("focus target does not exist")
  let view = model.view(output.get().activeView)
  if view.isNone or window.get().homeOutput != outputId or (
    windowId != model.visibleScratchpad and
    not model.windowTagIds(windowId).intersects(model.viewTagIds(view.get().id))
  ) or not window.get().capabilities.focusable or window.get().minimized:
    fail("focus target is not visible and focusable")
  model.outputs[outputId].focusedWindow = windowId
  model.outputs[outputId].focusHistory.keepItIf(it != windowId)
  model.outputs[outputId].focusHistory.add(windowId)
  if model.outputs[outputId].focusHistory.len > maxFocusHistory:
    model.outputs[outputId].focusHistory.delete(0)
  model.activeOutput = outputId

proc clearFocus*(model: var PolicyModel, outputId: OutputId) =
  if outputId notin model.outputs:
    fail("focus output does not exist")
  model.outputs[outputId].focusedWindow = nullWindowId
