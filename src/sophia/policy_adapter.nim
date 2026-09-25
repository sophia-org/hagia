import std/[algorithm, json, jsonutils, options, sets, strutils, tables]

import ../types/actions
import ../types/config_values
import ../config/policy_candidate
import ../types/observability
import ../observability
import ../types/[core, model, policy_messages, projection]
import ../policy/[actions, entity_store, projection, reducer, state]
import ../types/wm_v1
import ../types/session
import ./policy_codec
import ./snapshot_convert
import ../types/tab_tree
import ../entities/[tab_tree_ops, workspace_assignment]

export PolicyAdapterError

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyAdapterError, message)

type
  PolicyAdapter* = object
    model: PolicyModel
    surfaceToWindow: Table[uint64, WindowId]
    windowToSurface: Table[WindowId, uint64]
    outputToLogical: Table[uint64, OutputId]
    activeOutputToLogical: Table[OutputHandle, OutputId]
    # Launch contexts. Session-local and deliberately absent from the
    # checkpoint: a token means nothing to a later connection, and reviving one
    # would point a launch at a place the operator has since rearranged.
    launchTokens: Table[uint64, LaunchDestination]
    launchDestinationTokens: Table[string, uint64]
    launchTokenOrder: seq[uint64]
    launchTokenCounter: uint64
    launchEpoch: uint64
    outputLaunchTokens: HashSet[uint64]
    dormantOutputToLogical: Table[OutputHandle, OutputId]
    logicalToOutput: Table[OutputId, OutputHandle]
    surfaceFacts: Table[WindowId, SnapshotSurface]
    # Last emitted maximize bit, promoted with the candidate on commit. An
    # echo of suspended presentation must not clear private maximize intent.
    presentedMaximized: Table[WindowId, bool]

  TagRelationDto = object
    owner: uint32
    tags: seq[uint32]

  SurfaceDto = object
    key: uint64
    window: uint32
    facts: SnapshotSurface
    presentedMaximized: bool

  OutputDto = object
    output: uint64
    generation: uint64
    logical: uint32

  ScratchpadRestoreDto = object
    window: uint32
    restore: ScratchpadRestoreData

  NamedScratchpadDto = object
    slot: uint32
    window: uint32

  GroupRelationDto = object
    window: uint32
    group: uint32

  CheckpointV4Dto = object
    tabTrees: seq[TabTreeDto]
    schema: uint32
    counters: IdCounters
    settings: PolicySettings
    activeOutput: uint32
    windows: seq[WindowData]
    windowOrder: seq[uint32]
    columns: seq[ColumnData]
    columnOrder: seq[uint32]
    views: seq[ViewData]
    tags: seq[TagData]
    outputs: seq[OutputData]
    outputOrder: seq[uint32]
    windowTags: seq[TagRelationDto]
    viewTags: seq[TagRelationDto]
    minimizedOrder: seq[uint32]
    affinities: seq[OutputAffinity]
    affinityOrder: seq[uint32]
    scratchpadOrder: seq[uint32]
    scratchpadRestore: seq[ScratchpadRestoreDto]
    namedScratchpads: seq[NamedScratchpadDto]
    groups: seq[GroupData]
    groupOfWindow: seq[GroupRelationDto]
    visibleScratchpad: uint32
    scratchpadTag: uint32
    surfaces: seq[SurfaceDto]
    activeOutputs: seq[OutputDto]
    dormantOutputs: seq[OutputDto]

proc applyPolicyCandidate*(adapter: var PolicyAdapter, candidate: AuthorityCandidate)

proc initPolicyAdapter*(): PolicyAdapter =
  PolicyAdapter(model: initPolicyModel())

proc initPolicyAdapter*(candidate: AuthorityCandidate): PolicyAdapter =
  result = initPolicyAdapter()
  result.applyPolicyCandidate(candidate)

proc applyPolicyCandidate*(adapter: var PolicyAdapter, candidate: AuthorityCandidate) =
  var prepared = adapter.model.clone()
  prepared.applyPolicyCandidate(candidate)
  if adapter.model.settings.workspaceAssignments.len > 0 and
      adapter.model.settings.workspaceAssignments !=
      prepared.settings.workspaceAssignments and
      (adapter.model.outputOrder.len > 0 or adapter.model.affinityOrder.len > 0):
    fail("changing established workspace assignments requires an explicit migration")
  prepared.reconcilePolicySettings()
  prepared.validate()
  adapter.model = prepared

proc clone*(adapter: PolicyAdapter): PolicyAdapter =
  result.model = adapter.model.clone()
  for key, value in adapter.surfaceToWindow.pairs:
    result.surfaceToWindow[key] = value
  for key, value in adapter.windowToSurface.pairs:
    result.windowToSurface[key] = value
  for key, value in adapter.outputToLogical.pairs:
    result.outputToLogical[key] = value
  for key, value in adapter.activeOutputToLogical.pairs:
    result.activeOutputToLogical[key] = value
  for key, value in adapter.dormantOutputToLogical.pairs:
    result.dormantOutputToLogical[key] = value
  for key, value in adapter.logicalToOutput.pairs:
    result.logicalToOutput[key] = value
  for key, value in adapter.surfaceFacts.pairs:
    result.surfaceFacts[key] = value
  for key, value in adapter.presentedMaximized.pairs:
    result.presentedMaximized[key] = value
  # Carried so a token keeps meaning the same place across cycles. A candidate
  # that is never committed is dropped whole, and the tokens it minted go with
  # it rather than leaking into the next attempt.
  for key, value in adapter.launchTokens.pairs:
    result.launchTokens[key] = value
  for key, value in adapter.launchDestinationTokens.pairs:
    result.launchDestinationTokens[key] = value
  result.launchTokenOrder = adapter.launchTokenOrder
  result.launchTokenCounter = adapter.launchTokenCounter
  result.launchEpoch = adapter.launchEpoch
  for token in adapter.outputLaunchTokens:
    result.outputLaunchTokens.incl(token)

proc destinationKey(destination: LaunchDestination): string =
  result = $int(destination.output)
  for tag in destination.tags:
    result.add('.')
    result.add($int(tag))

proc liveLogicalOutputs(adapter: PolicyAdapter): HashSet[OutputId] =
  ## Only outputs a live handle currently maps to. A dormant output stays in
  ## the model so its windows can return to it, but a launch must not be placed
  ## somewhere the operator cannot see.
  for logical in adapter.activeOutputToLogical.values:
    result.incl(logical)

proc launchToken(
    adapter: var PolicyAdapter,
    destination: LaunchDestination,
    protected: HashSet[string],
): uint64 =
  ## One token per destination, not per window: several windows sharing a place
  ## share its context, which is what keeps the cache bounded by places rather
  ## than by how many windows are open.
  let key = destination.destinationKey()
  if key in adapter.launchDestinationTokens:
    return adapter.launchDestinationTokens[key]
  # Reserve capacity before minting. Output bookmarks are stable for the epoch;
  # never let publishing ordinary window contexts evict an accepted destination.
  if adapter.launchTokens.len >= maxLaunchOriginRecords:
    var removable = 0'u64
    for candidate in adapter.launchTokenOrder:
      if candidate notin adapter.outputLaunchTokens and
          adapter.launchTokens[candidate].destinationKey() notin protected:
        removable = candidate
        break
    if removable == 0:
      return 0
    adapter.launchDestinationTokens.del(
      adapter.launchTokens[removable].destinationKey()
    )
    adapter.launchTokens.del(removable)
    adapter.launchTokenOrder.delete(adapter.launchTokenOrder.find(removable))
  adapter.launchTokenCounter += 1
  result = adapter.launchTokenCounter
  adapter.launchTokens[result] = destination
  adapter.launchDestinationTokens[key] = result
  adapter.launchTokenOrder.add(result)
  # Evict the oldest token no place currently in use needs. Evicting a live one
  # would hand Sophia a context that resolves to nothing on the very pass that
  # published it, and then mint the same destination again next cycle.
  var index = 0
  while adapter.launchTokenOrder.len > maxLaunchOriginRecords and
      index < adapter.launchTokenOrder.len:
    let candidate = adapter.launchTokenOrder[index]
    let key =
      if candidate in adapter.launchTokens:
        adapter.launchTokens[candidate].destinationKey()
      else:
        ""
    if candidate notin adapter.outputLaunchTokens and
        (key.len == 0 or key notin protected):
      adapter.launchTokenOrder.delete(index)
      if candidate in adapter.launchTokens:
        adapter.launchDestinationTokens.del(key)
        adapter.launchTokens.del(candidate)
    else:
      inc index

