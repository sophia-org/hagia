import std/[options, sequtils, unittest]

import policy/[actions, recent_windows, reducer, state]
import entities/recent_windows_ops
import systems/recent_windows
import types/[actions, core, model, policy_messages, recent_windows]

## The recent-windows switcher's pure policy: niri's order and selection rules,
## commit and cancel, and the strip layout. Sophia's chord lifecycle drives
## `showRecentWindows` (Held) and `commitRecentWindows` (Ended); here they are
## called directly.

proc capabilities(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

proc userFocus(model: var PolicyModel, output: OutputId, window: WindowId) =
  ## A focus the operator chose: one cause, recorded once it settles.
  model.setFocus(output, window)
  model.noteRecentFocus()

proc threeWindows(): (PolicyModel, OutputId, seq[WindowId]) =
  ## Focused in order a, b, c, so the most recent order is c, b, a.
  var model = initPolicyModel()
  let output = model.addOutput(Rect(width: 1920, height: 1080))
  var windows: seq[WindowId]
  for _ in 0 ..< 3:
    let window = model.addWindow(output, capabilities(), SizeConstraints())
    model.userFocus(output, window)
    windows.add(window)
  (model, output, windows)

proc focused(model: PolicyModel, output: OutputId): WindowId =
  model.output(output).get().focusedWindow

suite "recent-windows switcher":
  test "candidates are most recently focused first":
    var (model, output, windows) = threeWindows()
    check model.recentWindowCandidates(RecentWindowScope.all) ==
      @[windows[2], windows[1], windows[0]]
    model.userFocus(output, windows[0])
    check model.recentWindowCandidates(RecentWindowScope.all) ==
      @[windows[0], windows[2], windows[1]]

  test "the first press already selects the previous window, invisibly":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    check model.recentWindows.active
    check not model.recentWindows.visible
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[1]
    check model.recentWindowStrip().isNone
    model.validate()

  test "previous opens on the oldest entry and both directions wrap":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowPrevious)
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[0]
    model.applyAction(output, PolicyAction.recentWindowPrevious)
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[1]
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.applyAction(output, PolicyAction.recentWindowNext)
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[2]
    model.applyAction(output, PolicyAction.recentWindowNext)
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[1]

  test "a quick tap commits without ever being drawn":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model = model.reducePolicy(
      PolicyMsg(
        kind: PolicyMsgKind.action,
        output: output,
        action: PolicyAction.recentWindowConfirm,
      )
    ).candidate
    check model.focused(output) == windows[1]
    check not model.recentWindows.active
    check model.recentFocus[^1] == windows[1]
    model.validate()

  test "held shows the strip and release commits the cycled selection":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.showRecentWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    let strip = model.recentWindowStrip()
    check strip.isSome
    check strip.get().previews.mapIt(it.window) == @[windows[2], windows[1], windows[0]]
    model.commitRecentWindows()
    check model.focused(output) == windows[0]
    check model.recentWindowStrip().isNone

  test "cancel and any other action close without moving focus":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.applyAction(output, PolicyAction.recentWindowCancel)
    check not model.recentWindows.active
    check model.focused(output) == windows[2]
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.applyAction(output, PolicyAction.toggleOverview)
    check not model.recentWindows.active
    check model.overview.active
    model.applyAction(output, PolicyAction.recentWindowNext)
    check not model.overview.active
    model.validate()

  test "closing an offered window keeps selection on its left neighbour":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.applyAction(output, PolicyAction.recentWindowNext)
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[0]
    model.removeWindow(windows[0])
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[1]
    check windows[0] notin model.recentFocus
    model.validate()
    model.removeWindow(windows[1])
    model.removeWindow(windows[2])
    check not model.recentWindows.active
    model.validate()

  test "focus that is not the operator's does not reorder the history":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1200, height: 900))
    let right = model.addOutput(Rect(x: 1200, width: 1600, height: 1000))
    let older = model.addWindow(left, capabilities(), SizeConstraints())
    let away = model.addWindow(right, capabilities(), SizeConstraints())
    let current = model.addWindow(left, capabilities(), SizeConstraints())
    model.userFocus(left, older)
    model.userFocus(right, away)
    model.userFocus(left, current)
    # Restoring the other output's remembered focus, as reconciliation does,
    # makes that output active; it is put back and the cause settles.
    model.setFocus(right, away)
    model.setActiveOutput(left)
    model.noteRecentFocus()
    check model.recentWindowCandidates(RecentWindowScope.all) == @[current, away, older]

  test "an empty desk does not open the switcher":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1920, height: 1080))
    model.applyAction(output, PolicyAction.recentWindowNext)
    check not model.recentWindows.active

  test "a window never focused follows the focused ones":
    var (model, output, windows) = threeWindows()
    let background = model.addWindow(output, capabilities(), SizeConstraints())
    model.userFocus(output, windows[2])
    check model.recentWindowCandidates(RecentWindowScope.all)[^1] == background

  test "commit reaches a window on a hidden workspace of another output":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1200, height: 900))
    let right = model.addOutput(Rect(x: 1200, width: 1600, height: 1000))
    model.ensureViewCount(right, 2)
    let rightViews = model.output(right).get().views
    model.activateView(right, rightViews[1])
    let hidden = model.addWindow(right, capabilities(), SizeConstraints())
    model.userFocus(right, hidden)
    model.activateView(right, rightViews[0])
    let current = model.addWindow(left, capabilities(), SizeConstraints())
    model.userFocus(left, current)
    model.applyAction(left, PolicyAction.recentWindowNext)
    check model.recentWindows.candidates[model.recentWindows.selected] == hidden
    model.commitRecentWindows()
    check model.activeOutput == right
    check model.output(right).get().activeView == rightViews[1]
    check model.focused(right) == hidden
    model.validate()

  test "scopes narrow the candidates to the active workspace or output":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1200, height: 900))
    let right = model.addOutput(Rect(x: 1200, width: 1600, height: 1000))
    model.ensureViewCount(left, 2)
    let leftViews = model.output(left).get().views
    let other = model.addWindow(right, capabilities(), SizeConstraints())
    model.userFocus(right, other)
    model.activateView(left, leftViews[1])
    let hidden = model.addWindow(left, capabilities(), SizeConstraints())
    model.userFocus(left, hidden)
    model.activateView(left, leftViews[0])
    let shown = model.addWindow(left, capabilities(), SizeConstraints())
    model.userFocus(left, shown)
    check model.recentWindowCandidates(RecentWindowScope.workspace) == @[shown]
    check model.recentWindowCandidates(RecentWindowScope.output) == @[shown, hidden]
    check model.recentWindowCandidates(RecentWindowScope.all) == @[shown, hidden, other]

  test "minimized windows are not offered":
    var (model, output, windows) = threeWindows()
    model.minimizeFocused()
    check windows[2] notin model.recentWindowCandidates(RecentWindowScope.all)
    check model.recentWindowCandidates(RecentWindowScope.all).len == 2
    discard output

  test "pointer selection picks an offered preview and refuses others":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.selectRecentWindow(windows[0])
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[0]
    expect PolicyStateError:
      model.selectRecentWindow(WindowId(999))

