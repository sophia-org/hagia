# Included by policy_adapter after presentation.nim: it shares the identity maps
# and `finishPublication`.

proc addScopeKeys(
    bindings: var seq[(uint32, uint32, PolicyAction)], modifiers: uint32
) =
  ## niri's scope keys while the switcher is open: a, w, o and s.
  bindings.add((30'u32, modifiers, PolicyAction.recentWindowScopeAll))
  bindings.add((17'u32, modifiers, PolicyAction.recentWindowScopeWorkspace))
  bindings.add((24'u32, modifiers, PolicyAction.recentWindowScopeOutput))
  bindings.add((31'u32, modifiers, PolicyAction.recentWindowScopeCycle))

const recentWindowModalBindings = block:
  # Used only when Sophia cannot report the chord ending: the switcher is then
  # a modal one, drawn once the modifier is up, and confirmed explicitly.
  # Modal capture matches modifiers exactly and swallows every unbound key,
  # and the policy does not learn which chord opened the switcher. So each key
  # is bound under all sixteen masks (Shift, Ctrl, Alt, Super): a chord on Tab
  # steps with any modifiers held, and Shift+Tab steps back. A trigger on
  # another key opens the switcher but does not step it until the lifecycle.
  var bindings: seq[(uint32, uint32, PolicyAction)]
  for modifiers in 0'u32 .. 15'u32:
    let tab =
      if (modifiers and 1) != 0:
        PolicyAction.recentWindowPrevious
      else:
        PolicyAction.recentWindowNext
    bindings.add((15'u32, modifiers, tab))
    bindings.add((106'u32, modifiers, PolicyAction.recentWindowNext))
    bindings.add((105'u32, modifiers, PolicyAction.recentWindowPrevious))
    bindings.add((28'u32, modifiers, PolicyAction.recentWindowConfirm))
    bindings.add((96'u32, modifiers, PolicyAction.recentWindowConfirm))
    bindings.add((1'u32, modifiers, PolicyAction.recentWindowCancel))
    bindings.addScopeKeys(modifiers)
  bindings

const recentWindowHeldBindings = block:
  # With the held capture, a chord-owned switcher answers niri's keys while
  # the chord is held. Sophia passes every modifier through and keeps the
  # chord's own further presses, so Tab needs no binding here; each key is
  # bound under all sixteen masks because the policy does not learn which
  # modifiers hold the chord.
  var bindings: seq[(uint32, uint32, PolicyAction)]
  for modifiers in 0'u32 .. 15'u32:
    bindings.add((1'u32, modifiers, PolicyAction.recentWindowCancel))
    bindings.add((28'u32, modifiers, PolicyAction.recentWindowConfirm))
    bindings.add((96'u32, modifiers, PolicyAction.recentWindowConfirm))
    bindings.add((57'u32, modifiers, PolicyAction.recentWindowConfirm))
    bindings.add((105'u32, modifiers, PolicyAction.recentWindowPrevious))
    bindings.add((106'u32, modifiers, PolicyAction.recentWindowNext))
    bindings.add((102'u32, modifiers, PolicyAction.recentWindowFirst))
    bindings.add((107'u32, modifiers, PolicyAction.recentWindowLast))
    bindings.addScopeKeys(modifiers)
  bindings

proc reaches(rect, bounds: Rect): bool =
  ## Whether any of a scrolled preview is on the output at all.
  int64(rect.x) < int64(bounds.x) + bounds.width and
    int64(bounds.x) < int64(rect.x) + rect.width and
    int64(rect.y) < int64(bounds.y) + bounds.height and
    int64(bounds.y) < int64(rect.y) + rect.height

proc recentWindowsPresentation(
    adapter: var PolicyAdapter,
    snapshot: PolicySnapshot,
    physicalBounds: openArray[(OutputId, Rect)],
): Option[WmPresentation] =
  ## A switcher owned by a chord is an Overlay, so the held modifier and the
  ## chord's further presses keep reaching Sophia's shortcut authority. With
  ## the held capture it also takes niri's keys while the chord is held. One
  ## opened by a plain invocation is modal.
  let strip = adapter.model.recentWindowStrip(physicalBounds)
  if strip.isNone:
    adapter.clearPresentation()
    return none(WmPresentation)
  let modal = adapter.model.recentWindows.owners.len == 0
  let logical = strip.get().output
  let handle = adapter.logicalToOutput[logical]
  var generation = 0'u64
  var coverage = Rect()
  for output in snapshot.outputs:
    if output.output == handle.output:
      generation = output.generation
      coverage =
        Rect(x: output.x, y: output.y, width: output.width, height: output.height)
  if generation == 0:
    adapter.model.clearRecentWindows()
    adapter.clearPresentation()
    return none(WmPresentation)
  let previous = adapter.presentation.get(WmPresentation())
  var publication = WmPresentation(generation: previous.generation)
  var nextKeys = initTable[string, uint64]()
  var targets = initTable[uint64, OverviewSelection]()
  publication.outputs.add(
    PresentationOutput(
      output: handle.output,
      generation: generation,
      coverage: coverage,
      mode:
        if modal: PresentationMode.replaceApplications else: PresentationMode.overlay,
    )
  )
  publication.regions.add(
    PresentationRegion(
      id: adapter.presentationTarget(
        OverviewSelection(output: logical).presentationKey("recent-backdrop"), nextKeys
      ),
      output: handle.output,
      geometry: coverage,
      clip: coverage,
      role: PresentationRegionRole.backdrop,
    )
  )
  var zIndex = 1'u16
  for preview in strip.get().previews:
    if preview.window notin adapter.surfaceFacts or
        not preview.geometry.reaches(coverage):
      continue
    let selection = OverviewSelection(output: logical, window: preview.window)
    let id = adapter.presentationTarget(selection.presentationKey("recent"), nextKeys)
    targets[id] = selection
    let source = adapter.surfaceFacts[preview.window]
    publication.instances.add(
      SurfaceInstance(
        id: id,
        output: handle.output,
        sourceIndex: source.surfaceIndex,
        sourceGeneration: source.surfaceGeneration,
        destination: preview.geometry,
        clip: coverage,
        opacityMillis: 1000,
        zIndex: zIndex,
        action: PolicyAction.recentWindowConfirm.raw(),
      )
    )
    inc zIndex
  let highlight = strip.get().highlight
  # An empty switcher draws its backdrop and no highlight.
  if highlight.width > 0 and highlight.height > 0 and
      adapter.model.recentWindows.candidates.len > 0:
    let selected =
      adapter.model.recentWindows.candidates[adapter.model.recentWindows.selected]
    let selection = OverviewSelection(output: logical, window: selected)
    let id =
      adapter.presentationTarget(selection.presentationKey("recent-emphasis"), nextKeys)
    targets[id] = selection
    publication.regions.add(
      PresentationRegion(
        id: id,
        output: handle.output,
        geometry: highlight,
        clip: coverage,
        zIndex: zIndex,
        role: PresentationRegionRole.emphasis,
        action: PolicyAction.recentWindowConfirm.raw(),
      )
    )
  if modal or adapter.heldCapture:
    publication.keyboardOutput = handle.output
    let bindings = if modal: recentWindowModalBindings else: recentWindowHeldBindings
    for (keycode, modifiers, action) in bindings:
      publication.bindings.add(
        PresentationBinding(
          action: action.raw(), keycode: keycode, modifiers: modifiers
        )
      )
  adapter.finishPublication(publication, previous, nextKeys, targets)
