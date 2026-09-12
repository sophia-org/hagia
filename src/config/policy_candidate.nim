import std/[algorithm, sequtils, strutils]

import kdl

import ../types/[config_values, core, model]
import ./migration_common
import ../state/values
import ./profile

proc integerValue(value: ProfileValue): int =
  let node = parseKdl(value.encoded)[0]
  if node.args.len != 1:
    raise newException(DesktopProfileError, value.key & " requires one integer")
  try:
    node.args[0].get(int)
  except CatchableError:
    raise newException(DesktopProfileError, value.key & " requires one integer")

proc int32Value(value: ProfileValue): int32 =
  let parsed = value.integerValue()
  if parsed < int(low(int32)) or parsed > int(high(int32)):
    raise newException(DesktopProfileError, value.key & " exceeds 32-bit bounds")
  int32(parsed)

proc layoutMode(name: string): LayoutMode =
  case name
  of "scroller":
    LayoutMode.scroller
  of "tile":
    LayoutMode.tile
  of "grid":
    LayoutMode.grid
  of "monocle":
    LayoutMode.monocle
  of "center-tile":
    LayoutMode.centerTile
  of "right-tile":
    LayoutMode.rightTile
  of "vertical-grid":
    LayoutMode.verticalGrid
  of "deck":
    LayoutMode.deck
  of "spiral":
    LayoutMode.spiral
  of "frame-tree":
    LayoutMode.frameTree
  of "notion":
    LayoutMode.notion
  of "i3", "split-tree":
    LayoutMode.splitTree
  of "dwindle":
    LayoutMode.dwindle
  of "tgmix":
    LayoutMode.tgmix
  of "vertical-scroller":
    LayoutMode.verticalScroller
  else:
    raise newException(DesktopProfileError, "unsupported Hagia policy layout")

proc layoutValue(value: ProfileValue): LayoutMode =
  let node = parseKdl(value.encoded)[0]
  if node.args.len != 1 or node.args[0].kind != KString:
    raise newException(DesktopProfileError, value.key & " requires one layout name")
  node.args[0].kString().layoutMode()

proc layoutCycleValue(value: ProfileValue): seq[LayoutMode] =
  let node = parseKdl(value.encoded)[0]
  if node.args.len == 0 or node.args.len > ord(high(LayoutMode)) + 1:
    raise newException(DesktopProfileError, "policy layout-cycle is invalid")
  for argument in node.args:
    if argument.kind != KString:
      raise newException(DesktopProfileError, "policy layout-cycle is invalid")
    let layout = argument.kString().layoutMode()
    if layout in result:
      raise newException(DesktopProfileError, "policy layout-cycle has duplicates")
    result.add(layout)

proc extentValue(node: KdlNode): LayoutExtent =
  ## One `{ proportion N }` or `{ fixed N }` child as an extent. The grammar
  ## is checked before this runs, so the shape here is known good.
  let child = node.children[0]
  if child.name == "fixed":
    return fixedExtent(int32(child.args[0].kInt()))
  var value: float64
  discard child.args[0].number(value)
  proportionExtent(scaleFromProportion(value))

proc extentListValue(node: KdlNode): seq[LayoutExtent] =
  for child in node.children:
    var one = node
    one.children = @[child]
    result.add(one.extentValue())

