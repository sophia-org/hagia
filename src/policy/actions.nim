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
