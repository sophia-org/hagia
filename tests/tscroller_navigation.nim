import std/unittest
import policy/[actions, entity_store, projection, state]
import types/[actions, core, model]

proc caps(): WindowCapabilities =
  WindowCapabilities(movable: true, resizable: true, focusable: true)

proc commitCamera(model: var PolicyModel, output: OutputId): int32 =
  let projected = model.projectLayout([output], 8, 8)[0]
  model.rememberViewportOffset(output, projected.viewportOffset, projected.camera)
  projected.viewportOffset

suite "Niri scrolling traces":
  test "overflow uses the committed incoming column and redraw is stable":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 2560, height: 1440))
    var windows: seq[WindowId]
    for i in 0 .. 2:
      windows.add(model.addWindow(output, caps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
      discard model.commitCamera(output)
    model.setColumnWidthScale(model.windows[windows[0]].column, Scale(49152))
    discard model.commitCamera(output)
    model.setFocus(output, windows[1])
    check model.commitCamera(output) == 1894
    for i in 0 .. 3:
      check model.commitCamera(output) == 1894

  test "insert after focus and close returns to the opening view":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 2560, height: 1440))
    var windows: seq[WindowId]
    for i in 0 .. 2:
      windows.add(model.addWindow(output, caps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
      discard model.commitCamera(output)
    model.setFocus(output, windows[1])
    let before = model.commitCamera(output)
    let inserted = model.addWindow(output, caps(), SizeConstraints())
    check model.tiledColumnIds(output) ==
      @[
        model.windows[windows[0]].column,
        model.windows[windows[1]].column,
        model.windows[inserted].column,
        model.windows[windows[2]].column,
      ]
    model.setFocus(output, inserted)
    discard model.commitCamera(output)
    model.removeWindow(inserted)
    check model.outputs[output].focusedWindow == windows[1]
    check model.commitCamera(output) == before

  test "removing an earlier column preserves the focused window position":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 2560, height: 1440))
    var windows: seq[WindowId]
    for i in 0 .. 3:
      windows.add(model.addWindow(output, caps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
      discard model.commitCamera(output)
    let before = model.projectLayout([output], 8, 8)[0].placements[^1].geometry.x
    model.removeWindow(windows[0])
    discard model.commitCamera(output)
    check model.projectLayout([output], 8, 8)[0].placements[^1].geometry.x == before

  test "directional navigation stops and explicit cycling still cycles":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 900))
    let first = model.addWindow(output, caps(), SizeConstraints())
    let last = model.addWindow(output, caps(), SizeConstraints())
    model.setFocus(output, first)
    model.applyAction(output, PolicyAction.focusColumnPrevious)
    check model.outputs[output].focusedWindow == first
    model.setFocus(output, last)
    model.applyAction(output, PolicyAction.focusColumnNext)
    check model.outputs[output].focusedWindow == last
    model.focusRelative(output, 1)
    check model.outputs[output].focusedWindow == first

  test "vertical and horizontal camera anchors remain independent":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    var windows: seq[WindowId]
    for i in 0 .. 2:
      windows.add(model.addWindow(output, caps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
      discard model.commitCamera(output)
    let view = model.outputs[output].activeView
    let horizontal = model.views[view].camera
    model.views[view].layout = LayoutMode.verticalScroller
    discard model.commitCamera(output)
    check model.views[view].camera == horizontal
    check model.views[view].cameraY.column == model.windows[windows[^1]].column
    model.validate()

suite "navigation across an empty display":
  ## Stepping off the end of a strip hands focus to the display on that side.
  ## An empty one has no columns, and an early return for "no columns" makes
  ## that a one-way trip: the operator arrives on a monitor with nothing on it
  ## and the opposite arrow cannot bring them back.

  test "an empty display can be stepped off again in either direction":
    for direction in [1, -1]:
      var model = initPolicyModel()
      let first = model.addOutput(Rect(width: 1600, height: 1000))
      let second = model.addOutput(Rect(x: 1600, width: 1280, height: 1024))
      let (populated, empty) =
        if direction == 1:
          (first, second)
        else:
          (second, first)
      let window = model.addWindow(populated, caps(), SizeConstraints())
      model.setFocus(populated, window)

      model.focusColumnRelative(populated, direction)
      check model.activeOutput == empty
      check model.outputs[empty].focusedWindow == nullWindowId

      model.focusColumnRelative(empty, -direction)
      check model.activeOutput == populated
      check model.outputs[populated].focusedWindow == window
      model.validate()

  test "an empty display between two others is crossed, not fallen into":
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1280, height: 1024))
    let middle = model.addOutput(Rect(x: 1280, width: 1280, height: 1024))
    let right = model.addOutput(Rect(x: 2560, width: 1280, height: 1024))
    let leftWindow = model.addWindow(left, caps(), SizeConstraints())
    let rightWindow = model.addWindow(right, caps(), SizeConstraints())
    model.setFocus(right, rightWindow)
    model.setFocus(left, leftWindow)

    # Left to middle: empty, so nothing takes focus but the display is active.
    model.focusColumnRelative(left, 1)
    check model.activeOutput == middle
    check model.outputs[middle].focusedWindow == nullWindowId

    # Middle to right: the window waiting there takes it.
    model.focusColumnRelative(middle, 1)
    check model.activeOutput == right
    check model.outputs[right].focusedWindow == rightWindow

    # And all the way back, one display at a time.
    model.focusColumnRelative(right, -1)
    check model.activeOutput == middle
    model.focusColumnRelative(middle, -1)
    check model.activeOutput == left
    check model.outputs[left].focusedWindow == leftWindow
    model.validate()

  test "one empty display steps to another and back":
    var model = initPolicyModel()
    let first = model.addOutput(Rect(width: 1280, height: 1024))
    let second = model.addOutput(Rect(x: 1280, width: 1280, height: 1024))
    check model.activeOutput == first

    model.focusColumnRelative(first, 1)
    check model.activeOutput == second
    check model.outputs[second].focusedWindow == nullWindowId

    model.focusColumnRelative(second, -1)
    check model.activeOutput == first
    check model.outputs[first].focusedWindow == nullWindowId
    model.validate()

  test "an empty display keeps what the display beside it remembered":
    ## Arriving back on a populated display restores the window it had, not
    ## whichever one the strip happens to start with.
    var model = initPolicyModel()
    let left = model.addOutput(Rect(width: 1600, height: 1000))
    let right = model.addOutput(Rect(x: 1600, width: 1280, height: 1024))
    # Both displays are on a workspace that is not their first, so a reset
    # would be visible rather than matching the default by accident.
    model.ensureViewCount(left, 3)
    model.ensureViewCount(right, 3)
    model.applyAction(right, PolicyAction.activateView3)
    model.applyAction(left, PolicyAction.activateView2)
    let leftView = model.outputs[left].activeView
    let rightView = model.outputs[right].activeView
    check leftView != model.outputs[left].views[0]
    check rightView != model.outputs[right].views[0]

    var windows: seq[WindowId]
    for _ in 0 .. 1:
      windows.add(model.addWindow(left, caps(), SizeConstraints()))
    model.setFocus(left, windows[1])

    model.focusColumnRelative(left, 1)
    check model.activeOutput == right
    model.focusColumnRelative(right, -1)
    check model.activeOutput == left
    check model.outputs[left].focusedWindow == windows[1]
    check model.outputs[left].activeView == leftView
    check model.outputs[right].activeView == rightView
    model.validate()

  test "a lone display has nowhere to hand focus to":
    var model = initPolicyModel()
    let only = model.addOutput(Rect(width: 1600, height: 1000))
    let window = model.addWindow(only, caps(), SizeConstraints())
    model.setFocus(only, window)
    for direction in [1, -1]:
      model.focusColumnRelative(only, direction)
      check model.activeOutput == only
      check model.outputs[only].focusedWindow == window
    model.validate()

  test "a lone empty display stays put":
    var model = initPolicyModel()
    let only = model.addOutput(Rect(width: 1600, height: 1000))
    for direction in [1, -1]:
      model.focusColumnRelative(only, direction)
      check model.activeOutput == only
      check model.outputs[only].focusedWindow == nullWindowId
    model.validate()
