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
  of PolicyAction.toggleNamedScratchpad1 .. PolicyAction.toggleNamedScratchpad4:
    "toggle-named-scratchpad " &
      $(ord(action) - ord(PolicyAction.toggleNamedScratchpad1) + 1)
  of PolicyAction.moveToNamedScratchpad1 .. PolicyAction.moveToNamedScratchpad4:
    "move-to-named-scratchpad " &
      $(ord(action) - ord(PolicyAction.moveToNamedScratchpad1) + 1)
  of PolicyAction.focusLast:
    "focus-last"
  of PolicyAction.selectScrollerLayout:
    "layout-scroller"
  of PolicyAction.selectTileLayout:
    "layout-tile"
  of PolicyAction.selectGridLayout:
    "layout-grid"
  of PolicyAction.selectMonocleLayout:
    "layout-monocle"
  of PolicyAction.selectVerticalScrollerLayout:
    "layout-vertical-scroller"
  of PolicyAction.focusColumnNext:
    "focus-column-next"
  of PolicyAction.focusColumnPrevious:
    "focus-column-prev"
  of PolicyAction.focusWindowBelow:
    "focus-window-below"
  of PolicyAction.focusWindowAbove:
    "focus-window-above"
  of PolicyAction.moveWindowBelow:
    "move-window-below"
  of PolicyAction.moveWindowAbove:
    "move-window-above"
  of PolicyAction.moveWindowToColumnNext:
    "move-window-column-next"
  of PolicyAction.moveWindowToColumnPrevious:
    "move-window-column-prev"
  of PolicyAction.moveColumnNext:
    "move-column-next"
  of PolicyAction.moveColumnPrevious:
    "move-column-prev"
  of PolicyAction.moveColumnFirst:
    "move-column-first"
  of PolicyAction.moveColumnLast:
    "move-column-last"
  of PolicyAction.focusColumnFirst:
    "focus-column-first"
  of PolicyAction.focusColumnLast:
    "focus-column-last"
  of PolicyAction.promoteColumn:
    "promote-column"
  of PolicyAction.moveToViewNext:
    "move-to-view-next"
  of PolicyAction.moveToViewPrevious:
    "move-to-view-prev"
  of PolicyAction.moveViewToOutputNext:
    "move-view-to-output-next"
  of PolicyAction.moveViewToOutputPrevious:
    "move-view-to-output-prev"
  of PolicyAction.swapWithView1 .. PolicyAction.swapWithView9:
    "swap-with-view " & $(ord(action) - ord(PolicyAction.swapWithView1) + 1)
  of PolicyAction.increaseMasterCount:
    "increase-master-count"
  of PolicyAction.decreaseMasterCount:
    "decrease-master-count"
  of PolicyAction.increaseMasterRatio:
    "increase-master-ratio"
  of PolicyAction.decreaseMasterRatio:
    "decrease-master-ratio"
  of PolicyAction.increaseGaps:
    "increase-gaps"
  of PolicyAction.decreaseGaps:
    "decrease-gaps"
  of PolicyAction.toggleGaps:
    "toggle-gaps"
  of PolicyAction.maximizeColumn:
    "maximize-column"
  of PolicyAction.selectCenterTileLayout:
    "layout-center-tile"
  of PolicyAction.selectRightTileLayout:
    "layout-right-tile"
  of PolicyAction.selectVerticalGridLayout:
    "layout-vertical-grid"
  of PolicyAction.selectDeckLayout:
    "layout-deck"
  of PolicyAction.groupWindows:
    "group-windows"
  of PolicyAction.ungroupWindow:
    "ungroup-window"
  of PolicyAction.focusNextInGroup:
    "focus-next-in-group"
  of PolicyAction.selectSpiralLayout:
    "layout-spiral"
  of PolicyAction.selectMixedLayout:
    "layout-mixed"

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

proc toggleNamedScratchpadAction*(slot: int): PolicyAction =
  if slot notin 1 .. maxNamedScratchpadSlots:
    raise newException(PolicyStateError, "named scratchpad action slot is invalid")
  PolicyAction(ord(PolicyAction.toggleNamedScratchpad1) + slot - 1)

proc moveToNamedScratchpadAction*(slot: int): PolicyAction =
  if slot notin 1 .. maxNamedScratchpadSlots:
    raise newException(PolicyStateError, "named scratchpad action slot is invalid")
  PolicyAction(ord(PolicyAction.moveToNamedScratchpad1) + slot - 1)

proc swapWithViewAction*(slot: int): PolicyAction =
  if slot notin 1 .. 9:
    raise newException(PolicyStateError, "view swap action slot is invalid")
  PolicyAction(ord(PolicyAction.swapWithView1) + slot - 1)

