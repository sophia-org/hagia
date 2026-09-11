## Dialogs that follow the window they belong to.
##
## A dialog's position is a rule, not a rectangle: it sits on its parent
## wherever the parent ends up this cycle -- scrolled, maximised, fullscreen,
## on a monitor whose origin is negative. The rule is evaluated inside the same
## projection that placed the parent, so nothing is stored between cycles and
## nothing arrives a frame late. The moment the operator moves or resizes the
## dialog, the rule is spent and the rectangle is theirs.

proc dialogCaps(): WindowCapabilities =
  WindowCapabilities(
    movable: true,
    resizable: true,
    focusable: true,
    closable: true,
    # Without this `toggle-fullscreen` is refused and a test that expected a
    # fullscreen window quietly measures an ordinary one.
    fullscreenable: true,
  )

proc dialogOn(
    model: var PolicyModel,
    outputId: OutputId,
    parent: WindowId,
    width, height: int32,
    constraints = SizeConstraints(),
): WindowId =
  ## A managed dialog admitted against a parent, the way reconciliation does it.
  result = model.addWindow(outputId, dialogCaps(), constraints)
  model.setWindowRelation(result, WindowKind.dialog, parent)
  model.placeTransient(result, parent, width, height, Rect())

proc placementFor(
    projection: LogicalOutputProjection, window: WindowId
): Option[LogicalPlacement] =
  for placement in projection.placements:
    if placement.window == window:
      return some(placement)
  none(LogicalPlacement)

proc stackIndex(projection: LogicalOutputProjection, window: WindowId): int =
  result = -1
  for index, placement in projection.placements:
    if placement.window == window:
      return index

