import std/[sequtils, strutils]

import kdl

import ../types/model
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

proc applyPolicyCandidate*(model: var PolicyModel, candidate: AuthorityCandidate) =
  if candidate.authority != ProfileAuthority.policy or candidate.generation == 0 or
      candidate.digest.len != 64 or not candidate.digest.allCharsInSet(HexDigits):
    raise newException(DesktopProfileError, "Hagia received a non-policy candidate")
  var settings = defaultPolicySettings
  var defaultLayout = LayoutMode.scroller
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
      settings.outerGap = value.int32Value()
    of "policy.inner-gap":
      settings.innerGap = value.int32Value()
    of "policy.viewport-offset":
      settings.viewportOffset = value.int32Value()
    else:
      raise newException(DesktopProfileError, "unknown Hagia policy candidate value")
  if settings.outerGap < 0 or settings.innerGap < 0 or settings.viewportOffset < 0:
    raise
      newException(DesktopProfileError, "policy geometry settings must be nonnegative")
  settings.layoutCycle.keepItIf(it != defaultLayout)
  settings.layoutCycle.insert(defaultLayout, 0)
  model.settings = settings