proc isPolicyAction*(raw: uint64): bool =
  raw in PolicyAction.focusNext.raw() .. PolicyAction.moveToView9.raw() or
    raw in
    PolicyAction.focusNextOutput.raw() .. PolicyAction.focusNextOccupiedWorkspace.raw() or
    raw in PolicyAction.moveToScratchpad.raw() .. high(PolicyAction).raw()

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
  of PolicyAction.toggleNamedScratchpad1 .. PolicyAction.toggleNamedScratchpad4:
    model.toggleNamedScratchpad(
      output,
      ScratchpadSlotId(ord(action) - ord(PolicyAction.toggleNamedScratchpad1) + 1),
    )
  of PolicyAction.moveToNamedScratchpad1 .. PolicyAction.moveToNamedScratchpad4:
    model.moveFocusedToNamedScratchpad(
      output,
      ScratchpadSlotId(ord(action) - ord(PolicyAction.moveToNamedScratchpad1) + 1),
    )
  of PolicyAction.focusLast:
    model.focusLast(output)
  of PolicyAction.selectScrollerLayout:
    model.setLayout(output, LayoutMode.scroller)
  of PolicyAction.selectTileLayout:
    model.setLayout(output, LayoutMode.tile)
  of PolicyAction.selectGridLayout:
    model.setLayout(output, LayoutMode.grid)
  of PolicyAction.selectMonocleLayout:
    model.setLayout(output, LayoutMode.monocle)
  of PolicyAction.selectVerticalScrollerLayout:
    model.setLayout(output, LayoutMode.verticalScroller)
  of PolicyAction.focusColumnNext:
    model.focusColumnRelative(output, 1)
  of PolicyAction.focusColumnPrevious:
    model.focusColumnRelative(output, -1)
  of PolicyAction.focusWindowBelow:
    model.focusWithinColumnRelative(output, 1)
  of PolicyAction.focusWindowAbove:
    model.focusWithinColumnRelative(output, -1)
  of PolicyAction.moveWindowBelow:
    model.moveWithinColumn(output, 1)
  of PolicyAction.moveWindowAbove:
    model.moveWithinColumn(output, -1)
  of PolicyAction.moveWindowToColumnNext:
    model.moveToAdjacentColumn(output, 1)
  of PolicyAction.moveWindowToColumnPrevious:
    model.moveToAdjacentColumn(output, -1)
  of PolicyAction.moveColumnNext:
    model.moveColumnRelative(output, 1)
  of PolicyAction.moveColumnPrevious:
    model.moveColumnRelative(output, -1)
  of PolicyAction.moveColumnFirst:
    model.moveColumnToEdge(output, last = false)
  of PolicyAction.moveColumnLast:
    model.moveColumnToEdge(output, last = true)
  of PolicyAction.focusColumnFirst:
    model.focusColumnEdge(output, last = false)
  of PolicyAction.focusColumnLast:
    model.focusColumnEdge(output, last = true)
  of PolicyAction.promoteColumn:
    model.promoteFocusedColumn(output)
  of PolicyAction.moveToViewNext:
    model.moveFocusedToViewRelative(output, 1)
  of PolicyAction.moveToViewPrevious:
    model.moveFocusedToViewRelative(output, -1)
  of PolicyAction.moveViewToOutputNext:
    model.moveViewToOutputRelative(output, 1)
  of PolicyAction.moveViewToOutputPrevious:
    model.moveViewToOutputRelative(output, -1)
  of PolicyAction.swapWithView1 .. PolicyAction.swapWithView9:
    model.swapWithViewSlot(output, ord(action) - ord(PolicyAction.swapWithView1) + 1)
  of PolicyAction.increaseMasterCount:
    model.adjustMasterCount(1)
  of PolicyAction.decreaseMasterCount:
    model.adjustMasterCount(-1)
  of PolicyAction.increaseMasterRatio:
    model.adjustMasterRatio(1)
  of PolicyAction.decreaseMasterRatio:
    model.adjustMasterRatio(-1)
  of PolicyAction.increaseGaps:
    model.adjustGaps(1)
  of PolicyAction.decreaseGaps:
    model.adjustGaps(-1)
  of PolicyAction.toggleGaps:
    model.toggleGaps()
  of PolicyAction.maximizeColumn:
    model.toggleColumnMaximized(output)
  of PolicyAction.selectCenterTileLayout:
    model.setLayout(output, LayoutMode.centerTile)
  of PolicyAction.selectRightTileLayout:
    model.setLayout(output, LayoutMode.rightTile)
  of PolicyAction.selectVerticalGridLayout:
    model.setLayout(output, LayoutMode.verticalGrid)
  of PolicyAction.selectDeckLayout:
    model.setLayout(output, LayoutMode.deck)
  of PolicyAction.groupWindows:
    model.groupFocusedWithNeighbour(output)
  of PolicyAction.ungroupWindow:
    model.ungroupFocused(output)
  of PolicyAction.focusNextInGroup:
    model.focusNextInGroup(output)
  of PolicyAction.selectSpiralLayout:
    model.setLayout(output, LayoutMode.spiral)
  of PolicyAction.selectMixedLayout:
    model.setLayout(output, LayoutMode.tgmix)