suite "recent-windows strip layout":
  test "previews keep aspect within niri's bounds and centre when they fit":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.showRecentWindows()
    let before = model.clone()
    let strip = model.recentWindowStrip().get()
    check model == before
    check strip.output == output
    for preview in strip.previews:
      check preview.geometry.height <= recentWindowsMaxHeight
      check preview.geometry.height <= 1080 div 2
      check preview.geometry.y + preview.geometry.height div 2 in 539 .. 541
    let first = strip.previews[0].geometry
    let last = strip.previews[^1].geometry
    let left = first.x
    let right = 1920 - (last.x + last.width)
    check abs(left - right) <= 1
    let selected = strip.previews[1].geometry
    check strip.highlight.x == selected.x - recentWindowsPadding
    check strip.highlight.width == selected.width + 2 * recentWindowsPadding
    discard windows

  test "a strip wider than the output scrolls to keep the selection clear":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1920, height: 1080))
    for _ in 0 ..< 12:
      let window = model.addWindow(output, capabilities(), SizeConstraints())
      model.userFocus(output, window)
    for _ in 0 ..< 6:
      model.applyAction(output, PolicyAction.recentWindowNext)
    model.showRecentWindows()
    let strip = model.recentWindowStrip().get()
    let selected = strip.previews[model.recentWindows.selected].geometry
    check selected.x >= recentWindowsStrut
    check selected.x + selected.width <= 1920 - recentWindowsStrut
    check strip.previews[0].geometry.x <= recentWindowsStrut
    check strip.previews[^1].geometry.x + strip.previews[^1].geometry.width >=
      1920 - recentWindowsStrut