suite "dialog placement follows its parent":
  test "a dialog centres on the parent's final geometry in the same cycle":
    ## The parent is a scroller column, so its rectangle is decided by the
    ## projection rather than stored anywhere. A dialog derived from a stale
    ## rectangle would sit where the column used to be.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 2560, height: 1440))
    var windows: seq[WindowId]
    for _ in 0 .. 2:
      windows.add(model.addWindow(output, dialogCaps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
    let dialog = model.dialogOn(output, windows[0], 400, 300)

    model.setFocus(output, windows[0])
    let projection = model.projectLayout([output], 8, 8)[0]
    let parent = projection.placementFor(windows[0]).get().geometry
    let child = projection.placementFor(dialog).get().geometry
    check child.width == 400
    check child.height == 300
    check child.x == parent.x + (parent.width - child.width) div 2
    check child.y == parent.y + (parent.height - child.height) div 2

    # Scroll the strip. The dialog moves with its column, with nothing stored
    # in between and no second projection needed.
    model.setFocus(output, windows[2])
    let scrolled = model.projectLayout([output], 8, 8)[0]
    let movedParent = scrolled.placementFor(windows[0]).get().geometry
    let movedChild = scrolled.placementFor(dialog).get().geometry
    check movedParent.x != parent.x
    # Centred on the parent where that fits, and held at the output edge once
    # the parent has scrolled far enough left that centring would not: a dialog
    # is kept reachable rather than followed off the screen.
    let centred = movedParent.x + (movedParent.width - movedChild.width) div 2
    check movedChild.x == max(0'i32, min(centred, 2560'i32 - movedChild.width))
    check movedChild.x + movedChild.width <= 2560

  test "an elevated parent carries its dialog and keeps it above":
    for elevate in ["maximized", "fullscreen"]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
      model.setFocus(output, parent)
      let dialog = model.dialogOn(output, parent, 300, 200)
      if elevate == "maximized":
        model.windows[parent].maximized = true
      else:
        model.windows[parent].fullscreen = true
      model.setFocus(output, parent)

      let projection = model.projectLayout([output], 8, 8)[0]
      let parentRect = projection.placementFor(parent).get().geometry
      let childRect = projection.placementFor(dialog).get().geometry
      check childRect.x == parentRect.x + (parentRect.width - childRect.width) div 2
      # Focus is on the parent, which the raise rule would otherwise put last.
      # A parent over its own dialog is the one arrangement that hides it.
      check projection.stackIndex(dialog) > projection.stackIndex(parent)

  test "a dialog on a monitor at a negative origin stays inside it":
    var model = initPolicyModel()
    discard model.addOutput(Rect(width: 2560, height: 1440))
    let left = model.addOutput(Rect(x: -1920, width: 1920, height: 1080))
    let parent = model.addWindow(left, dialogCaps(), SizeConstraints())
    model.setFocus(left, parent)
    let dialog = model.dialogOn(left, parent, 600, 400)

    let projection = model.projectLayout([left], 8, 8)[0]
    let child = projection.placementFor(dialog).get().geometry
    check child.x >= -1920
    check child.x + child.width <= 0
    check child.y >= 0

  test "a dialog larger than its output is clamped inside it":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 800, height: 600))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let dialog = model.dialogOn(
      output, parent, 2000, 1500, SizeConstraints(minWidth: 200, minHeight: 150)
    )

    let child =
      model.projectLayout([output], 8, 8)[0].placementFor(dialog).get().geometry
    check child.x >= 0
    check child.y >= 0
    # Shrunk to the screen, not merely repositioned on it.
    check child.width <= 800
    check child.height <= 600
    check child.width >= 200
    check child.height >= 150

    # A minimum that cannot fit is honoured anyway: the client cannot draw
    # smaller, so the dialog overhangs and its top-left corner stays reachable.
    let cramped = model.dialogOn(
      output, parent, 900, 700, SizeConstraints(minWidth: 900, minHeight: 700)
    )
    let wide =
      model.projectLayout([output], 8, 8)[0].placementFor(cramped).get().geometry
    check wide.width == 900
    check wide.x == 0
    check wide.y == 0

  test "a moved dialog keeps its position when the parent moves":
    ## The operator's placement is a decision, not a rule, so a later parent
    ## move must not recompute it.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 2560, height: 1440))
    var windows: seq[WindowId]
    for _ in 0 .. 2:
      windows.add(model.addWindow(output, dialogCaps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
    let dialog = model.dialogOn(output, windows[0], 400, 300)
    model.setFocus(output, windows[0])

    let pinned = Rect(x: 40, y: 60, width: 400, height: 300)
    model.setFloatingGeometry(output, dialog, pinned)
    check model.windows[dialog].floatingIntent == FloatingIntent.manual
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).get().geometry ==
      pinned

    model.setFocus(output, windows[2])
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).get().geometry ==
      pinned
    model.validate()

  test "a nested dialog follows the dialog it belongs to":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let dialog = model.dialogOn(output, parent, 600, 400)
    let nested = model.dialogOn(output, dialog, 200, 120)

    let projection = model.projectLayout([output], 8, 8)[0]
    let middle = projection.placementFor(dialog).get().geometry
    let inner = projection.placementFor(nested).get().geometry
    check inner.x == middle.x + (middle.width - inner.width) div 2
    check inner.y == middle.y + (middle.height - inner.height) div 2
    check projection.stackIndex(nested) > projection.stackIndex(dialog)
    check projection.stackIndex(dialog) > projection.stackIndex(parent)

  test "siblings stack by how recently each was focused":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let first = model.dialogOn(output, parent, 300, 200)
    let second = model.dialogOn(output, parent, 300, 200)

    model.setFocus(output, second)
    model.setFocus(output, first)
    var projection = model.projectLayout([output], 8, 8)[0]
    check projection.stackIndex(first) > projection.stackIndex(second)

    model.setFocus(output, second)
    projection = model.projectLayout([output], 8, 8)[0]
    check projection.stackIndex(second) > projection.stackIndex(first)

  test "a dialog goes with its parent, and unrelated focus does not take it":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let other = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, other)
    let dialog = model.dialogOn(output, parent, 300, 200)

    # Working in an unrelated window on the same screen leaves the dialog up.
    model.setFocus(output, other)
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).isSome

    # Minimising the parent takes it.
    model.windows[parent].minimized = true
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).isNone
    model.windows[parent].minimized = false
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).isSome

  test "the whole chain decides whether a nested dialog shows":
    ## A grandchild is not visible merely because its own parent is. Losing the
    ## window at the root of the family takes everything hanging off it.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let root = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, root)
    let middle = model.dialogOn(output, root, 600, 400)
    let leaf = model.dialogOn(output, middle, 200, 120)
    check model.projectLayout([output], 8, 8)[0].placementFor(leaf).isSome

    # Focus moves off the root first: minimising the focused window is a
    # separate transition and not what this case is about.
    let elsewhere = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, elsewhere)
    model.windows[root].minimized = true
    let hidden = model.projectLayout([output], 8, 8)[0]
    check hidden.placementFor(middle).isNone
    check hidden.placementFor(leaf).isNone
    model.windows[root].minimized = false
    check model.projectLayout([output], 8, 8)[0].placementFor(leaf).isSome

  test "closing a dialog on another monitor leaves the active one alone":
    ## Each output keeps its own focus record, so a dialog closing on a screen
    ## the operator is not looking at must settle that output's focus without
    ## moving them to it.
    var model = initPolicyModel()
    let here = model.addOutput(Rect(width: 1600, height: 1000))
    let there = model.addOutput(Rect(x: 1600, width: 1280, height: 1024))
    let mine = model.addWindow(here, dialogCaps(), SizeConstraints())
    let parent = model.addWindow(there, dialogCaps(), SizeConstraints())
    model.setFocus(there, parent)
    let sibling = model.dialogOn(there, parent, 300, 200)
    let closing = model.dialogOn(there, parent, 300, 200)
    model.setFocus(there, sibling)
    model.setFocus(there, closing)
    model.setFocus(here, mine)
    check model.activeOutput == here

    model.removeWindow(closing)
    check model.outputs[there].focusedWindow == sibling
    check model.activeOutput == here
    check model.outputs[here].focusedWindow == mine
    model.validate()

  test "a version-13 checkpoint keeps the geometry it stored":
    ## The field did not exist then, so the migration cannot know which
    ## positions were rules. Treating every one as the operator's is what keeps
    ## a restored session looking like the one that was saved.
    var adapter = initPolicyAdapter()
    var parentSurface = surface(1, 10)
    parentSurface.kind = 1
    var dialogSurface = surface(2, 10)
    dialogSurface.kind = 2
    dialogSurface.transientIndex = 1
    dialogSurface.transientGeneration = 1
    adapter.reconcile(
      snapshot(
        1,
        @[SnapshotOutput(output: 10, generation: 1, width: 1600, height: 1000)],
        @[parentSurface, dialogSurface],
      )
    )
    let dialog = adapter.logicalWindow(2, 1).get()
    let stored = adapter.model().windows[dialog].floatingGeometry
    check stored.width > 0

    var payload = parseJson(adapter.checkpointPayload().dumpCheckpointJson())
    payload["schema"] = %13
    for windowNode in payload["windows"]:
      windowNode.delete("floatingIntent")
    for entry in payload["scratchpadRestore"]:
      entry["restore"].delete("floatingIntent")
    let restored = restoreCheckpointPayload("HAGIA-POLICY-CHECKPOINT-13\n" & $payload)
    check restored.model().windows[dialog].floatingIntent == FloatingIntent.manual
    check restored.model().windows[dialog].floatingGeometry == stored
    check restored.checkpointPayload().startsWith("HAGIA-POLICY-CHECKPOINT-15\n")

  test "a parent that is wholly off the output takes its dialog with it":
    ## Partly visible is still visible -- the dialog is clamped and stays
    ## reachable. Entirely past the edge is not, and a dialog floating over an
    ## empty screen with nothing to belong to is worse than no dialog.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1280, height: 800))
    var windows: seq[WindowId]
    for _ in 0 .. 5:
      windows.add(model.addWindow(output, dialogCaps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
    let dialog = model.dialogOn(output, windows[5], 300, 200)

    # Focused on its own parent: both on screen.
    model.setFocus(output, windows[5])
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).isSome

    # Scrolled to the far end of the strip, the parent is gone and so is it.
    model.setFocus(output, windows[0])
    let scrolled = model.projectLayout([output], 8, 8)[0]
    let parentRect = scrolled.placementFor(windows[5]).get().geometry
    check parentRect.x >= 1280
    check scrolled.placementFor(dialog).isNone
    model.validate()

  test "a parent on another view takes its dialog with it":
    ## An inactive tab or workspace is the same question as a minimized parent:
    ## the window is not on screen, so neither is what belongs to it.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    model.ensureViewCount(output, 2)
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let dialog = model.dialogOn(output, parent, 300, 200)
    let elsewhere = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, elsewhere)
    check model.projectLayout([output], 8, 8)[0].placementFor(dialog).isSome

    model.placeWindowInViewSlot(parent, output, 2)
    let moved = model.projectLayout([output], 8, 8)[0]
    check moved.placementFor(parent).isNone
    check moved.placementFor(dialog).isNone
    model.validate()

  test "a parent that arrives late adopts the window that was already open":
    ## A child can be admitted before its owner is known. When the relation
    ## turns up, the window becomes a dialog and takes its place on the parent
    ## rather than staying where it was first put.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let orphan = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, orphan)
    check model.windows[orphan].parent == nullWindowId
    check not model.windows[orphan].floating

    model.setWindowRelation(orphan, WindowKind.dialog, parent)
    model.placeTransient(orphan, parent, 400, 300, Rect())
    check model.windows[orphan].floating
    check model.windows[orphan].floatingIntent == FloatingIntent.automatic

    let projection = model.projectLayout([output], 8, 8)[0]
    let parentRect = projection.placementFor(parent).get().geometry
    let child = projection.placementFor(orphan).get().geometry
    check child.x == parentRect.x + (parentRect.width - child.width) div 2
    check projection.stackIndex(orphan) > projection.stackIndex(parent)
    model.validate()

  test "a fullscreen parent under a panel carries its dialog to the whole screen":
    ## The work area stops below a reserved panel; fullscreen does not. The
    ## dialog has to centre on the rectangle its parent actually gets, which
    ## means fullscreen has to be settled inside the projection rather than
    ## corrected afterwards at the wire boundary.
    var adapter = initPolicyAdapter()
    var parentSurface = surface(1, 10)
    parentSurface.kind = 1
    parentSurface.currentStateBits = 1
    var dialogSurface = surface(2, 10)
    dialogSurface.kind = 2
    dialogSurface.transientIndex = 1
    dialogSurface.transientGeneration = 1
    let panelled = SnapshotOutput(
      output: 10,
      generation: 1,
      width: 1600,
      height: 1000,
      workY: 40,
      workWidth: 1600,
      workHeight: 960,
      focusIndex: 1,
      focusGeneration: 1,
    )
    let scene = snapshot(1, @[panelled], @[parentSurface, dialogSurface])
    adapter.reconcile(scene)
    let projected = adapter.projection(
      scene,
      ProjectionRequest(
        connectionEpoch: 1,
        requestId: 1,
        sceneGeneration: 1,
        policyGeneration: 1,
        affectedOutputs: @[10'u64],
      ),
    )

    var parentRect, childRect: Rect
    for placement in projected.outputs[0].placements:
      let rect = Rect(
        x: placement.x, y: placement.y, width: placement.width, height: placement.height
      )
      if placement.surfaceIndex == 1:
        parentRect = rect
      else:
        childRect = rect
    # The parent covers the panel; the work area would have started at y=40.
    check parentRect.y == 0
    check parentRect.height == 1000
    check childRect.y == parentRect.y + (parentRect.height - childRect.height) div 2
    check childRect.x == parentRect.x + (parentRect.width - childRect.width) div 2

  test "closing a dialog hands focus inside its own family":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let elsewhere = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, elsewhere)
    let sibling = model.dialogOn(output, parent, 300, 200)
    let closing = model.dialogOn(output, parent, 300, 200)
    model.setFocus(output, sibling)
    model.setFocus(output, closing)

    # The surviving dialog on the same parent, not the window the operator was
    # in before, and certainly not something in the background.
    model.removeWindow(closing)
    check model.outputs[output].focusedWindow == sibling

    # With the family emptied, focus falls back to the parent itself.
    model.removeWindow(sibling)
    check model.outputs[output].focusedWindow == parent
    model.validate()

  test "the intent survives a checkpoint and a scratchpad round trip":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let automatic = model.dialogOn(output, parent, 300, 200)
    let pinned = model.dialogOn(output, parent, 300, 200)
    model.setFloatingGeometry(
      output, pinned, Rect(x: 10, y: 20, width: 300, height: 200)
    )

    model.setFocus(output, pinned)
    model.moveFocusedToScratchpad(output)
    model.restoreScratchpad(pinned)
    check model.windows[pinned].floatingIntent == FloatingIntent.manual
    check model.windows[automatic].floatingIntent == FloatingIntent.automatic
    model.validate()

