import std/[options, sequtils, unittest]

import policy/[actions, recent_windows, reducer, state]
import state/values
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

  test "first and last jump to the ends and leave a closed switcher closed":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowLast)
    check not model.recentWindows.active
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.applyAction(output, PolicyAction.recentWindowLast)
    check model.recentWindows.active
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[0]
    model.applyAction(output, PolicyAction.recentWindowFirst)
    check model.recentWindows.candidates[model.recentWindows.selected] == windows[2]
    model.validate()

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

  test "a scope change keeps the selection, or the nearest one to its left":
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
    proc selected(model: PolicyModel): WindowId =
      model.recentWindows.candidates[model.recentWindows.selected]

    # Closed: a scope key does nothing.
    model.applyAction(left, PolicyAction.recentWindowScopeOutput)
    check model.recentWindows.scope == RecentWindowScope.all
    model.applyAction(left, PolicyAction.recentWindowNext)
    check model.selected() == hidden
    model.applyAction(left, PolicyAction.recentWindowScopeOutput)
    check model.recentWindows.candidates == @[shown, hidden]
    check model.selected() == hidden
    model.applyAction(left, PolicyAction.recentWindowScopeWorkspace)
    check model.recentWindows.candidates == @[shown]
    check model.selected() == shown
    model.applyAction(left, PolicyAction.recentWindowScopeAll)
    model.applyAction(left, PolicyAction.recentWindowLast)
    check model.selected() == other
    model.applyAction(left, PolicyAction.recentWindowScopeOutput)
    check model.selected() == hidden
    # Cycle: output, then all, then workspace.
    model.applyAction(left, PolicyAction.recentWindowScopeCycle)
    check model.recentWindows.scope == RecentWindowScope.all
    model.applyAction(left, PolicyAction.recentWindowScopeCycle)
    check model.recentWindows.scope == RecentWindowScope.workspace
    check model.recentWindows.active
    model.validate()

  test "an empty scope leaves the switcher open, empty and cycling":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1200, height: 900))
    model.ensureViewCount(left, 2)
    let leftViews = model.output(left).get().views
    let first = model.addWindow(left, capabilities(), SizeConstraints())
    model.userFocus(left, first)
    model.activateView(left, leftViews[1])
    let second = model.addWindow(left, capabilities(), SizeConstraints())
    model.userFocus(left, second)
    model.activateView(left, leftViews[0])
    model.applyAction(left, PolicyAction.recentWindowNext)
    # The active workspace loses its only window while the switcher is open.
    model.removeWindow(first)
    check model.recentWindows.active
    model.applyAction(left, PolicyAction.recentWindowScopeWorkspace)
    check model.recentWindows.scope == RecentWindowScope.workspace
    check model.recentWindows.active
    check model.recentWindows.candidates.len == 0
    model.validate()
    # Stepping, first and last do nothing; nothing is selected.
    model.applyAction(left, PolicyAction.recentWindowNext)
    model.applyAction(left, PolicyAction.recentWindowPrevious)
    model.applyAction(left, PolicyAction.recentWindowLast)
    check model.recentWindows.candidates.len == 0
    check model.recentWindows.selected == 0
    model.validate()
    # Cycling passes through the empty scope and repopulates.
    model.applyAction(left, PolicyAction.recentWindowScopeCycle)
    check model.recentWindows.scope == RecentWindowScope.output
    check model.recentWindows.candidates == @[second]
    model.applyAction(left, PolicyAction.recentWindowScopeWorkspace)
    check model.recentWindows.candidates.len == 0
    # Confirming an empty switcher closes it and moves no focus.
    let focusedBefore = model.focused(left)
    model.applyAction(left, PolicyAction.recentWindowConfirm)
    check not model.recentWindows.active
    check model.focused(left) == focusedBefore
    model.validate()

  test "an empty switcher on a narrow output lays out an empty strip":
    var model = initPolicyModel()
    # Narrower than the two struts the scrolling layout keeps.
    let narrow = model.addOutput(Rect(width: 300, height: 600))
    let other = model.addOutput(Rect(x: 300, width: 1600, height: 1000))
    let window = model.addWindow(other, capabilities(), SizeConstraints())
    model.userFocus(other, window)
    model.setActiveOutput(narrow)
    model.applyAction(narrow, PolicyAction.recentWindowNext)
    model.showRecentWindows()
    model.applyAction(narrow, PolicyAction.recentWindowScopeOutput)
    check model.recentWindows.candidates.len == 0
    let strip = model.recentWindowStrip()
    check strip.isSome
    check strip.get().previews.len == 0
    check strip.get().highlight == Rect()
    model.validate()

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

