import std/[options, unittest]
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