suite "dialog final geometry and visibility":
  test "floating elevated parents resolve before children regardless of admission order":
    for mode in [LayoutMode.scroller, LayoutMode.verticalScroller, LayoutMode.frameTree]:
      for fullscreen in [false, true]:
        var model = initPolicyModel()
        let work = Rect(x: 100, y: 60, width: 1600, height: 960)
        let physical = Rect(x: 100, y: 20, width: 1600, height: 1000)
        let output = model.addOutput(work)
        let child = model.addWindow(output, dialogCaps(), SizeConstraints())
        let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
        model.setFloatingGeometry(
          output, parent, Rect(x: 120, y: 100, width: 600, height: 400)
        )
        model.setWindowRelation(child, WindowKind.dialog, parent)
        model.placeTransient(child, parent, 200, 120)
        model.windows[parent].fullscreen = fullscreen
        model.windows[parent].maximized = not fullscreen
        model.setLayout(output, mode)
        let projection = model.projectLayout([output], 8, 8, 0, [(output, physical)])[0]
        let expected = if fullscreen: physical else: work
        check projection.placementFor(parent).get().geometry == expected
        let dialog = projection.placementFor(child).get().geometry
        check dialog.x == expected.x + (expected.width - dialog.width) div 2
        check dialog.y == expected.y + (expected.height - dialog.height) div 2
        check projection.stackIndex(child) > projection.stackIndex(parent)

  test "an offscreen parent becoming fullscreen brings its dialog back in the same cycle":
    var model = initPolicyModel()
    let bounds = Rect(width: 1600, height: 1000)
    let output = model.addOutput(bounds)
    var windows: seq[WindowId]
    for _ in 0 .. 7:
      windows.add(model.addWindow(output, dialogCaps(), SizeConstraints()))
      model.setFocus(output, windows[^1])
    let child = model.dialogOn(output, windows[0], 300, 200)
    model.setFocus(output, windows[^1])
    let before = model.projectLayout([output], 8, 8)[0]
    check before.placementFor(child).isNone
    model.windows[windows[0]].fullscreen = true
    let after = model.projectLayout([output], 8, 8)[0]
    check after.placementFor(windows[0]).get().geometry == bounds
    check after.placementFor(child).isSome

  test "an inactive parent tab suppresses the complete dialog chain":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    let other = model.addWindow(output, dialogCaps(), SizeConstraints())
    let child = model.dialogOn(output, parent, 400, 300)
    let nested = model.dialogOn(output, child, 200, 120)
    model.setFocus(output, other)
    model.setLayout(output, LayoutMode.frameTree)
    let hidden = model.projectLayout([output], 8, 8)[0]
    check hidden.placementFor(other).isSome
    check hidden.placementFor(parent).isNone
    check hidden.placementFor(child).isNone
    check hidden.placementFor(nested).isNone
    model.setFocus(output, parent)
    let visible = model.projectLayout([output], 8, 8)[0]
    check visible.placementFor(parent).isSome
    check visible.placementFor(child).isSome
    check visible.placementFor(nested).isSome