proc launchContexts(
    adapter: var PolicyAdapter, epoch: uint64
): seq[LaunchOriginRecord] =
  ## A context for every live managed top-level, hidden ones included. A window
  ## on a view the operator has since left is exactly the case this exists for:
  ## the child still belongs where its launcher lives.
  let live = adapter.liveLogicalOutputs()
  var sources: seq[(uint64, LaunchDestination)]
  var protected = initHashSet[string]()
  for window in adapter.model.windowOrder:
    if sources.len >= maxLaunchOriginRecords:
      break
    let data = adapter.model.windows[window]
    if data.kind != WindowKind.toplevel or data.parent != nullWindowId or
        window notin adapter.windowToSurface or data.homeOutput notin live:
      continue
    let tags = adapter.model.windowTagIds(window)
    if tags.len == 0:
      continue
    let destination = LaunchDestination(output: data.homeOutput, tags: tags)
    protected.incl(destination.destinationKey())
    sources.add((adapter.windowToSurface[window], destination))
  # Every destination this pass publishes is known before any is minted, so
  # eviction cannot take one the same pass is about to hand out.
  for (key, destination) in sources:
    let token = adapter.launchToken(destination, protected)
    if token == 0:
      continue
    result.add(
      LaunchOriginRecord(
        surfaceIndex: uint32(key and 0xffffffff'u64),
        surfaceGeneration: uint32(key shr 32),
        epoch: epoch,
        token: token,
      )
    )

proc outputLaunchContexts(
    adapter: var PolicyAdapter, epoch: uint64
): seq[OutputLaunchContext] =
  # Empty workspaces have no window context to borrow. Publish their destination
  # directly, and never recycle an output token during this WM connection.
  for handle, logical in adapter.activeOutputToLogical.pairs:
    let output = adapter.model.output(logical)
    if output.isNone:
      continue
    let destination = LaunchDestination(
      output: logical, tags: adapter.model.viewTagIds(output.get().activeView)
    )
    let key = destination.destinationKey()
    var token: uint64
    if key in adapter.launchDestinationTokens:
      token = adapter.launchDestinationTokens[key]
    elif adapter.launchTokens.len < maxLaunchOriginRecords:
      token = adapter.launchToken(destination, initHashSet[string]())
    else:
      continue # Bounded exhaustion makes new launches unavailable, not misdirected.
    adapter.outputLaunchTokens.incl(token)
    result.add(
      OutputLaunchContext(
        output: handle.output, generation: handle.generation, epoch: epoch, token: token
      )
    )

proc synchronizeLaunchEpoch*(adapter: var PolicyAdapter, epoch: uint64) =
  ## A new connection is a new token space. Anything minted under the old one
  ## is cleared rather than reused, so a stale echo resolves to nothing and the
  ## window it names is placed ordinarily.
  if adapter.launchEpoch == epoch:
    return
  adapter.launchEpoch = epoch
  adapter.launchTokens.clear()
  adapter.launchDestinationTokens.clear()
  adapter.launchTokenOrder.setLen(0)
  adapter.launchTokenCounter = 0
  adapter.outputLaunchTokens.clear()

proc logicalWindow*(
    adapter: PolicyAdapter, surfaceIndex, surfaceGeneration: uint32
): Option[WindowId] =
  let key = surfaceKey(surfaceIndex, surfaceGeneration)
  if key in adapter.surfaceToWindow:
    some(adapter.surfaceToWindow[key])
  else:
    none(WindowId)

proc logicalOutput*(adapter: PolicyAdapter, output: uint64): Option[OutputId] =
  if output in adapter.outputToLogical:
    some(adapter.outputToLogical[output])
  else:
    none(OutputId)

proc model*(adapter: PolicyAdapter): PolicyModel =
  adapter.model

proc hasWindows*(adapter: PolicyAdapter): bool =
  adapter.model.windowOrder.len > 0

proc checkpointDto(adapter: PolicyAdapter): CheckpointV4Dto =
  result.schema = 19
  for view, tree in adapter.model.tabTrees:
    result.tabTrees.add(TabTreeDto(view: uint32(view), tree: tree))
  result.tabTrees.sort(
    proc(a, b: TabTreeDto): int =
      cmp(a.view, b.view)
  )
  result.counters = adapter.model.counters
  result.settings = adapter.model.settings
  result.activeOutput = uint32(adapter.model.activeOutput)
  for _, window in adapter.model.windows.pairs:
    result.windows.add(window)
  result.windows.sort(idOrder[WindowData])
  for id in adapter.model.windowOrder:
    result.windowOrder.add(uint32(id))
  for _, column in adapter.model.columns.pairs:
    result.columns.add(column)
  result.columns.sort(idOrder[ColumnData])
  for id in adapter.model.columnOrder:
    result.columnOrder.add(uint32(id))
  for _, view in adapter.model.views.pairs:
    result.views.add(view)
  result.views.sort(idOrder[ViewData])
  for _, tag in adapter.model.tags.pairs:
    result.tags.add(tag)
  result.tags.sort(idOrder[TagData])
  for _, output in adapter.model.outputs.pairs:
    result.outputs.add(output)
  result.outputs.sort(idOrder[OutputData])
  for id in adapter.model.outputOrder:
    result.outputOrder.add(uint32(id))
  for id in adapter.model.windowOrder:
    var relation = TagRelationDto(owner: uint32(id))
    for tag in adapter.model.windowTagIds(id):
      relation.tags.add(uint32(tag))
    relation.tags.sort()
    result.windowTags.add(relation)
  var viewIds = adapter.model.views.ids
  viewIds.sort(
    proc(left, right: ViewId): int =
      cmp(uint32(left), uint32(right))
  )
  for id in viewIds:
    var relation = TagRelationDto(owner: uint32(id))
    for tag in adapter.model.viewTagIds(id):
      relation.tags.add(uint32(tag))
    relation.tags.sort()
    result.viewTags.add(relation)
  for id in adapter.model.minimizedOrder:
    result.minimizedOrder.add(uint32(id))
  for id in adapter.model.affinityOrder:
    result.affinities.add(adapter.model.affinities[id])
    result.affinityOrder.add(uint32(id))
  for id in adapter.model.scratchpadOrder:
    result.scratchpadOrder.add(uint32(id))
    result.scratchpadRestore.add(
      ScratchpadRestoreDto(
        window: uint32(id), restore: adapter.model.scratchpadRestore[id]
      )
    )
  for slot, window in adapter.model.namedScratchpads.pairs:
    result.namedScratchpads.add(
      NamedScratchpadDto(slot: uint32(slot), window: uint32(window))
    )
  result.namedScratchpads.sort(
    proc(left, right: NamedScratchpadDto): int =
      cmp(left.slot, right.slot)
  )
  for groupId in adapter.model.groups.ids:
    result.groups.add(adapter.model.groups[groupId])
  for window, group in adapter.model.groupOfWindow.pairs:
    result.groupOfWindow.add(
      GroupRelationDto(window: uint32(window), group: uint32(group))
    )
  result.groupOfWindow.sort(
    proc(left, right: GroupRelationDto): int =
      cmp(left.window, right.window)
  )
  result.visibleScratchpad = uint32(adapter.model.visibleScratchpad)
  result.scratchpadTag = uint32(adapter.model.scratchpadTag)
  for key, window in adapter.surfaceToWindow.pairs:
    result.surfaces.add(
      SurfaceDto(
        key: key,
        window: uint32(window),
        facts: adapter.surfaceFacts[window],
        presentedMaximized: adapter.presentedMaximized[window],
      )
    )
  result.surfaces.sort(
    proc(left, right: SurfaceDto): int =
      cmp(left.window, right.window)
  )
  for handle, logical in adapter.activeOutputToLogical.pairs:
    result.activeOutputs.add(
      OutputDto(
        output: handle.output, generation: handle.generation, logical: uint32(logical)
      )
    )
  result.activeOutputs.sort(
    proc(left, right: OutputDto): int =
      cmp(left.logical, right.logical)
  )
  for handle, logical in adapter.dormantOutputToLogical.pairs:
    result.dormantOutputs.add(
      OutputDto(
        output: handle.output, generation: handle.generation, logical: uint32(logical)
      )
    )
  result.dormantOutputs.sort(
    proc(left, right: OutputDto): int =
      cmp(left.logical, right.logical)
  )

proc checkpointPayload*(adapter: PolicyAdapter): string =
  "HAGIA-POLICY-CHECKPOINT-19\n" & $adapter.checkpointDto().toJson()

proc migratedProportion(percent: int): JsonNode =
  ## A checkpointed percentage as the proportion the percent resolver produced
  ## for it, so a payload written before proportions existed restores to the
  ## pixels it had rather than the nearest ones the new vocabulary can state.
  toJson(proportionExtent(scaleFromRatio(uint32(max(0, percent)), 100)))

proc restoreCheckpointPayload*(payload: string): PolicyAdapter =
  # Version 4 predates tab trees, version 5 predates dwindle preselects,
  # version 6 predates named views and placement sizing, version 7 predates
  # the scroller camera and the default column width, version 8 stored a
  # maximised column as a width, version 9 shared one camera across both
  # scroll axes, version 12 predates focus-follows-mouse, and version 13 stored
  # a floating rectangle without saying whether it was a rule or a decision;
  # version 14 predates the emitted maximize bit used to recognize scene echoes.
  # Version 15 predates uniform gaps and explicit tiling struts, and version
  # 16 stated column widths and their defaults as integer percentages, before
  # proportions and fixed pixels.
  # Each migrates forward by filling the fields it could not have written.
  var version = 19
  for legacy in [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]:
    if payload.startsWith("HAGIA-POLICY-CHECKPOINT-" & $legacy & "\n"):
      version = legacy
  let prefix = "HAGIA-POLICY-CHECKPOINT-" & $version & "\n"
  for superseded in ["1", "2", "3"]:
    if payload.startsWith("HAGIA-POLICY-CHECKPOINT-" & superseded & "\n"):
      fail(
        "policy checkpoint v" & superseded &
          " is unsupported; a complete snapshot will rebuild it"
      )
  if not payload.startsWith(prefix):
    fail("policy checkpoint version is invalid")
  var dto: CheckpointV4Dto
  try:
    var node = payload[prefix.len .. ^1].parseJson()
    if version <= 18:
      # Older sessions always allowed directional output handoff.
      node["settings"]["arrowCrossesOutputs"] = toJson(true)
    if version == 4:
      node["tabTrees"] = newJArray()
    if version <= 5:
      for item in node["tabTrees"]:
        for treeNode in item["tree"]["nodes"]:
          treeNode["preselect"] = toJson(TabTreePreselect.none)
    if version <= 6:
      node["settings"]["viewNames"] = newJArray()
      node["settings"]["viewLayouts"] = newJArray()
      node["settings"]["presetColumnWidths"] =
        toJson(defaultPolicySettings.presetColumnWidths)
      node["settings"]["scratchpadWidthPercent"] =
        toJson(defaultPolicySettings.scratchpadWidthPercent)
      node["settings"]["scratchpadHeightPercent"] =
        toJson(defaultPolicySettings.scratchpadHeightPercent)
      node["settings"]["floatingWidthPercent"] = toJson(0'i32)
      node["settings"]["floatingHeightPercent"] = toJson(0'i32)
    if version <= 7:
      # A camera resting at the origin is the honest restore: the strip is
      # rebuilt from the columns, and the first focus settles it where the
      # rule says it belongs rather than somewhere a previous run happened to
      # leave it.
      for viewNode in node["views"]:
        viewNode["viewportOffset"] = toJson(0'i32)
      node["settings"]["defaultColumnWidth"] =
        toJson(defaultPolicySettings.defaultColumnWidth)
      node["settings"]["centerFocusedColumn"] =
        toJson(defaultPolicySettings.centerFocusedColumn)
    if version <= 8:
      node["settings"]["alwaysCenterSingleColumn"] =
        toJson(defaultPolicySettings.alwaysCenterSingleColumn)
      # A version-8 column at exactly full width was maximised, so it becomes
      # one that is flagged rather than sized. The two are indistinguishable
      # in a v8 payload -- someone may have grown a column to precisely this
      # width -- and reading it as maximised is the recoverable answer: the
      # key that maximised it can put it back, where a width has no way home.
      for columnNode in node["columns"]:
        # A payload relabelled to this version from a newer one already states
        # its width as an extent; only a genuine v8 column carries the scale
        # this reads, and only it needs the flag derived from one.
        if not columnNode.hasKey("widthScale"):
          if not columnNode.hasKey("fullWidth"):
            columnNode["fullWidth"] = toJson(false)
          continue
        let maximized = columnNode["widthScale"].getInt() == int(scaleOne)
        columnNode["fullWidth"] = toJson(maximized)
        if maximized:
          columnNode["widthScale"] = toJson(autoScale)
    if version <= 9:
      # The vertical camera starts at the origin: the one stored offset was
      # horizontal, and the first vertical projection settles its own.
      for viewNode in node["views"]:
        viewNode["viewportOffsetY"] = toJson(0'i32)
    if version <= 10:
      # Zero and empty mean inherit the column values, which is what a
      # profile written before these keys existed was getting anyway.
      node["settings"]["defaultRowHeight"] =
        toJson(defaultPolicySettings.defaultRowHeight)
      node["settings"]["presetRowHeights"] = newJArray()
    if version <= 11:
      for viewNode in node["views"]:
        viewNode["camera"] = toJson(CameraAnchor())
        viewNode["cameraY"] = toJson(CameraAnchor())
        viewNode["openedColumn"] = toJson(nullColumnId)
        viewNode["openingFocus"] = toJson(nullWindowId)
        viewNode["openingOffset"] = toJson(0'i32)
        viewNode["openingOffsetY"] = toJson(0'i32)
    if version <= 12:
      # Off is what a profile written before this key existed was getting, and
      # it is the default the key itself carries.
      node["settings"]["focusFollowsMouse"] = toJson(false)
    if version <= 13:
      # Every stored rectangle is treated as the operator's. A version-13
      # payload cannot say which positions were automatic, and re-deriving one
      # the operator had dragged would move a window they placed; leaving a
      # genuinely automatic dialog where it is only costs it a later follow.
      # Only where the field is absent: a payload relabelled to an older
      # version still carries what it wrote, and a migration fills gaps rather
      # than overwriting answers.
      for windowNode in node["windows"]:
        if not windowNode.hasKey("floatingIntent"):
          windowNode["floatingIntent"] = toJson(FloatingIntent.manual)
      for entry in node["scratchpadRestore"]:
        if not entry["restore"].hasKey("floatingIntent"):
          entry["restore"]["floatingIntent"] = toJson(FloatingIntent.manual)
    if version <= 14:
      for surface in node["surfaces"]:
        if not surface.hasKey("presentedMaximized"):
          surface["presentedMaximized"] =
            toJson((surface["facts"]["currentStateBits"].getInt() and 2) != 0)
      # The old implementation permitted both modes and presented window
      # maximization. Preserve that visible choice while migrating its state.
      for window in node["windows"]:
        if window["maximized"].getBool():
          for column in node["columns"]:
            if column["id"] == window["column"]:
              column["fullWidth"] = toJson(false)
    if version <= 15:
      node["settings"]["gapModel"] = toJson(GapModel.legacy)
      node["settings"]["gaps"] = toJson(0'i32)
      node["settings"]["struts"] = toJson(LayoutStruts())
    if version <= 16:
      # Percentages become proportions through exactly the conversion the old
      # resolver used, so a restored strip lands on the same pixels rather than
      # the nearest new ones. Fixed pixels cannot appear in such a payload:
      # nothing able to write one could have written this version.
      #
      # Only where the old field is present, because a payload relabelled to an
      # older version still carries what it wrote and a rung above may already
      # have supplied the current spelling. The fills afterwards are what make
      # the rung total: the DTO matches keys exactly, so every field has to
      # exist by the end of it however the payload got here.
      let settings = node["settings"]
      if settings.hasKey("defaultColumnWidthPercent"):
        settings["defaultColumnWidth"] =
          migratedProportion(settings["defaultColumnWidthPercent"].getInt())
        settings.delete("defaultColumnWidthPercent")
      if settings.hasKey("defaultRowHeightPercent"):
        let percent = settings["defaultRowHeightPercent"].getInt()
        # Zero was the sentinel for "inherit the column default", which an
        # extent spells `automatic` and which is still the zero value.
        settings["defaultRowHeight"] =
          if percent == 0:
            toJson(automaticExtent)
          else:
            migratedProportion(percent)
        settings.delete("defaultRowHeightPercent")
      for pair in [
        ("columnWidthPresets", "presetColumnWidths"),
        ("rowHeightPresets", "presetRowHeights"),
      ]:
        if settings.hasKey(pair[0]):
          var presets = newJArray()
          for preset in settings[pair[0]]:
            presets.add(migratedProportion(preset.getInt()))
          settings[pair[1]] = presets
          settings.delete(pair[0])
      if not settings.hasKey("defaultColumnWidth"):
        settings["defaultColumnWidth"] =
          toJson(defaultPolicySettings.defaultColumnWidth)
      if not settings.hasKey("defaultRowHeight"):
        settings["defaultRowHeight"] = toJson(defaultPolicySettings.defaultRowHeight)
      if not settings.hasKey("presetColumnWidths"):
        settings["presetColumnWidths"] =
          toJson(defaultPolicySettings.presetColumnWidths)
      if not settings.hasKey("presetRowHeights"):
        settings["presetRowHeights"] = newJArray()
      for columnNode in node["columns"]:
        if columnNode.hasKey("widthScale"):
          let raw = uint32(columnNode["widthScale"].getInt())
          columnNode["width"] =
            if raw == uint32(autoScale):
              toJson(automaticExtent)
            else:
              toJson(proportionExtent(Scale(raw)))
          columnNode.delete("widthScale")
        elif not columnNode.hasKey("width"):
          columnNode["width"] = toJson(automaticExtent)
    if version <= 17:
      node["settings"]["workspaceAssignments"] = newJArray()
      for output in node["outputs"]:
        output["policyKey"] = %0
      for affinity in node["affinities"]:
        affinity["policyKey"] = %0
    dto = node.jsonTo(CheckpointV4Dto)
  except CatchableError:
    fail("policy checkpoint payload is malformed")
  if dto.schema != uint32(version):
    fail("policy checkpoint schema is invalid")
  for item in dto.tabTrees:
    let view = ViewId(item.view)
    if view in result.model.tabTrees:
      fail("duplicate checkpoint tab tree")
    item.tree.validateTabTree()
    result.model.tabTrees[view] = item.tree
  result.model.counters = dto.counters
  if dto.settings.layoutCycle.len == 0:
    dto.settings.layoutCycle = defaultLayoutCycle
  result.model.settings = dto.settings
  result.model.activeOutput = OutputId(dto.activeOutput)
  for window in dto.windows:
    result.model.windows[window.id] = window
  for raw in dto.windowOrder:
    result.model.windowOrder.add(WindowId(raw))
  for column in dto.columns:
    result.model.columns[column.id] = column
  for raw in dto.columnOrder:
    result.model.columnOrder.add(ColumnId(raw))
  for view in dto.views:
    result.model.views[view.id] = view
  for tag in dto.tags:
    result.model.tags[tag.id] = tag
  for output in dto.outputs:
    result.model.outputs[output.id] = output
  for raw in dto.outputOrder:
    result.model.outputOrder.add(OutputId(raw))
  for relation in dto.windowTags:
    let owner = WindowId(relation.owner)
    for raw in relation.tags:
      result.model.windowTags.mgetOrPut(owner, @[]).add(TagId(raw))
  for relation in dto.viewTags:
    let owner = ViewId(relation.owner)
    for raw in relation.tags:
      result.model.viewTags.mgetOrPut(owner, @[]).add(TagId(raw))
  for raw in dto.minimizedOrder:
    result.model.minimizedOrder.add(WindowId(raw))
  if dto.scratchpadOrder.len != dto.scratchpadRestore.len:
    fail("policy checkpoint scratchpad records diverged")
  for index, raw in dto.scratchpadOrder:
    let id = WindowId(raw)
    if dto.scratchpadRestore[index].window != raw:
      fail("policy checkpoint scratchpad order is invalid")
    result.model.scratchpadOrder.add(id)
    result.model.scratchpadRestore[id] = dto.scratchpadRestore[index].restore
  for relation in dto.namedScratchpads:
    result.model.namedScratchpads[ScratchpadSlotId(relation.slot)] =
      WindowId(relation.window)
  for group in dto.groups:
    result.model.groups[group.id] = group
  for relation in dto.groupOfWindow:
    result.model.groupOfWindow[WindowId(relation.window)] = GroupId(relation.group)
  result.model.visibleScratchpad = WindowId(dto.visibleScratchpad)
  result.model.scratchpadTag = TagId(dto.scratchpadTag)
  if dto.affinities.len != dto.affinityOrder.len:
    fail("policy checkpoint affinity records diverged")
  for index, raw in dto.affinityOrder:
    let id = OutputId(raw)
    result.model.affinities[id] = dto.affinities[index]
    result.model.affinityOrder.add(id)
  for surface in dto.surfaces:
    let window = WindowId(surface.window)
    result.surfaceToWindow[surface.key] = window
    result.windowToSurface[window] = surface.key
    result.surfaceFacts[window] = surface.facts
    result.presentedMaximized[window] = surface.presentedMaximized
  for output in dto.activeOutputs:
    let handle = (output: output.output, generation: output.generation)
    let logical = OutputId(output.logical)
    result.activeOutputToLogical[handle] = logical
    result.outputToLogical[output.output] = logical
    result.logicalToOutput[logical] = handle
  for output in dto.dormantOutputs:
    result.dormantOutputToLogical[
      (output: output.output, generation: output.generation)
    ] = OutputId(output.logical)
  result.model.validate()
  if result.surfaceToWindow.len > maxSurfaces or
      result.surfaceToWindow.len != result.windowToSurface.len or
      result.surfaceToWindow.len != result.surfaceFacts.len or
      result.surfaceToWindow.len != result.presentedMaximized.len or
      result.surfaceToWindow.len != result.model.windows.len or
      result.activeOutputToLogical.len > maxOutputs or
      result.activeOutputToLogical.len != result.outputToLogical.len or
      result.activeOutputToLogical.len != result.logicalToOutput.len or
      result.activeOutputToLogical.len != result.model.outputs.len or
      result.dormantOutputToLogical.len > maxOutputAffinities or
      result.dormantOutputToLogical.len != result.model.affinities.len:
    fail("policy checkpoint exceeds bounded identities")
  for key, window in result.surfaceToWindow.pairs:
    if window notin result.model.windows or window notin result.windowToSurface or
        result.windowToSurface[window] != key:
      fail("policy checkpoint surface indexes diverged")
  for window, key in result.windowToSurface.pairs:
    if key notin result.surfaceToWindow or result.surfaceToWindow[key] != window or
        window notin result.surfaceFacts or
        result.surfaceFacts[window].surfaceKey() != key:
      fail("policy checkpoint reverse surface index diverged")
  for handle, output in result.activeOutputToLogical.pairs:
    if output notin result.model.outputs or output notin result.logicalToOutput or
        result.logicalToOutput[output] != handle or
        result.outputToLogical.getOrDefault(handle.output) != output:
      fail("policy checkpoint active output indexes diverged")
  for handle, output in result.dormantOutputToLogical.pairs:
    if output notin result.model.affinities or output in result.logicalToOutput:
      fail("policy checkpoint dormant output indexes diverged")
  for rawOutput, output in result.outputToLogical.pairs:
    if output notin result.logicalToOutput or
        result.logicalToOutput[output].output != rawOutput:
      fail("policy checkpoint raw output indexes diverged")
  for output in result.model.affinityOrder:
    var found = false
    for _, dormantOutput in result.dormantOutputToLogical.pairs:
      if dormantOutput == output:
        if found:
          fail("policy checkpoint dormant output is ambiguous")
        found = true
    if not found:
      fail("policy checkpoint output affinity has no opaque handle")

proc targetOutputAction*(
    adapter: var PolicyAdapter, request: ProjectionRequest
): OutputId =
  if request.cause.kind != ProjectionCauseKind.outputAction:
    fail("expected explicit output action")
  if request.cause.output notin adapter.outputToLogical or
      request.cause.activationSerial == 0 or request.cause.action == 0:
    fail("targeted policy action is invalid")
  let target = adapter.outputToLogical[request.cause.output]
  if adapter.logicalToOutput[target].generation != request.cause.outputGeneration:
    fail("targeted policy action output was replaced")
  if adapter.model.settings.workspaceAssignments.len > 0 and
      request.cause.action in
      uint64(ord(PolicyAction.activateView1)) .. uint64(ord(PolicyAction.activateView9)):
    let number = int(request.cause.action) - ord(PolicyAction.activateView1) + 1
    if adapter.model.workspaceHost(number)[0] != target:
      fail("targeted workspace action belongs to another output")
  adapter.model.setActiveOutput(target)
  target

proc applyCause*(adapter: var PolicyAdapter, request: ProjectionRequest) =
  if request.affectedOutputs.len == 0:
    fail("policy cause has no affected output")
  let rawOutput = request.affectedOutputs[0]
  if rawOutput notin adapter.outputToLogical:
    fail("policy cause names an unknown output")
  let output = adapter.model.activeOutput
  var message = PolicyMsg(kind: PolicyMsgKind.sceneChanged, output: output)
  case request.cause.kind
  of ProjectionCauseKind.sceneChanged:
    discard
  of ProjectionCauseKind.outputAction:
    let target = adapter.targetOutputAction(request)
    message = PolicyMsg(
      kind: PolicyMsgKind.action,
      output: target,
      action: request.cause.action.policyAction(),
    )
  of ProjectionCauseKind.action:
    if request.cause.activationSerial == 0 or not request.cause.action.isPolicyAction():
      fail("policy action cause is invalid")
    message = PolicyMsg(
      kind: PolicyMsgKind.action,
      output: output,
      action: request.cause.action.policyAction(),
    )
  of ProjectionCauseKind.focus:
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy focus cause names an unknown surface")
    let window = adapter.surfaceToWindow[key]
    message = PolicyMsg(
      kind: PolicyMsgKind.focus,
      output: adapter.model.windows[window].homeOutput,
      focusWindow: window,
    )
  of ProjectionCauseKind.pointerFocus:
    # The Engine hit-tests its own presented pixels and reports what the
    # pointer settled on. Policy never sees motion, so this arm only resolves
    # the opaque identities and lets the reducer decide whether the profile
    # asked for any of it.
    if request.cause.action notin adapter.outputToLogical:
      fail("policy pointer-focus cause names an unknown output")
    let pointerOutput = adapter.outputToLogical[request.cause.action]
    var pointerWindow = nullWindowId
    if request.cause.targetGeneration != 0:
      let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
      if key notin adapter.surfaceToWindow:
        fail("policy pointer-focus cause names an unknown surface")
      pointerWindow = adapter.surfaceToWindow[key]
      # A target that has moved output since the observation was taken would
      # otherwise focus a window the pointer is no longer over.
      if adapter.model.windows[pointerWindow].homeOutput != pointerOutput:
        fail("policy pointer-focus target does not live on the named output")
    message = PolicyMsg(
      kind: PolicyMsgKind.pointerFocus,
      output: pointerOutput,
      pointerWindow: pointerWindow,
    )
  of ProjectionCauseKind.interaction:
    let key = surfaceKey(request.cause.targetIndex, request.cause.targetGeneration)
    if key notin adapter.surfaceToWindow:
      fail("policy interaction cause names an unknown surface")
    let window = adapter.surfaceToWindow[key]
    let interactionOutput = adapter.model.windows[window].homeOutput
    let geometry = Rect(
      x: request.cause.x,
      y: request.cause.y,
      width: request.cause.width,
      height: request.cause.height,
    )
    if request.cause.interactionPhase == InteractionPhase.cancel:
      message = PolicyMsg(kind: PolicyMsgKind.sceneChanged, output: interactionOutput)
      adapter.model = adapter.model.reducePolicy(message).candidate
      recordEvidence(
        EvidenceEvent(
          kind: EvidenceKind.reducer,
          event: "interaction",
          epoch: request.connectionEpoch,
          generation: request.policyGeneration,
          requestId: request.requestId,
          status: $request.cause.interactionPhase,
        )
      )
      return
    case request.cause.interactionKind
    of InteractionKind.move:
      message = PolicyMsg(
        kind: PolicyMsgKind.interaction,
        output: interactionOutput,
        interactionWindow: window,
        interactionKind: PolicyInteractionKind.move,
        geometry: geometry,
      )
    of InteractionKind.resize:
      message = PolicyMsg(
        kind: PolicyMsgKind.interaction,
        output: interactionOutput,
        interactionWindow: window,
        interactionKind: PolicyInteractionKind.resize,
        geometry: geometry,
      )
    of InteractionKind.drag:
      message = PolicyMsg(
        kind: PolicyMsgKind.interaction,
        output: interactionOutput,
        interactionWindow: window,
        interactionKind: PolicyInteractionKind.move,
        geometry: geometry,
      )
    of InteractionKind.scroll:
      fail("policy interaction kind is not implemented")
    else:
      fail("policy interaction kind is invalid")
  adapter.model = adapter.model.reducePolicy(message).candidate
  recordEvidence(
    EvidenceEvent(
      kind: EvidenceKind.reducer,
      event: "cause_applied",
      epoch: request.connectionEpoch,
      generation: request.policyGeneration,
      requestId: request.requestId,
      status: $message.kind,
    )
  )

## Reconcile only complete Sophia snapshots. The policy model never observes a
## partial transfer or stores a Sophia identity in its own entity tables.
proc reconcile*(adapter: var PolicyAdapter, snapshot: PolicySnapshot) =
  if snapshot.generation == 0 or snapshot.outputs.len == 0:
    fail("Sophia snapshot is empty")
  if snapshot.activeOutput == 0:
    fail("Sophia snapshot has no active output")

  # The first complete snapshot may be a WM restart over existing windows.
  # Only later admissions may replace the Engine's reconciled focus.
  let established = adapter.activeOutputToLogical.len > 0
  var newWindows: seq[WindowId]
  var previousActive: seq[(OutputHandle, OutputId)]
  for output, logical in adapter.activeOutputToLogical.pairs:
    previousActive.add((output, logical))
  var liveOutputs = initHashSet[OutputHandle]()
  var liveLogical = initHashSet[OutputId]()
  var liveKeys = initHashSet[uint64]()
  let assigned = adapter.model.settings.workspaceAssignments.len > 0
  var oldActive = adapter.activeOutputToLogical
  var oldDormant = adapter.dormantOutputToLogical
  var nextActive = initTable[OutputHandle, OutputId]()
  var nextRaw = initTable[uint64, OutputId]()
  for output in snapshot.outputs:
    let current = output.handle()
    if current in liveOutputs or output.output in nextRaw:
      fail("snapshot repeats an output")
    liveOutputs.incl(current)
    if assigned:
      if output.policyKey == 0 or output.policyKey in liveKeys:
        fail("assigned snapshot requires unique output policy keys")
      liveKeys.incl(output.policyKey)
    var logical = nullOutputId
    var dormant = none(OutputHandle)
    for handle, id in oldActive.pairs:
      let key = adapter.model.outputs[id].policyKey
      if (assigned and key != 0 and key == output.policyKey) or
          (handle == current and (not assigned or key == 0)):
        if logical != nullOutputId:
          fail("live output affinity is ambiguous")
        logical = id
    for handle, id in oldDormant.pairs:
      let key = adapter.model.affinities[id].policyKey
      if (assigned and key != 0 and key == output.policyKey) or
          (handle == current and (not assigned or key == 0)):
        if logical != nullOutputId:
          fail("saved output affinity is ambiguous")
        logical = id
        dormant = some(handle)
    if logical in liveLogical:
      fail("two outputs claim the same policy owner")
    if logical == nullOutputId:
      logical = adapter.model.addOutput(
        output.bounds(), (if assigned: output.policyKey else: 0)
      )
    elif dormant.isSome:
      adapter.model.restoreOutput(logical, output.bounds())
      adapter.dormantOutputToLogical.del(dormant.get())
    else:
      adapter.model.updateOutput(logical, output.bounds())
    if assigned:
      adapter.model.bindOutputPolicyKey(logical, output.policyKey)
    adapter.model.ensureViewCount(logical, adapter.model.settings.viewCount)
    liveLogical.incl(logical)
    nextActive[current] = logical
    nextRaw[output.output] = logical
    adapter.logicalToOutput[logical] = current
  adapter.activeOutputToLogical = nextActive
  adapter.outputToLogical = nextRaw
  if snapshot.activeOutput notin adapter.outputToLogical:
    fail("Sophia snapshot active output is not live")
  adapter.model.setActiveOutput(adapter.outputToLogical[snapshot.activeOutput])

  # An echo is only meaningful against the token space this connection minted.
  # Before this adapter has published anything -- a fresh process, or one
  # restored from a checkpoint, which carries no tokens -- every echo is by
  # definition stale. Stale is ordinary placement, not a protocol failure:
  # refusing the cycle would drop the connection over a window that simply
  # opens where it otherwise would have.
  # The session synchronises the token epoch from the authenticated request
  # before this runs, so a current-epoch echo whose token the cache no longer
  # holds falls back to ordinary placement while a malformed or cross-epoch
  # record is still refused.
  snapshot.launchOrigins.validateLaunchOrigins(adapter.launchEpoch)
  var launchOrigins = initTable[uint64, uint64]()
  for record in snapshot.launchOrigins:
    launchOrigins[surfaceKey(record.surfaceIndex, record.surfaceGeneration)] =
      record.token

  var launchClassifications = initTable[uint64, uint64]()
  for classification in snapshot.classifications:
    launchClassifications[
      surfaceKey(classification.surfaceIndex, classification.surfaceGeneration)
    ] = classification.classification

  let fallback = adapter.outputToLogical[snapshot.outputs[0].output]
  for item in previousActive:
    let (output, logical) = item
    if logical in liveLogical:
      continue
    let evicted = adapter.model.removeOutput(logical, fallback)
    adapter.dormantOutputToLogical[output] = logical
    if output.output in adapter.outputToLogical and
        adapter.outputToLogical[output.output] == logical:
      adapter.outputToLogical.del(output.output)
    adapter.logicalToOutput.del(logical)
    if evicted.isSome:
      var evictedHandles: seq[OutputHandle]
      for handle, dormantLogical in adapter.dormantOutputToLogical.pairs:
        if dormantLogical == evicted.get():
          evictedHandles.add(handle)
      for handle in evictedHandles:
        adapter.dormantOutputToLogical.del(handle)

  var liveSurfaces = initHashSet[uint64]()
  for surface in snapshot.surfaces:
    let key = surface.surfaceKey()
    liveSurfaces.incl(key)
    if key in adapter.surfaceToWindow:
      let window = adapter.surfaceToWindow[key]
      adapter.model.updateWindowFacts(
        window, surface.capabilityBits.capabilities(), surface.constraints()
      )
      let presented = (surface.currentStateBits and 2) != 0
      var intentBits = surface.currentStateBits
      if presented == adapter.presentedMaximized[window] and
          (surface.currentStateBits and 5) == 0:
        let retained = adapter.model.window(window).get().maximized
        intentBits = (intentBits and not 2'u16) or (if retained: 2'u16 else: 0'u16)
      adapter.model.applyPresentation(window, intentBits)
      adapter.presentedMaximized[window] = presented
      if surface.currentOutput != 0:
        adapter.model.adoptWindowOutput(
          window, adapter.outputToLogical[surface.currentOutput]
        )
      adapter.surfaceFacts[window] = surface
    else:
      let rawHome =
        if key in launchClassifications or surface.currentOutput == 0:
          snapshot.activeOutput
        else:
          surface.currentOutput
      if rawHome notin adapter.outputToLogical:
        fail("surface home output is not present")
      let window = adapter.model.addWindow(
        adapter.outputToLogical[rawHome],
        surface.capabilityBits.capabilities(),
        surface.constraints(),
      )
      newWindows.add(window)
      adapter.surfaceToWindow[key] = window
      adapter.windowToSurface[window] = key
      adapter.surfaceFacts[window] = surface
      adapter.model.applyPresentation(window, surface.currentStateBits)
      adapter.presentedMaximized[window] = (surface.currentStateBits and 2) != 0
      if key in launchClassifications:
        let classification = launchClassifications[key]
        # Hagia's retained daily-driver vocabulary maps classes 1..9 to its
        # corresponding view slots. Unknown opaque classes are advisory and
        # remain intentionally ignorable.
        if classification >= 1 and classification <= uint64(high(int)) and
            int(classification) <= adapter.model.settings.viewCount:
          adapter.model.placeWindowInViewSlot(
            window, adapter.outputToLogical[snapshot.activeOutput], int(classification)
          )
      elif key in launchOrigins:
        # After an explicit class and before ordinary placement. A transient
        # owner is not resolved yet at this point in the pass: the loop below
        # re-places any surface that turns out to have one, overwriting both
        # the output and the tags set here, so a dialog never keeps its
        # launcher's membership.
        #
        # A token the cache no longer holds, or one naming an output no live
        # handle maps to, resolves to nothing and the window opens where it
        # otherwise would have.
        let token = launchOrigins[key]
        if token in adapter.launchTokens:
          let destination = adapter.launchTokens[token]
          if destination.output in adapter.liveLogicalOutputs():
            adapter.model.placeLaunchOrigin(
              window, destination.output, destination.tags
            )

  var removedSurfaces: seq[uint64]
  for key in adapter.surfaceToWindow.keys:
    if key notin liveSurfaces:
      removedSurfaces.add(key)
  var removalFocusOutputs: seq[OutputId]
  for key in removedSurfaces:
    let window = adapter.surfaceToWindow[key]
    for outputId in adapter.model.outputOrder:
      if adapter.model.outputs[outputId].focusedWindow == window:
        removalFocusOutputs.add(outputId)
    adapter.model.removeWindow(window)
    adapter.surfaceToWindow.del(key)
    adapter.windowToSurface.del(window)
    adapter.surfaceFacts.del(window)
    adapter.presentedMaximized.del(window)

  # Resolve reduced transient ownership only after every live Sophia handle has
  # a stable logical identity. No generational handle crosses this boundary.
  for surface in snapshot.surfaces:
    let window = adapter.surfaceToWindow[surface.surfaceKey()]
    var parent = nullWindowId
    if surface.transientGeneration != 0:
      let parentKey = surfaceKey(surface.transientIndex, surface.transientGeneration)
      if parentKey notin adapter.surfaceToWindow:
        fail("surface transient owner has no logical identity")
      parent = adapter.surfaceToWindow[parentKey]
    let kind = surface.kind.windowKind()
    let relationChanged =
      adapter.model.windows[window].kind != kind or
      adapter.model.windows[window].parent != parent
    adapter.model.setWindowRelation(window, kind, parent)
    let inheritanceChanged =
      parent != nullWindowId and (
        adapter.model.windows[window].homeOutput !=
        adapter.model.windows[parent].homeOutput or
        adapter.model.windowTagIds(window) != adapter.model.windowTagIds(parent)
      )
    if (relationChanged or inheritanceChanged) and parent != nullWindowId and
        kind in {WindowKind.dialog, WindowKind.utility} and
        window notin adapter.model.scratchpadRestore:
      let parentOutput = adapter.model.windows[parent].homeOutput
      let parentBounds = adapter.model.outputs[parentOutput].bounds
      let parentFacts = adapter.surfaceFacts[parent]
      adapter.model.placeTransient(
        window,
        parent,
        (if surface.width > 0: surface.width
        else: parentBounds.width div 2),
        (if surface.height > 0: surface.height
        else: parentBounds.height div 2),
        Rect(
          x: parentFacts.x,
          y: parentFacts.y,
          width: parentFacts.width,
          height: parentFacts.height,
        ),
      )

  for output in snapshot.outputs:
    if output.focusGeneration == 0:
      let logical = adapter.outputToLogical[output.output]
      if logical notin removalFocusOutputs:
        adapter.model.clearFocus(logical)
      continue
    let key = surfaceKey(output.focusIndex, output.focusGeneration)
    if key in adapter.surfaceToWindow:
      let window = adapter.surfaceToWindow[key]
      try:
        adapter.model.setFocus(adapter.outputToLogical[output.output], window)
      except PolicyStateError:
        discard
  if established:
    adapter.model.focusNewWindows(
      adapter.outputToLogical[snapshot.activeOutput], newWindows
    )
  # Sophia names the active output and restoring focus must not move it.
  # `setFocus` makes its own output active, so without this the last output
  # carrying focus in the snapshot decides where the next action lands -- on a
  # two-output desktop where both remember a focused window, that is the wrong
  # one. The handle was proved live when it was first established above.
  adapter.model.setActiveOutput(adapter.outputToLogical[snapshot.activeOutput])
  adapter.model.validate()

proc projection*(
    adapter: var PolicyAdapter, snapshot: PolicySnapshot, request: ProjectionRequest
): PolicyProjection =
  ## Takes `var` because the scroller camera is state, not a derived value: the
  ## offset this projection settles on is where the view now sits. It rides the
  ## same transaction as everything else here, so a rejected projection leaves
  ## the camera where it was.
  if request.sceneGeneration != snapshot.generation:
    fail("projection request names a stale snapshot")
  result.activeOutput = snapshot.activeOutput
  var affected: seq[OutputId]
  for output in request.affectedOutputs:
    if output notin adapter.outputToLogical:
      fail("projection request names an unknown output")
    affected.add(adapter.outputToLogical[output])

  adapter.synchronizeLaunchEpoch(request.connectionEpoch)
  result.launchContexts = adapter.launchContexts(request.connectionEpoch)
  result.outputLaunchContexts = adapter.outputLaunchContexts(request.connectionEpoch)
  let (outerGap, innerGap) = adapter.model.effectiveGaps()
  # Fullscreen is the one placement that needs the physical display rather than
  # the work area, and the logical model does not hold it. Handing it to the
  # projection keeps the rectangle a dialog centres on and the rectangle its
  # parent is given the same one; correcting it here afterwards would not.
  var physicalBounds: seq[(OutputId, Rect)]
  for candidate in snapshot.outputs:
    if candidate.output in adapter.outputToLogical:
      physicalBounds.add(
        (
          adapter.outputToLogical[candidate.output],
          Rect(
            x: candidate.x,
            y: candidate.y,
            width: candidate.width,
            height: candidate.height,
          ),
        )
      )
  for logical in adapter.model.projectLayout(
    affected, outerGap, innerGap, adapter.model.settings.viewportOffset, physicalBounds
  ):
    # The camera the projection settled on is where this view now sits, so it
    # is written back before the next projection reads it. Without this the
    # strip recomputes from the configured offset every time and springs back.
    if logical.cameraDecided:
      adapter.model.rememberViewportOffset(
        logical.output, logical.viewportOffset, logical.camera
      )
    let rawOutput = adapter.logicalToOutput[logical.output].output
    var outputSnapshot: SnapshotOutput
    var foundOutput = false
    for candidate in snapshot.outputs:
      if candidate.output == rawOutput:
        outputSnapshot = candidate
        foundOutput = true
        break
    if not foundOutput:
      fail("logical output has no current Sophia record")
    var output = ProjectionOutput(
      output: rawOutput, placementCount: uint32(logical.placements.len)
    )
    if logical.focus != nullWindowId:
      let key = adapter.windowToSurface[logical.focus]
      output.focusIndex = uint32(key and 0xffffffff'u64)
      output.focusGeneration = uint32(key shr 32)
    if logical.cameraDecided:
      let view = adapter.model.views[adapter.model.outputs[logical.output].activeView]
      var group = ProjectionTranslationGroup(output: rawOutput, group: uint64(view.id))
      if view.layout == LayoutMode.verticalScroller:
        group.y = -logical.viewportOffset
      else:
        group.x = -logical.viewportOffset
      for placement in logical.placements:
        let window = adapter.model.windows[placement.window]
        if not window.floating and not window.fullscreen and not placement.maximized:
          let key = adapter.windowToSurface[placement.window]
          group.members.add(
            ProjectionTabMember(
              surfaceIndex: uint32(key and 0xffffffff'u64),
              surfaceGeneration: uint32(key shr 32),
            )
          )
      if group.members.len > 0:
        result.translationGroups.add(group)
    var projection = PolicyOutputProjection(output: output)
    for placement in logical.placements:
      if placement.window notin adapter.surfaceFacts:
        fail("logical window has no current Sophia facts")
      let surface = adapter.surfaceFacts[placement.window]
      let window = adapter.model.windows[placement.window]
      # Settled inside the projection, where a dialog could still see it.
      let geometry = placement.geometry
      var presentationBits = 0'u16
      if window.fullscreen:
        presentationBits = presentationBits or (1'u16 shl 0)
      if placement.maximized:
        presentationBits = presentationBits or (1'u16 shl 1)
      adapter.presentedMaximized[placement.window] = placement.maximized
      let requestedWidth =
        if window.fullscreen or placement.maximized:
          constrainedExtent(
            geometry.width, surface.minWidth, surface.maxWidth, surface.exactWidth
          )
        else:
          placement.requestedWidth
      let requestedHeight =
        if window.fullscreen or placement.maximized:
          constrainedExtent(
            geometry.height, surface.minHeight, surface.maxHeight, surface.exactHeight
          )
        else:
          placement.requestedHeight
      projection.placements.add(
        ProjectionPlacement(
          surfaceIndex: surface.surfaceIndex,
          surfaceGeneration: surface.surfaceGeneration,
          stateGeneration: surface.stateGeneration,
          x: geometry.x,
          y: geometry.y,
          width: geometry.width,
          height: geometry.height,
          requestedWidth: requestedWidth,
          requestedHeight: requestedHeight,
          transform: 1,
          presentationBits: presentationBits,
        )
      )
    let viewId = adapter.model.outputs[logical.output].activeView
    for windowId in adapter.model.windowOrder:
      let window = adapter.model.windows[windowId]
      if window.homeOutput != logical.output or not window.minimized or
          not adapter.model.windowTagIds(windowId).intersects(
            adapter.model.viewTagIds(viewId)
          ):
        continue
      let surface = adapter.surfaceFacts[windowId]
      let geometry = outputSnapshot.bounds()
      projection.placements.add(
        ProjectionPlacement(
          surfaceIndex: surface.surfaceIndex,
          surfaceGeneration: surface.surfaceGeneration,
          stateGeneration: surface.stateGeneration,
          x: geometry.x,
          y: geometry.y,
          width: geometry.width,
          height: geometry.height,
          requestedWidth: constrainedExtent(
            geometry.width, surface.minWidth, surface.maxWidth, surface.exactWidth
          ),
          requestedHeight: constrainedExtent(
            geometry.height, surface.minHeight, surface.maxHeight, surface.exactHeight
          ),
          transform: 1,
          presentationBits: 1'u16 shl 2,
        )
      )
      adapter.presentedMaximized[windowId] = false
      inc projection.output.placementCount
    var fullscreen = false
    for placement in projection.placements:
      if (placement.presentationBits and 1) != 0:
        fullscreen = true
    if not fullscreen:
      for group in logical.tabGroups:
        var wire = ProjectionTabGroup(
          output: rawOutput,
          group: group.id,
          x: group.geometry.x,
          y: group.geometry.y,
          width: group.geometry.width,
          height: group.geometry.height,
          focused: group.focused,
        )
        for member in group.members:
          let facts = adapter.surfaceFacts[member]
          wire.members.add(
            ProjectionTabMember(
              surfaceIndex: facts.surfaceIndex,
              surfaceGeneration: facts.surfaceGeneration,
            )
          )
          if member == group.selected:
            wire.selectedIndex = facts.surfaceIndex
            wire.selectedGeneration = facts.surfaceGeneration
        result.tabGroups.add(wire)
    result.outputs.add(projection)

    let outputState = adapter.model.outputs[logical.output]
    # Migrated views retained for a disconnected output affinity remain model
    # state, not extra public profile slots on the fallback output.
    for index in 0 ..< min(outputState.views.len, 9):
      let viewId = outputState.views[index]
      var stateBits = 0'u16
      if viewId == outputState.activeView:
        stateBits = stateBits or (1'u16 shl 0)
      for windowId in adapter.model.windowOrder:
        let window = adapter.model.windows[windowId]
        if window.homeOutput == logical.output and
            adapter.model.windowTagIds(windowId).intersects(
              adapter.model.viewTagIds(viewId)
            ):
          stateBits = stateBits or (1'u16 shl 2)
          break
      for otherOutputId in adapter.model.outputOrder:
        if otherOutputId == logical.output:
          continue
        let other = adapter.model.outputs[otherOutputId]
        if adapter.model.viewTagIds(other.activeView).intersects(
          adapter.model.viewTagIds(viewId)
        ):
          stateBits = stateBits or (1'u16 shl 3)
          break
      # A configured workspace name labels the indicator; the slot number is
      # the fallback and stays the wire identity either way — a name is not
      # an identity.
      var number = index + 1
      if adapter.model.settings.workspaceAssignments.len > 0:
        let tags = adapter.model.viewTagIds(viewId)
        if tags.len != 1:
          fail("assigned workspace indicator is ambiguous")
        number = int(adapter.model.tags[tags[0]].slot)
      var labelText = $number
      for tagId in adapter.model.viewTagIds(viewId):
        if adapter.model.tags[tagId].name.len > 0:
          labelText = adapter.model.tags[tagId].name
          break
      if labelText.len > indicatorLabelLen:
        labelText.setLen(indicatorLabelLen)
      var indicator = ProjectionIndicator(
        output: rawOutput,
        slot: uint32(index),
        indicator: uint64(uint32(viewId)),
        action: (if number in 1 .. 9: number.activateViewAction().raw()
        else: 0),
        stateBits: stateBits,
        labelLen: uint16(labelText.len),
      )
      for labelIndex, character in labelText:
        indicator.label[labelIndex] = byte(character)
      result.indicators.add(indicator)

    let layoutText =
      case adapter.model.views[outputState.activeView].layout
      of LayoutMode.scroller: "Scroller"
      of LayoutMode.tile: "Tile"
      of LayoutMode.grid: "Grid"
      of LayoutMode.monocle: "Monocle"
      of LayoutMode.verticalScroller: "Vertical Scroller"
      of LayoutMode.centerTile: "Center Tile"
      of LayoutMode.rightTile: "Right Tile"
      of LayoutMode.verticalGrid: "Vertical Grid"
      of LayoutMode.deck: "Deck"
      of LayoutMode.spiral: "Spiral"
      of LayoutMode.tgmix: "Mixed"
      of LayoutMode.frameTree: "Frames"
      of LayoutMode.notion: "Notion"
      of LayoutMode.splitTree: "i3"
      of LayoutMode.dwindle: "Dwindle"
    var status = ProjectionOutputStatus(
      output: rawOutput,
      focusBits: (if outputState.focusedWindow != nullWindowId: 1'u16 else: 0'u16),
      layoutLen: uint16(layoutText.len),
    )
    for index, character in layoutText:
      status.layout[index] = byte(character)
    result.outputStatuses.add(status)

  result.activeOutput = adapter.logicalToOutput[adapter.model.activeOutput].output