proc policyCandidateSettings*(candidate: AuthorityCandidate): PolicySettings =
  ## The settings a policy fragment states, with no model to put them in.
  ## Negotiation needs one of these values before any model exists, and a
  ## second parser for that one value would be a second owner of the grammar.
  if candidate.authority != ProfileAuthority.policy or candidate.generation == 0 or
      candidate.digest.len != 64 or not candidate.digest.allCharsInSet(HexDigits):
    raise newException(DesktopProfileError, "Hagia received a non-policy candidate")
  var settings = defaultPolicySettings
  var defaultLayout = LayoutMode.scroller
  var legacyGaps = false
  var hasStruts = false
  for value in candidate.values:
    case value.key
    of "policy.layout":
      defaultLayout = value.layoutValue()
    of "policy.layout-cycle":
      settings.layoutCycle = value.layoutCycleValue()
    of "policy.view-count":
      settings.viewCount = value.integerValue()
      if settings.viewCount < 1 or settings.viewCount > 9:
        raise newException(DesktopProfileError, "policy view-count is outside 1..9")
    of "policy.outer-gap":
      legacyGaps = true
      settings.outerGap = value.int32Value()
    of "policy.inner-gap":
      legacyGaps = true
      settings.innerGap = value.int32Value()
    of "policy.gaps":
      let node = parseKdl(value.encoded)[0]
      node.validateGapSetting()
      settings.gapModel = GapModel.uniform
      settings.gaps = value.int32Value()
    of "policy.struts":
      let node = parseKdl(value.encoded)[0]
      node.validateGapSetting()
      hasStruts = true
      for edge in node.children:
        let amount = int32(edge.args[0].get(int))
        case edge.name
        of "left":
          settings.struts.left = amount
        of "right":
          settings.struts.right = amount
        of "top":
          settings.struts.top = amount
        of "bottom":
          settings.struts.bottom = amount
        else:
          discard # The shared grammar rejected unknown edges above.
    of "policy.viewport-offset":
      settings.viewportOffset = value.int32Value()
    of "policy.master-count":
      settings.masterCount = value.integerValue()
      if settings.masterCount < 1 or settings.masterCount > maxMasterCount:
        raise newException(
          DesktopProfileError, "policy master-count is outside 1.." & $maxMasterCount
        )
    of "policy.master-ratio":
      # Written as a percentage, because a profile is read by people and a
      # fixed-point scale is not.
      let percent = value.integerValue()
      if percent < 10 or percent > 90:
        raise newException(DesktopProfileError, "policy master-ratio is outside 10..90")
      settings.masterRatio = scaleFromRatio(uint32(percent), 100)
    of "policy.default-column-width":
      # What a column gets when it has never been given a width, which a
      # scroller needs: column widths no longer follow from how many columns
      # there are.
      let node = parseKdl(value.encoded)[0]
      node.validateExtentSetting(1)
      settings.defaultColumnWidth = node.extentValue()
    of "policy.default-row-height":
      # The vertical scroller's along-axis default. Unset inherits
      # default-column-width, so a profile that never mentions rows behaves
      # as it always has.
      let node = parseKdl(value.encoded)[0]
      node.validateExtentSetting(1)
      settings.defaultRowHeight = node.extentValue()
    of "policy.preset-row-heights":
      let node = parseKdl(value.encoded)[0]
      node.validateExtentSetting(maxSizePresets)
      settings.presetRowHeights = node.extentListValue()
    of "policy.always-center-single-column":
      let node = parseKdl(value.encoded)[0]
      if node.args.len != 1 or node.args[0].kind != KBool:
        raise newException(DesktopProfileError, value.key & " requires #true or #false")
      settings.alwaysCenterSingleColumn = node.args[0].kBool()
    of "policy.focus-follows-mouse":
      let node = parseKdl(value.encoded)[0]
      if node.args.len != 1 or node.args[0].kind != KBool:
        raise newException(DesktopProfileError, value.key & " requires #true or #false")
      settings.focusFollowsMouse = node.args[0].kBool()
    of "policy.center-focused-column":
      let node = parseKdl(value.encoded)[0]
      if node.args.len != 1 or node.args[0].kind != KString:
        raise
          newException(DesktopProfileError, value.key & " requires one centring mode")
      let mode = node.args[0].kString()
      settings.centerFocusedColumn =
        case mode
        of "never":
          CenterFocusedColumn.never
        of "always":
          CenterFocusedColumn.always
        of "on-overflow":
          CenterFocusedColumn.onOverflow
        else:
          raise newException(
            DesktopProfileError,
            "policy center-focused-column expects never, always, or on-overflow",
          )
    of "policy.preset-column-widths":
      let node = parseKdl(value.encoded)[0]
      node.validateExtentSetting(maxSizePresets)
      settings.presetColumnWidths = node.extentListValue()
    of "policy.scratchpad-size":
      let node = parseKdl(value.encoded)[0]
      settings.scratchpadWidthPercent = int32(node.args[0].get(int))
      settings.scratchpadHeightPercent = int32(node.args[1].get(int))
    of "policy.floating-size":
      let node = parseKdl(value.encoded)[0]
      settings.floatingWidthPercent = int32(node.args[0].get(int))
      settings.floatingHeightPercent = int32(node.args[1].get(int))
    of "policy.gap-step":
      settings.gapStep = value.int32Value()
      if settings.gapStep < 1 or settings.gapStep > maxGap:
        raise
          newException(DesktopProfileError, "policy gap-step is outside 1.." & $maxGap)
    else:
      if value.key.startsWith("policy.view-name."):
        let node = parseKdl(value.encoded)[0]
        settings.viewNames.add(
          ViewSlotName(slot: node.args[0].get(int), name: node.args[1].get(string))
        )
      elif value.key.startsWith("policy.view-layout."):
        let node = parseKdl(value.encoded)[0]
        settings.viewLayouts.add(
          ViewSlotLayout(
            slot: node.args[0].get(int), layout: node.args[1].get(string).layoutMode()
          )
        )
      else:
        raise newException(DesktopProfileError, "unknown Hagia policy candidate value")
  if legacyGaps and settings.gapModel == GapModel.uniform:
    raise newException(
      DesktopProfileError, "policy gaps cannot mix with outer-gap or inner-gap"
    )
  if hasStruts and settings.gapModel != GapModel.uniform:
    raise newException(DesktopProfileError, "policy struts requires gaps")
  if settings.outerGap > maxGap or settings.innerGap > maxGap:
    raise newException(DesktopProfileError, "policy gaps exceed their bound")
  if settings.outerGap < 0 or settings.innerGap < 0 or settings.viewportOffset < 0:
    raise
      newException(DesktopProfileError, "policy geometry settings must be nonnegative")
  settings.layoutCycle.keepItIf(it != defaultLayout)
  settings.layoutCycle.insert(defaultLayout, 0)
  settings.viewNames.sort(
    proc(left, right: ViewSlotName): int =
      cmp(left.slot, right.slot)
  )
  settings.viewLayouts.sort(
    proc(left, right: ViewSlotLayout): int =
      cmp(left.slot, right.slot)
  )
  settings

proc applyPolicyCandidate*(model: var PolicyModel, candidate: AuthorityCandidate) =
  model.settings = candidate.policyCandidateSettings()