suite "edge presentation follows window families":
  ## Edge expansion is presentation for the focused family. Its retained
  ## preference survives navigation, while background panes return to the strip.

  proc order(model: PolicyModel, output: OutputId): seq[WindowId] =
    ## Bottom-to-top, which is the order the wire consumes.
    for placement in model.projectLayout([output], 8, 8)[0].placements:
      result.add(placement.window)

  proc stripOf(model: var PolicyModel, output: OutputId, count: int): seq[WindowId] =
    for _ in 0 ..< count:
      result.add(model.addWindow(output, dialogCaps(), SizeConstraints()))
      model.setFocus(output, result[^1])

  test "focus leaving an edge-maximized window restores its strip geometry":
    ## Whichever column was expanded -- first, middle, or last -- and back
    ## again, so expansion is not an artifact of strip position.
    for expanded in 0 .. 2:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      let windows = model.stripOf(output, 3)
      model.setFocus(output, windows[expanded])
      model.applyAction(output, PolicyAction.toggleMaximized)
      check model.windows[windows[expanded]].maximized

      var projection = model.projectLayout([output], 8, 8)[0]
      let expandedGeometry = projection.placementFor(windows[expanded]).get().geometry
      check projection.stackIndex(windows[expanded]) == projection.placements.high

      for other in 0 .. 2:
        if other == expanded:
          continue
        model.setFocus(output, windows[other])
        projection = model.projectLayout([output], 8, 8)[0]
        check not projection.placementFor(windows[expanded]).get().maximized
        check model.windows[windows[expanded]].maximized
        check projection.placementFor(windows[expanded]).get().geometry !=
          expandedGeometry

      # And through the key the operator actually presses. The neighbour is
      # named rather than read back, so a navigation action that moved nothing
      # fails here instead of being accepted as "focus did not change".
      model.setFocus(output, windows[expanded])
      let delta = if expanded == windows.high: -1 else: 1
      let neighbour = windows[expanded + delta]
      model.focusColumnRelative(output, delta)
      check model.outputs[output].focusedWindow == neighbour
      projection = model.projectLayout([output], 8, 8)[0]
      check not projection.placementFor(windows[expanded]).get().maximized
      let target = projection.placementFor(neighbour).get().geometry
      check target.x >= 0 and target.x + target.width <= 1600

      # Back again, and the expanded window leads once more.
      model.focusColumnRelative(output, -delta)
      check model.outputs[output].focusedWindow == windows[expanded]
      projection = model.projectLayout([output], 8, 8)[0]
      check projection.stackIndex(windows[expanded]) == projection.placements.high
      model.validate()

  test "a focused dialog leaves an unrelated maximized window in the strip":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let expanded = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, expanded)
    model.applyAction(output, PolicyAction.toggleMaximized)
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    let dialog = model.dialogOn(output, parent, 300, 200)
    model.setFocus(output, dialog)

    let projection = model.projectLayout([output], 8, 8)[0]
    check projection.stackIndex(parent) > projection.stackIndex(expanded)
    check projection.stackIndex(dialog) > projection.stackIndex(parent)
    check model.windows[expanded].maximized
    check not projection.placementFor(expanded).get().maximized
    check projection.placementFor(expanded).get().geometry.width < 1600
    model.validate()

  test "a focused dialog of a maximized parent leads another maximized window":
    ## Run with the dialog's owner created first and created last. Created
    ## last it would lead on strip order alone, which would let the old
    ## ordering pass without ever raising the family.
    for ownerFirst in [true, false]:
      var model = initPolicyModel()
      let output = model.addOutput(Rect(width: 1600, height: 1000))
      var owner, background: WindowId
      for index in 0 .. 1:
        let window = model.addWindow(output, dialogCaps(), SizeConstraints())
        model.setFocus(output, window)
        model.applyAction(output, PolicyAction.toggleMaximized)
        if (index == 0) == ownerFirst:
          owner = window
        else:
          background = window
      let dialog = model.dialogOn(output, owner, 300, 200)
      model.setFocus(output, dialog)

      let projection = model.projectLayout([output], 8, 8)[0]
      check projection.stackIndex(owner) > projection.stackIndex(background)
      check projection.stackIndex(dialog) > projection.stackIndex(owner)
      check model.windows[background].maximized
      check model.windows[owner].maximized
      check projection.placementFor(owner).get().maximized
      check projection.placementFor(owner).get().geometry ==
        Rect(width: 1600, height: 1000)
      check not projection.placementFor(background).get().maximized
      check projection.placementFor(background).get().geometry.width < 1600
      model.validate()

  test "an independent focused floating window remains above retained edge presentation":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let parent = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFocus(output, parent)
    model.applyAction(output, PolicyAction.toggleMaximized)
    let overlay = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFloatingGeometry(
      output, overlay, Rect(x: 40, y: 40, width: 300, height: 200)
    )
    model.setFocus(output, overlay)
    let projection = model.projectLayout([output], 8, 8)[0]
    check projection.placementFor(parent).get().maximized
    check projection.placementFor(parent).get().geometry ==
      Rect(width: 1600, height: 1000)
    check projection.stackIndex(overlay) > projection.stackIndex(parent)
    model.validate()

  test "a fullscreen window keeps the screen whatever else holds focus":
    ## Fullscreen is an explicit claim on the display, not a focus-following
    ## elevation, and it stays above a focused ordinary window.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let windows = model.stripOf(output, 3)
    model.setFocus(output, windows[0])
    model.applyAction(output, PolicyAction.toggleFullscreen)
    model.setFocus(output, windows[1])
    model.applyAction(output, PolicyAction.toggleMaximized)
    let dialog = model.dialogOn(output, windows[0], 300, 200)
    check model.windows[windows[0]].fullscreen
    check model.windows[windows[1]].maximized

    # An ordinary window takes focus. It rises past the maximized one and
    # stays under the fullscreen claim and the dialog that belongs to it.
    model.setFocus(output, windows[2])
    let projection = model.projectLayout([output], 8, 8)[0]
    check projection.stackIndex(windows[2]) > projection.stackIndex(windows[1])
    check projection.stackIndex(windows[0]) > projection.stackIndex(windows[2])
    check projection.stackIndex(dialog) > projection.stackIndex(windows[0])
    model.validate()

  test "unmaximizing restores the ordinary tile order":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let windows = model.stripOf(output, 3)
    model.setFocus(output, windows[0])
    let before = model.order(output)

    model.applyAction(output, PolicyAction.toggleMaximized)
    model.setFocus(output, windows[2])
    model.setFocus(output, windows[0])
    model.applyAction(output, PolicyAction.toggleMaximized)
    check not model.windows[windows[0]].maximized

    check model.order(output) == before
    model.validate()

  test "without a maximized window the order is the one the layout made":
    ## With nothing expanded, focus must not reshuffle
    ## the strip -- including floating windows, which all share one layer.
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let windows = model.stripOf(output, 3)
    let floating = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFloatingGeometry(
      output, floating, Rect(x: 40, y: 40, width: 300, height: 200)
    )
    model.setFocus(output, windows[0])
    let settled = model.order(output)
    for window in windows:
      model.setFocus(output, window)
      check model.order(output) == settled
    model.validate()

  test "full-width column elevation follows dialogs and independent floating focus":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1600, height: 1000))
    let windows = model.stripOf(output, 3)
    let owner = windows[0]
    model.setFocus(output, owner)
    model.applyAction(output, PolicyAction.maximizeColumn)
    let dialog = model.dialogOn(output, owner, 300, 200)
    model.setFocus(output, dialog)
    let projected = model.projectLayout([output], 8, 8)[0]
    check not projected.placementFor(owner).get().maximized
    check projected.stackIndex(owner) > projected.stackIndex(windows[2])
    check projected.stackIndex(dialog) > projected.stackIndex(owner)
    let overlay = model.addWindow(output, dialogCaps(), SizeConstraints())
    model.setFloatingGeometry(
      output, overlay, Rect(x: 40, y: 40, width: 300, height: 200)
    )
    model.setFocus(output, overlay)
    let floating = model.projectLayout([output], 8, 8)[0]
    check floating.stackIndex(owner) > floating.stackIndex(windows[2])
    check floating.stackIndex(overlay) > floating.stackIndex(dialog)
    model.setFocus(output, windows[1])
    let navigated = model.projectLayout([output], 8, 8)[0]
    check navigated.stackIndex(owner) < navigated.stackIndex(windows[1])
    model.validate()