suite "recent-windows chord ownership":
  test "a closed switcher releases its chords; their events act on nothing":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    let first = model.claimRecentChord()
    model.applyAction(output, PolicyAction.recentWindowCancel)
    check not model.ownsRecentChord(first)
    model.applyAction(output, PolicyAction.recentWindowNext)
    let second = model.claimRecentChord()
    check second != first
    model.observeRecentChordHeld(first)
    check not model.recentWindows.visible
    model.observeRecentChordEnded(first, released = true)
    check model.recentWindows.active
    check model.focused(output) == windows[2]
    model.observeRecentChordHeld(second)
    check model.recentWindows.visible
    model.observeRecentChordEnded(second, released = true)
    check model.focused(output) == windows[1]
    check model.recentWindows.owners.len == 0
    model.validate()

  test "an owner ended otherwise closes without moving focus":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    discard model.claimRecentChord()
    let second = model.claimRecentChord()
    model.observeRecentChordEnded(second, released = false)
    check not model.recentWindows.active
    check model.recentWindows.owners.len == 0
    check model.focused(output) == windows[2]
    model.validate()

  test "owners stay within the bound Sophia can owe":
    var (model, output, _) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    for _ in 1 .. maxRecentWindowChords:
      check model.claimRecentChord() != nullRecentChordId
      model.validate()
    check model.claimRecentChord() == nullRecentChordId
    check model.recentWindows.owners.len == maxRecentWindowChords
    model.recentWindows.owners.setLen(maxRecentWindowChords - 1)
    model.recentWindows.owners.add(model.recentWindows.owners[0])
    expect PolicyStateError:
      model.validate()

  test "identities are issued once and never by a closed switcher":
    var (model, output, _) = threeWindows()
    check model.claimRecentChord() == nullRecentChordId
    check model.recentWindows.lastChord == 0
    var issued: seq[RecentChordId]
    for _ in 0 ..< 3:
      model.applyAction(output, PolicyAction.recentWindowNext)
      issued.add(model.claimRecentChord())
      model.applyAction(output, PolicyAction.recentWindowCancel)
    check issued.deduplicate().len == 3
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.recentWindows.owners.add(RecentChordId(model.recentWindows.lastChord + 1))
    expect PolicyStateError:
      model.validate()

  test "more owners than the bound are refused":
    var (model, output, _) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.recentWindows.lastChord = 10
    for chord in 1'u32 .. 10:
      model.recentWindows.owners.add(RecentChordId(chord))
    expect PolicyStateError:
      model.validate()

  test "a new connection closes only a switcher its chords owned":
    var (model, output, windows) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    discard model.claimRecentChord()
    model.forgetRecentChords()
    check not model.recentWindows.active
    check model.recentWindows.owners.len == 0
    check model.focused(output) == windows[2]
    # A modal switcher is not the chords' to close.
    model.applyAction(output, PolicyAction.recentWindowNext)
    model.forgetRecentChords()
    check model.recentWindows.active
    model.validate()

  test "cloned ownership is independent":
    var (model, output, _) = threeWindows()
    model.applyAction(output, PolicyAction.recentWindowNext)
    let first = model.claimRecentChord()
    var candidate = model.clone()
    discard candidate.claimRecentChord()
    check model.recentWindows.owners == @[first]
    candidate.applyAction(output, PolicyAction.recentWindowCancel)
    check model.recentWindows.owners == @[first]

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
