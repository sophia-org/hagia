import ../types/[actions, core, model]
import ./state
import ../types/tab_tree
import ../entities/tab_tree_ops

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
  of PolicyAction.splitTreeDefault:
    "split-tree-layout-default"
  of PolicyAction.selectFrameTree:
    "layout-frame-tree"
  of PolicyAction.selectNotion:
    "layout-notion"
  of PolicyAction.selectSplitTree:
    "layout-i3"
  of PolicyAction.frameSplitHorizontal:
    "frame-split-horizontal"
  of PolicyAction.frameSplitVertical:
    "frame-split-vertical"
  of PolicyAction.frameSplitToggle:
    "frame-split-toggle"
  of PolicyAction.frameUnsplit:
    "frame-unsplit"
  of PolicyAction.frameTabNext:
    "frame-tab-next"
  of PolicyAction.frameTabPrevious:
    "frame-tab-prev"
  of PolicyAction.frameFocusParent:
    "frame-focus-parent"
  of PolicyAction.frameFocusChild:
    "frame-focus-child"
  of PolicyAction.frameResizeLeft:
    "frame-resize-left"
  of PolicyAction.treeFocusLeft:
    "focus-left"
  of PolicyAction.treeMoveLeft:
    "move-window-left"
  of PolicyAction.frameResizeRight:
    "frame-resize-right"
  of PolicyAction.treeFocusRight:
    "focus-right"
  of PolicyAction.treeMoveRight:
    "move-window-right"
  of PolicyAction.frameResizeUp:
    "frame-resize-up"
  of PolicyAction.treeFocusUp:
    "focus-up"
  of PolicyAction.treeMoveUp:
    "move-window-up"
  of PolicyAction.frameResizeDown:
    "frame-resize-down"
  of PolicyAction.treeFocusDown:
    "focus-down"
  of PolicyAction.treeMoveDown:
    "move-window-down"
  of PolicyAction.splitTreeHorizontal:
    "split-tree-layout-split-horizontal"
  of PolicyAction.splitTreeVertical:
    "split-tree-layout-split-vertical"
  of PolicyAction.splitTreeTabbed:
    "split-tree-layout-tabbed"
  of PolicyAction.splitTreeStacking:
    "split-tree-layout-stacking"
  of PolicyAction.splitTreeToggleSplit:
    "split-tree-layout-toggle-split"
  of PolicyAction.splitTreeCycleAll:
    "split-tree-layout-cycle-all"
  of PolicyAction.splitTreeSplitHorizontal:
    "split-tree-split-horizontal"
  of PolicyAction.splitTreeSplitVertical:
    "split-tree-split-vertical"
  of PolicyAction.splitTreeSplitToggle:
    "split-tree-split-toggle"
  of PolicyAction.splitFocusParent:
    "split-tree-focus-parent"
  of PolicyAction.splitFocusChild:
    "split-tree-focus-child"
  of PolicyAction.splitNextSibling:
    "split-tree-focus-next-sibling"
  of PolicyAction.splitPreviousSibling:
    "split-tree-focus-prev-sibling"
  of PolicyAction.selectDwindleLayout:
    "layout-dwindle"
  of PolicyAction.dwindlePreselectLeft:
    "dwindle-preselect-left"
  of PolicyAction.dwindlePreselectRight:
    "dwindle-preselect-right"
  of PolicyAction.dwindlePreselectUp:
    "dwindle-preselect-up"
  of PolicyAction.dwindlePreselectDown:
    "dwindle-preselect-down"

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
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.focusRight)
    else:
      model.focusColumnRelative(output, 1)
  of PolicyAction.focusColumnPrevious:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.focusLeft)
    else:
      model.focusColumnRelative(output, -1)
  of PolicyAction.focusWindowBelow:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.focusDown)
    else:
      model.focusWithinColumnRelative(output, 1)
  of PolicyAction.focusWindowAbove:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.focusUp)
    else:
      model.focusWithinColumnRelative(output, -1)
  of PolicyAction.moveWindowBelow:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.moveDown)
    else:
      model.moveWithinColumn(output, 1)
  of PolicyAction.moveWindowAbove:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.moveUp)
    else:
      model.moveWithinColumn(output, -1)
  of PolicyAction.moveWindowToColumnNext:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.moveRight)
    else:
      model.moveToAdjacentColumn(output, 1)
  of PolicyAction.moveWindowToColumnPrevious:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.moveLeft)
    else:
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
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.group)
    else:
      model.groupFocusedWithNeighbour(output)
  of PolicyAction.ungroupWindow:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.ungroup)
    else:
      model.ungroupFocused(output)
  of PolicyAction.focusNextInGroup:
    if model.tabLayoutActive(output):
      model.tabTreeCommand(output, TabTreeCommand.nextTab)
    else:
      model.focusNextInGroup(output)
  of PolicyAction.selectSpiralLayout:
    model.setLayout(output, LayoutMode.spiral)
  of PolicyAction.selectMixedLayout:
    model.setLayout(output, LayoutMode.tgmix)
  of PolicyAction.selectFrameTree:
    model.setLayout(output, LayoutMode.frameTree)
  of PolicyAction.selectNotion:
    model.setLayout(output, LayoutMode.notion)
  of PolicyAction.selectSplitTree:
    model.setLayout(output, LayoutMode.splitTree)
  of PolicyAction.frameSplitHorizontal:
    model.tabTreeCommand(output, TabTreeCommand.splitHorizontal)
  of PolicyAction.frameSplitVertical:
    model.tabTreeCommand(output, TabTreeCommand.splitVertical)
  of PolicyAction.frameSplitToggle:
    model.tabTreeCommand(output, TabTreeCommand.splitToggle)
  of PolicyAction.frameUnsplit:
    model.tabTreeCommand(output, TabTreeCommand.unsplit)
  of PolicyAction.frameTabNext:
    model.tabTreeCommand(output, TabTreeCommand.nextTab)
  of PolicyAction.frameTabPrevious:
    model.tabTreeCommand(output, TabTreeCommand.previousTab)
  of PolicyAction.frameFocusParent:
    model.tabTreeCommand(output, TabTreeCommand.focusParent)
  of PolicyAction.frameFocusChild:
    model.tabTreeCommand(output, TabTreeCommand.focusChild)
  of PolicyAction.frameResizeLeft:
    model.tabTreeCommand(output, TabTreeCommand.resizeLeft)
  of PolicyAction.treeFocusLeft:
    model.tabTreeCommand(output, TabTreeCommand.focusLeft)
  of PolicyAction.treeMoveLeft:
    model.tabTreeCommand(output, TabTreeCommand.moveLeft)
  of PolicyAction.frameResizeRight:
    model.tabTreeCommand(output, TabTreeCommand.resizeRight)
  of PolicyAction.treeFocusRight:
    model.tabTreeCommand(output, TabTreeCommand.focusRight)
  of PolicyAction.treeMoveRight:
    model.tabTreeCommand(output, TabTreeCommand.moveRight)
  of PolicyAction.frameResizeUp:
    model.tabTreeCommand(output, TabTreeCommand.resizeUp)
  of PolicyAction.treeFocusUp:
    model.tabTreeCommand(output, TabTreeCommand.focusUp)
  of PolicyAction.treeMoveUp:
    model.tabTreeCommand(output, TabTreeCommand.moveUp)
  of PolicyAction.frameResizeDown:
    model.tabTreeCommand(output, TabTreeCommand.resizeDown)
  of PolicyAction.treeFocusDown:
    model.tabTreeCommand(output, TabTreeCommand.focusDown)
  of PolicyAction.treeMoveDown:
    model.tabTreeCommand(output, TabTreeCommand.moveDown)
  of PolicyAction.splitTreeHorizontal:
    model.tabTreeCommand(output, TabTreeCommand.layoutHorizontal)
  of PolicyAction.splitTreeVertical:
    model.tabTreeCommand(output, TabTreeCommand.layoutVertical)
  of PolicyAction.splitTreeTabbed:
    model.tabTreeCommand(output, TabTreeCommand.layoutTabbed)
  of PolicyAction.splitTreeStacking:
    model.tabTreeCommand(output, TabTreeCommand.layoutStacking)
  of PolicyAction.splitTreeToggleSplit:
    model.tabTreeCommand(output, TabTreeCommand.toggleSplit)
  of PolicyAction.splitTreeCycleAll:
    model.tabTreeCommand(output, TabTreeCommand.cycleAll)
  of PolicyAction.splitTreeSplitHorizontal:
    model.tabTreeCommand(output, TabTreeCommand.splitHorizontal)
  of PolicyAction.splitTreeSplitVertical:
    model.tabTreeCommand(output, TabTreeCommand.splitVertical)
  of PolicyAction.splitTreeSplitToggle:
    model.tabTreeCommand(output, TabTreeCommand.splitToggle)
  of PolicyAction.splitFocusParent:
    model.tabTreeCommand(output, TabTreeCommand.focusParent)
  of PolicyAction.splitFocusChild:
    model.tabTreeCommand(output, TabTreeCommand.focusChild)
  of PolicyAction.splitNextSibling:
    model.tabTreeCommand(output, TabTreeCommand.nextSibling)
  of PolicyAction.splitPreviousSibling:
    model.tabTreeCommand(output, TabTreeCommand.previousSibling)
  of PolicyAction.splitTreeDefault:
    model.tabTreeCommand(output, TabTreeCommand.layoutHorizontal)
  of PolicyAction.selectDwindleLayout:
    model.setLayout(output, LayoutMode.dwindle)
  of PolicyAction.dwindlePreselectLeft:
    model.tabTreeCommand(output, TabTreeCommand.preselectLeft)
  of PolicyAction.dwindlePreselectRight:
    model.tabTreeCommand(output, TabTreeCommand.preselectRight)
  of PolicyAction.dwindlePreselectUp:
    model.tabTreeCommand(output, TabTreeCommand.preselectUp)
  of PolicyAction.dwindlePreselectDown:
    model.tabTreeCommand(output, TabTreeCommand.preselectDown)
