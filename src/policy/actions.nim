import ../types/[actions, core, model]
import ./state

proc raw*(action: PolicyAction): uint64 =
  uint64(ord(action))

proc profileName*(action: PolicyAction): string =
  ## Stable semantic identity advertised to Sophia's shortcut authority.
  ## The coordinator treats this as opaque text; Hagia alone owns meaning.
  case action
  of PolicyAction.focusNext:
    "focus-next"
  of PolicyAction.focusPrevious:
    "focus-prev"
  of PolicyAction.viewNext:
    "focus-view-next"
  of PolicyAction.viewPrevious:
    "focus-view-prev"
  of PolicyAction.moveToNextOutput:
    "move-to-output-next"
  of PolicyAction.moveToPreviousOutput:
    "move-to-output-prev"
  of PolicyAction.growColumn:
    "resize-width 0.1"
  of PolicyAction.shrinkColumn:
    "resize-width -0.1"
  of PolicyAction.growWindow:
    "resize-height 0.1"
  of PolicyAction.shrinkWindow:
    "resize-height -0.1"
  of PolicyAction.activateView1 .. PolicyAction.activateView9:
    "focus-workspace " & $(ord(action) - ord(PolicyAction.activateView1) + 1)
  of PolicyAction.moveToView1 .. PolicyAction.moveToView9:
    "move-to-workspace " & $(ord(action) - ord(PolicyAction.moveToView1) + 1)
  of PolicyAction.sessionTerminal:
    "spawn-terminal"
  of PolicyAction.sessionBrowser:
    "spawn-browser"
  of PolicyAction.sessionClose:
    "close-window"
  of PolicyAction.sessionLogout:
    "logout"
  of PolicyAction.focusNextOutput:
    "focus-output-next"
  of PolicyAction.focusPreviousOutput:
    "focus-output-prev"
  of PolicyAction.consumeNextColumn:
    "consume-window"
  of PolicyAction.expelFocusedWindow:
    "expel-window"
  of PolicyAction.toggleFullscreen:
    "toggle-fullscreen"
  of PolicyAction.toggleMaximized:
    "toggle-maximized"
  of PolicyAction.minimizeFocused:
    "minimize"
  of PolicyAction.restoreMinimized:
    "restore-minimized"
  of PolicyAction.toggleFloating:
    "toggle-floating"
  of PolicyAction.toggleViewTag1 .. PolicyAction.toggleViewTag9:
    "toggle-view-tag " & $(ord(action) - ord(PolicyAction.toggleViewTag1) + 1)
  of PolicyAction.toggleFocusedTag1 .. PolicyAction.toggleFocusedTag9:
    "toggle-window-tag " & $(ord(action) - ord(PolicyAction.toggleFocusedTag1) + 1)
  of PolicyAction.newWorkspace:
    "new-workspace"
  of PolicyAction.focusPreviousOccupiedWorkspace:
    "focus-occupied-workspace-prev"
  of PolicyAction.focusNextOccupiedWorkspace:
    "focus-occupied-workspace-next"
  of PolicyAction.moveToScratchpad:
    "move-to-scratchpad"
  of PolicyAction.toggleScratchpad:
    "toggle-scratchpad"
  of PolicyAction.restoreScratchpad:
    "restore-scratchpad"
  of PolicyAction.switchLayout:
    "switch-layout"

proc sessionOperationSlot*(action: PolicyAction): uint16 =
  case action
  of PolicyAction.sessionTerminal: 1
  of PolicyAction.sessionBrowser: 2
  of PolicyAction.sessionClose: 3
  of PolicyAction.sessionLogout: 4
  else: 0

proc activateViewAction*(slot: int): PolicyAction =
  if slot notin 1 .. 9:
    raise newException(PolicyStateError, "view action slot is invalid")
  PolicyAction(ord(PolicyAction.activateView1) + slot - 1)

proc moveToViewAction*(slot: int): PolicyAction =
  if slot notin 1 .. 9:
    raise newException(PolicyStateError, "move-to-view action slot is invalid")
  PolicyAction(ord(PolicyAction.moveToView1) + slot - 1)

proc toggleViewTagAction*(slot: int): PolicyAction =
  if slot notin 1 .. 9:
    raise newException(PolicyStateError, "view-tag action slot is invalid")
  PolicyAction(ord(PolicyAction.toggleViewTag1) + slot - 1)

