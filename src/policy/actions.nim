import ./[state, types]

type PolicyAction* {.pure.} = enum
  focusNext = 1
  focusPrevious = 2
  viewNext = 3
  viewPrevious = 4
  moveToNextOutput = 5
  moveToPreviousOutput = 6
  growColumn = 7
  shrinkColumn = 8
  growWindow = 9
  shrinkWindow = 10
  activateView1 = 11
  activateView2 = 12
  activateView3 = 13
  activateView4 = 14
  activateView5 = 15
  activateView6 = 16
  activateView7 = 17
  activateView8 = 18
  activateView9 = 19
  moveToView1 = 20
  moveToView2 = 21
  moveToView3 = 22
  moveToView4 = 23
  moveToView5 = 24
  moveToView6 = 25
  moveToView7 = 26
  moveToView8 = 27
  moveToView9 = 28
  sessionTerminal = 29
  sessionBrowser = 30
  sessionClose = 31
  sessionLogout = 32
  focusNextOutput = 33
  focusPreviousOutput = 34
  consumeNextColumn = 35
  expelFocusedWindow = 36
  toggleFullscreen = 37
  toggleMaximized = 38
  minimizeFocused = 39
  restoreMinimized = 40
  toggleFloating = 41
  toggleViewTag1 = 42
  toggleViewTag2 = 43
  toggleViewTag3 = 44
  toggleViewTag4 = 45
  toggleViewTag5 = 46
  toggleViewTag6 = 47
  toggleViewTag7 = 48
  toggleViewTag8 = 49
  toggleViewTag9 = 50
  toggleFocusedTag1 = 51
  toggleFocusedTag2 = 52
  toggleFocusedTag3 = 53
  toggleFocusedTag4 = 54
  toggleFocusedTag5 = 55
  toggleFocusedTag6 = 56
  toggleFocusedTag7 = 57
  toggleFocusedTag8 = 58
  toggleFocusedTag9 = 59
  newWorkspace = 60
  focusPreviousOccupiedWorkspace = 61
  focusNextOccupiedWorkspace = 62
  moveToScratchpad = 63
  toggleScratchpad = 64
  restoreScratchpad = 65

proc raw*(action: PolicyAction): uint64 =
  uint64(ord(action))

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
    raw in PolicyAction.moveToScratchpad.raw() .. PolicyAction.restoreScratchpad.raw()

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
