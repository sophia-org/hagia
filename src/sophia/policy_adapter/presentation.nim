# Included by policy_adapter: identity maps share its speculative commit owner.

proc clearPresentation*(adapter: var PolicyAdapter) =
  adapter.model.clearOverview()
  adapter.presentation = none(WmPresentation)
  adapter.presentationKeys.clear()
  adapter.presentationTargets.clear()

proc synchronizePresentationEpoch*(adapter: var PolicyAdapter, epoch: uint64) =
  if epoch == 0:
    fail("presentation connection epoch is invalid")
  if adapter.presentationEpoch != epoch:
    adapter.clearPresentation()
    adapter.presentationEpoch = epoch
    adapter.publicationCounter = 0
    adapter.targetCounter = 0

proc nextIdentity(counter: var uint64): uint64 =
  if counter == high(uint64):
    fail("presentation identity space is exhausted")
  inc counter
  counter

proc presentationKey(selection: OverviewSelection, role: string): string =
  role & ":" & $uint32(selection.output) & ":" & $uint32(selection.view) & ":" &
    $uint32(selection.window)

proc presentationTarget(
    adapter: var PolicyAdapter, key: string, nextKeys: var Table[string, uint64]
): uint64 =
  result = adapter.presentationKeys.getOrDefault(key)
  if result == 0:
    result = adapter.targetCounter.nextIdentity()
  nextKeys[key] = result

