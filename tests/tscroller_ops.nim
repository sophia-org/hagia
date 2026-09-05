import std/[options, unittest]

import policy/[actions, entity_store, projection, state]
import types/[actions, core, model]

## A scroller driven by sequences of operations, with its invariants checked
## after every one.
##
## Individual tests pin the defects we already know about. This is for the
## ones we do not: it applies operations in orders nobody thought to try and
## asks, each time, whether the layout still means anything. niri tests its
## scrolling layout the same way -- `check_ops_on_layout` in
## `src/layout/tests.rs` applies an operation and calls `verify_invariants`,
## over and over -- and the pattern ports well here because Hagia's model is
## pure data with no clock and no animation state to settle.
##
## The generator is a seeded LCG rather than a property-testing library. It
## needs no dependency, and a failure prints the seed that produced it, so the
## sequence can be replayed exactly and pinned as an ordinary test.

type ScrollerOp = enum
  ## What can happen to a scroller. Every one of these is something a person
  ## can do; the point is the orders they can do them in.
  openWindow
  closeFocusedWindow
  focusNextColumn
  focusPreviousColumn
  focusFirstColumn
  focusLastColumn
  moveColumnNext
  moveColumnPrevious
  growFocusedColumn
  shrinkFocusedColumn
  cycleWidthForward
  cycleWidthBack
  maximizeFocusedColumn
  expandFocusedColumnWidth
  centerFocusedColumn
  centerVisibleRun
  consumeIntoColumn
  expelFromColumn
  switchToTile
  switchToScroller
  switchToVerticalScroller

proc focusableCapabilities(): WindowCapabilities =
  WindowCapabilities(
    movable: true, resizable: true, focusable: true, fullscreenable: true
  )

proc validateScroller(
    model: PolicyModel, outputId: OutputId, seed: uint64, step: int, op: ScrollerOp
) =
  ## What a scroller promises, whatever has been done to it.
  ##
  ## `model.validate()` already covers the logical model. These are the facts
  ## that only a strip has, and each one is here because losing it would be
  ## visible: columns that overlap draw on top of each other, a column past
  ## the bounds cannot be placed at all, and a focused column off screen is a
  ## window receiving keys that nobody can see.
  ##
  ## Only the horizontal scroller is checked here. The vertical one is the
  ## same machine seen from ninety degrees away, so the same invariants hold
  ## of it through the transpose; sequences still switch into it, because the
  ## bugs worth finding are in the switching.
  # Printed only when something below fails, which is what makes a failure
  # replayable: the seed and step reproduce the exact sequence.
  checkpoint("seed=" & $seed & " step=" & $step & " op=" & $op)
  if model.views[model.outputs[outputId].activeView].layout != LayoutMode.scroller:
    return
  let (outerGap, innerGap) = model.effectiveGaps()
  let strip = model.scrollerStrip(outputId, outerGap, innerGap)
  var previousRight = int64(low(int32))
  for index, position in strip.positions:
    check strip.widths[index] >= 1
    # Columns are laid left to right and never overlap: the strip is an order,
    # and two columns sharing a coordinate would make it meaningless.
    check int64(position) >= previousRight
    previousRight = int64(position) + int64(strip.widths[index])
    # Every edge has to be a coordinate a placement can carry.
    check previousRight <= int64(high(int32))

  let projected = model.projectScroller([outputId], outerGap, innerGap)[0]
  check (projected.placements.len > 0) == (strip.positions.len > 0)

  if strip.focused >= 0:
    let offset = projected.viewportOffset
    let left = int64(strip.positions[strip.focused]) - int64(offset)
    let right = left + int64(strip.widths[strip.focused])
    if strip.widths[strip.focused] <= strip.usableWidth:
      # The focused column is on screen. Nothing else keeps a focused window
      # reachable: Sophia routes keys to whatever holds focus without asking
      # whether it can be seen, so if the camera fails to reveal it the
      # operator is typing into a window that is not there.
      check left >= 0
      check right <= int64(strip.usableWidth)
    else:
      # A column wider than the screen cannot be shown whole, so its left edge
      # is what gets shown, as niri does.
      check left == 0

proc applyOp(model: var PolicyModel, outputId: OutputId, op: ScrollerOp) =
  case op
  of openWindow:
    let window = model.addWindow(outputId, focusableCapabilities(), SizeConstraints())
    model.setFocus(outputId, window)
  of closeFocusedWindow:
    let focused = model.outputs[outputId].focusedWindow
    if focused != nullWindowId:
      model.removeWindow(focused)
  of focusNextColumn:
    model.applyAction(outputId, PolicyAction.focusColumnNext)
  of focusPreviousColumn:
    model.applyAction(outputId, PolicyAction.focusColumnPrevious)
  of focusFirstColumn:
    model.applyAction(outputId, PolicyAction.focusColumnFirst)
  of focusLastColumn:
    model.applyAction(outputId, PolicyAction.focusColumnLast)
  of moveColumnNext:
    model.applyAction(outputId, PolicyAction.moveColumnNext)
  of moveColumnPrevious:
    model.applyAction(outputId, PolicyAction.moveColumnPrevious)
  of growFocusedColumn:
    model.applyAction(outputId, PolicyAction.growColumn)
  of shrinkFocusedColumn:
    model.applyAction(outputId, PolicyAction.shrinkColumn)
  of cycleWidthForward:
    model.applyAction(outputId, PolicyAction.cycleColumnWidth)
  of cycleWidthBack:
    model.applyAction(outputId, PolicyAction.cycleColumnWidthBack)
  of maximizeFocusedColumn:
    model.applyAction(outputId, PolicyAction.maximizeColumn)
  of expandFocusedColumnWidth:
    model.applyAction(outputId, PolicyAction.expandColumnToAvailableWidth)
  of centerFocusedColumn:
    model.applyAction(outputId, PolicyAction.centerColumn)
  of centerVisibleRun:
    model.applyAction(outputId, PolicyAction.centerVisibleColumns)
  of consumeIntoColumn:
    model.applyAction(outputId, PolicyAction.consumeNextColumn)
  of expelFromColumn:
    model.applyAction(outputId, PolicyAction.expelFocusedWindow)
  of switchToTile:
    model.views[model.outputs[outputId].activeView].layout = LayoutMode.tile
  of switchToScroller:
    model.views[model.outputs[outputId].activeView].layout = LayoutMode.scroller
  of switchToVerticalScroller:
    model.views[model.outputs[outputId].activeView].layout = LayoutMode.verticalScroller