proc toggleFocusedTagAction*(slot: int): PolicyAction =
  if slot notin 1 .. 9:
    raise newException(PolicyStateError, "window-tag action slot is invalid")
  PolicyAction(ord(PolicyAction.toggleFocusedTag1) + slot - 1)

proc isPolicyAction*(raw: uint64): bool =
  raw in PolicyAction.focusNext.raw() .. PolicyAction.moveToView9.raw() or
    raw in
    PolicyAction.focusNextOutput.raw() .. PolicyAction.focusNextOccupiedWorkspace.raw() or
    raw in PolicyAction.moveToScratchpad.raw() .. PolicyAction.switchLayout.raw()

proc policyAction*(raw: uint64): PolicyAction =
  if not raw.isPolicyAction():
    raise newException(PolicyStateError, "policy action identity is invalid")
  PolicyAction(raw)

proc applyAction*(model: var PolicyModel, output: OutputId, action: PolicyAction) =
  ## Reducer actions mutate private logical state only. Sophia validates the
  ## resulting complete projection before any change becomes authoritative.
  case action
  of PolicyAction.focusNext:
    model.focusRelative(output, 1)
  of PolicyAction.focusPrevious:
    model.focusRelative(output, -1)
  of PolicyAction.viewNext:
    model.activateViewRelative(output, 1)
  of PolicyAction.viewPrevious:
    model.activateViewRelative(output, -1)
  of PolicyAction.moveToNextOutput:
    model.moveFocusedToRelativeOutput(output, 1)
  of PolicyAction.moveToPreviousOutput:
    model.moveFocusedToRelativeOutput(output, -1)
  of PolicyAction.growColumn:
    model.adjustFocusedColumn(output, 1)
  of PolicyAction.shrinkColumn:
    model.adjustFocusedColumn(output, -1)
  of PolicyAction.growWindow:
    model.adjustFocusedWindow(output, 1)
  of PolicyAction.shrinkWindow:
    model.adjustFocusedWindow(output, -1)
  of PolicyAction.activateView1 .. PolicyAction.activateView9:
    model.activateViewSlot(output, ord(action) - ord(PolicyAction.activateView1) + 1)
  of PolicyAction.moveToView1 .. PolicyAction.moveToView9:
    model.moveFocusedToViewSlot(output, ord(action) - ord(PolicyAction.moveToView1) + 1)
  of PolicyAction.sessionTerminal .. PolicyAction.sessionLogout:
    raise newException(PolicyStateError, "session operation entered policy reduction")
  of PolicyAction.focusNextOutput:
    model.focusOutputRelative(1)
  of PolicyAction.focusPreviousOutput:
    model.focusOutputRelative(-1)
  of PolicyAction.consumeNextColumn:
    model.consumeNextColumn()
  of PolicyAction.expelFocusedWindow:
    model.expelFocusedWindow()
  of PolicyAction.toggleFullscreen:
    model.toggleFocusedFullscreen()
  of PolicyAction.toggleMaximized:
    model.toggleFocusedMaximized()
  of PolicyAction.minimizeFocused:
    model.minimizeFocused()
  of PolicyAction.restoreMinimized:
    model.restoreLastMinimized()
  of PolicyAction.toggleFloating:
    model.toggleFocusedFloating()
  of PolicyAction.toggleViewTag1 .. PolicyAction.toggleViewTag9:
    model.toggleViewTagSlot(output, ord(action) - ord(PolicyAction.toggleViewTag1) + 1)
  of PolicyAction.toggleFocusedTag1 .. PolicyAction.toggleFocusedTag9:
    model.toggleFocusedWindowTagSlot(
      output, ord(action) - ord(PolicyAction.toggleFocusedTag1) + 1
    )
  of PolicyAction.newWorkspace:
    discard model.addDynamicWorkspace(output)
  of PolicyAction.focusPreviousOccupiedWorkspace:
    model.focusOccupiedWorkspaceRelative(output, -1)
  of PolicyAction.focusNextOccupiedWorkspace:
    model.focusOccupiedWorkspaceRelative(output, 1)
  of PolicyAction.moveToScratchpad:
    model.moveFocusedToScratchpad(output)
  of PolicyAction.toggleScratchpad:
    model.toggleScratchpad(output)
  of PolicyAction.restoreScratchpad:
    model.restoreVisibleScratchpad()
  of PolicyAction.switchLayout:
    model.cycleLayout(output)