proc overviewPresentation(
    adapter: var PolicyAdapter,
    snapshot: PolicySnapshot,
    physicalBounds: openArray[(OutputId, Rect)],
): Option[WmPresentation] =
  if not adapter.model.overview.active:
    adapter.clearPresentation()
    return none(WmPresentation)
  let previous = adapter.presentation.get(WmPresentation())
  var publication = WmPresentation(generation: previous.generation)
  var nextKeys = initTable[string, uint64]()
  var targets = initTable[uint64, OverviewSelection]()
  var zOrders = initTable[uint64, uint16]()
  var oldInstances = initTable[uint64, SurfaceInstance]()
  var oldRegions = initTable[uint64, PresentationRegion]()
  for item in previous.instances:
    oldInstances[item.id] = item
  for item in previous.regions:
    oldRegions[item.id] = item

  for output in snapshot.outputs:
    let logical = adapter.outputToLogical[output.output]
    let bounds =
      Rect(x: output.x, y: output.y, width: output.width, height: output.height)
    publication.outputs.add(
      PresentationOutput(
        output: output.output,
        generation: output.generation,
        coverage: bounds,
        mode: PresentationMode.replaceApplications,
      )
    )
    let id = adapter.presentationTarget(
      OverviewSelection(output: logical).presentationKey("backdrop"), nextKeys
    )
    publication.regions.add(
      PresentationRegion(
        id: id,
        output: output.output,
        geometry: bounds,
        clip: bounds,
        role: PresentationRegionRole.backdrop,
      )
    )
    zOrders[output.output] = 1
  publication.keyboardOutput =
    adapter.logicalToOutput[adapter.model.overview.selection.output].output

  for preview in adapter.model.overviewPreviews(physicalBounds):
    let logical = preview.workspace.output
    let output = adapter.logicalToOutput[logical].output
    let workspace = OverviewSelection(output: logical, view: preview.workspace.view)
    let frameId =
      adapter.presentationTarget(workspace.presentationKey("frame"), nextKeys)
    targets[frameId] = workspace
    publication.regions.add(
      PresentationRegion(
        id: frameId,
        output: output,
        geometry: preview.geometry,
        clip: preview.clip,
        zIndex: zOrders[output],
        role: PresentationRegionRole.frame,
        action: PolicyAction.confirmOverview.raw(),
      )
    )
    inc zOrders[output]
    for placement in preview.placements:
      let selection = OverviewSelection(
        output: logical, view: workspace.view, window: placement.window
      )
      let id =
        adapter.presentationTarget(selection.presentationKey("instance"), nextKeys)
      let source = adapter.surfaceFacts[placement.window]
      let selectable =
        adapter.model.window(placement.window).get().capabilities.focusable
      if selectable:
        targets[id] = selection
      publication.instances.add(
        SurfaceInstance(
          id: id,
          output: output,
          sourceIndex: source.surfaceIndex,
          sourceGeneration: source.surfaceGeneration,
          destination: placement.geometry,
          clip: preview.clip,
          opacityMillis: 1000,
          zIndex: zOrders[output],
          action: (if selectable: PolicyAction.confirmOverview.raw() else: 0),
        )
      )
      inc zOrders[output]
    if adapter.model.overview.selection.output == logical and
        adapter.model.overview.selection.view == workspace.view:
      var geometry = preview.geometry
      let selection = adapter.model.overview.selection
      for placement in preview.placements:
        if placement.window == selection.window:
          geometry = placement.geometry
          break
      let id =
        adapter.presentationTarget(selection.presentationKey("emphasis"), nextKeys)
      targets[id] = selection
      publication.regions.add(
        PresentationRegion(
          id: id,
          output: output,
          geometry: geometry,
          clip: preview.clip,
          zIndex: zOrders[output],
          role: PresentationRegionRole.emphasis,
          action: PolicyAction.confirmOverview.raw(),
        )
      )
      inc zOrders[output]

  for (key, action) in [
    (105'u32, PolicyAction.overviewLeft),
    (106'u32, PolicyAction.overviewRight),
    (103'u32, PolicyAction.overviewUp),
    (108'u32, PolicyAction.overviewDown),
    (35'u32, PolicyAction.overviewLeft),
    (36'u32, PolicyAction.overviewDown),
    (37'u32, PolicyAction.overviewUp),
    (38'u32, PolicyAction.overviewRight),
    (28'u32, PolicyAction.confirmOverview),
    (96'u32, PolicyAction.confirmOverview),
    (1'u32, PolicyAction.closeOverview),
    (104'u32, PolicyAction.overviewPreviousWorkspace),
    (109'u32, PolicyAction.overviewNextWorkspace),
  ]:
    publication.bindings.add(PresentationBinding(action: action.raw(), keycode: key))
  publication.bindings.add(
    PresentationBinding(
      action: PolicyAction.toggleOverview.raw(), keycode: 24, modifiers: 8
    )
  )

  # A source content commit is not a new target identity. Only these passive
  # spatial/action records change target and publication generations.
  for item in publication.instances.mitems:
    let old = oldInstances.getOrDefault(item.id)
    item.generation = old.generation
    if item != old:
      discard item.generation.nextIdentity()
  for item in publication.regions.mitems:
    let old = oldRegions.getOrDefault(item.id)
    item.generation = old.generation
    if item != old:
      discard item.generation.nextIdentity()
  if publication != previous:
    publication.generation = adapter.publicationCounter.nextIdentity()
  publication.validatePresentation()
  adapter.presentation = some(publication)
  adapter.presentationKeys = nextKeys
  adapter.presentationTargets = targets
  adapter.presentation

proc revokeChangedPresentation(adapter: var PolicyAdapter, snapshot: PolicySnapshot) =
  if adapter.presentation.isNone:
    return
  let publication = adapter.presentation.get()
  if publication.outputs.len != snapshot.outputs.len:
    adapter.clearPresentation()
    return
  for old in publication.outputs:
    var found = false
    for output in snapshot.outputs:
      if old.output == output.output and old.generation == output.generation:
        let bounds =
          Rect(x: output.x, y: output.y, width: output.width, height: output.height)
        let logical = adapter.outputToLogical.getOrDefault(output.output)
        let prior = adapter.model.output(logical)
        found =
          old.coverage == bounds and prior.isSome and
          prior.get().bounds == output.bounds()
        break
    if not found:
      adapter.clearPresentation()
      return
  var sources = initHashSet[(uint32, uint32)]()
  for source in snapshot.surfaces:
    sources.incl((source.surfaceIndex, source.surfaceGeneration))
  for item in publication.instances:
    if (item.sourceIndex, item.sourceGeneration) notin sources:
      adapter.clearPresentation()
      return

proc applyPresentationAction(adapter: var PolicyAdapter, request: ProjectionRequest) =
  let cause = request.cause
  let identity = cause.presentation
  if adapter.presentation.isNone or not adapter.model.overview.active or
      request.connectionEpoch != adapter.presentationEpoch or cause.activationSerial == 0 or
      identity.presentationEpoch == 0 or not cause.action.isPolicyAction():
    fail("presentation action has no active policy publication")
  let publication = adapter.presentation.get()
  if identity.publicationGeneration != publication.generation:
    fail("presentation action names a stale publication")
  var foundOutput = false
  for output in publication.outputs:
    if output.output == identity.output and
        output.generation == identity.outputGeneration:
      foundOutput = true
  if not foundOutput:
    fail("presentation action names a stale output")
  if identity.targetId == 0:
    if identity.targetGeneration != 0 or publication.keyboardOutput != identity.output:
      fail("presentation keyboard scope is invalid")
    var bound = false
    for binding in publication.bindings:
      if binding.action == cause.action:
        bound = true
    if not bound:
      fail("presentation action is not bound")
    adapter.model.applyAction(
      adapter.model.overview.selection.output, cause.action.policyAction()
    )
  else:
    var found = false
    for item in publication.instances:
      if item.id == identity.targetId and item.generation == identity.targetGeneration and
          item.output == identity.output and item.action == cause.action:
        found = true
    for item in publication.regions:
      if item.id == identity.targetId and item.generation == identity.targetGeneration and
          item.output == identity.output and item.action == cause.action:
        found = true
    let selection = adapter.presentationTargets.getOrDefault(identity.targetId)
    if not found or cause.action != PolicyAction.confirmOverview.raw() or
        selection.output == nullOutputId:
      fail("presentation target is stale or unbound")
    adapter.model.setOverviewSelection(selection)
    adapter.model.confirmOverview()

proc receivePresentationReceipt*(
    adapter: var PolicyAdapter, receipt: PresentationReceipt
) =
  if receipt.connectionEpoch != adapter.presentationEpoch or adapter.presentation.isNone:
    return
  let publication = adapter.presentation.get()
  if receipt.publicationGeneration != publication.generation:
    return
  for output in publication.outputs:
    if output.output == receipt.output and output.generation == receipt.outputGeneration:
      if receipt.outcome != PresentationOutcomeKind.presented:
        adapter.clearPresentation()
      return