proc runOps(
    seed: uint64, centering: CenterFocusedColumn, single: bool, steps: int
): int =
  ## Apply `steps` operations and check the invariants after each. Returns the
  ## number of operations that were actually applied, so a run that spends its
  ## whole sequence on an empty workspace is visible rather than silently
  ## passing.
  var model = initPolicyModel()
  model.settings.centerFocusedColumn = centering
  model.settings.alwaysCenterSingleColumn = single
  let outputId = model.addOutput(Rect(width: 2560, height: 1440))
  var state = seed or 1'u64
  for step in 1 .. steps:
    # A plain linear congruential generator. Deterministic, dependency-free,
    # and the seed is all anyone needs to replay a failure.
    state = state * 6364136223846793005'u64 + 1442695040888963407'u64
    let op = ScrollerOp(int((state shr 33) mod uint64(ord(high(ScrollerOp)) + 1)))
    applyOp(model, outputId, op)
    model.validate()
    validateScroller(model, outputId, seed, step, op)
    inc result
    # The camera is stored between projections in the running session, so the
    # harness has to store it too or it would be testing a scroller that
    # forgets where it is looking.
    if model.views[model.outputs[outputId].activeView].layout == LayoutMode.scroller:
      let (outerGap, innerGap) = model.effectiveGaps()
      let projected = model.projectScroller([outputId], outerGap, innerGap)[0]
      if projected.cameraDecided:
        model.rememberViewportOffset(outputId, projected.viewportOffset)

suite "scroller operation sequences":
  test "the invariants hold across every centring mode":
    ## The overflow rule only exists in one of the three modes, so a harness
    ## that ran a single mode would not reach it.
    for centering in CenterFocusedColumn:
      for single in [false, true]:
        for seed in 1'u64 .. 40'u64:
          let applied = runOps(seed, centering, single, 60)
          check applied == 60

  test "a long sequence does not accumulate damage":
    ## Short runs find ordering mistakes; a long one finds the state that only
    ## goes wrong after enough has happened to it.
    for seed in 1'u64 .. 8'u64:
      discard runOps(seed, CenterFocusedColumn.onOverflow, true, 600)

  test "the invariants survive a column pushed to either extreme":
    ## Random sequences reach the width bounds too rarely to test them: at one
    ## op in twenty, sixty steps buy about three presses where the ceiling is
    ## a hundred and ninety away. Directed runs go where the dice will not.
    for direction in [PolicyAction.growColumn, PolicyAction.shrinkColumn]:
      var model = initPolicyModel()
      let outputId = model.addOutput(Rect(width: 2560, height: 1440))
      for _ in 0 ..< 3:
        let window =
          model.addWindow(outputId, focusableCapabilities(), SizeConstraints())
        model.setFocus(outputId, window)
      for step in 1 .. 400:
        model.applyAction(outputId, direction)
        model.validate()
        validateScroller(model, outputId, 0'u64, step, growFocusedColumn)
      let column = model.window(model.outputs[outputId].focusedWindow).get().column
      let reached = model.columns[column].widthScale
      if direction == PolicyAction.growColumn:
        check reached == maximumScale
      else:
        check reached == minimumScale

  test "opening many windows keeps every column reachable":
    test "opening many windows keeps every column reachable":
      ## The strip outgrows the screen quickly, and focus wrapping is what makes
      ## the far end reachable. Walking the whole strip proves every column can
      ## be brought into view, which is the guarantee that makes an off-screen
      ## column ordinary rather than lost.
      var model = initPolicyModel()
      let outputId = model.addOutput(Rect(width: 2560, height: 1440))
      var opened: seq[WindowId]
      for _ in 0 ..< 12:
        opened.add(
          model.addWindow(outputId, focusableCapabilities(), SizeConstraints())
        )
      let (outerGap, innerGap) = model.effectiveGaps()
      for window in opened:
        model.setFocus(outputId, window)
        let projected = model.projectScroller([outputId], outerGap, innerGap)[0]
        model.rememberViewportOffset(outputId, projected.viewportOffset)
        let strip = model.scrollerStrip(outputId, outerGap, innerGap)
        require strip.focused >= 0
        let left =
          int64(strip.positions[strip.focused]) - int64(projected.viewportOffset)
        check left >= 0
        check left + int64(strip.widths[strip.focused]) <= int64(strip.usableWidth)
      model.validate()
