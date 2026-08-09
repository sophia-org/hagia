import kdl

import ../policy/types
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

proc applyPolicyCandidate*(model: var PolicyModel, candidate: AuthorityCandidate) =
  if candidate.authority != ProfileAuthority.policy:
    raise newException(DesktopProfileError, "Hagia received a non-policy candidate")
  var settings = defaultPolicySettings
  for value in candidate.values:
    case value.key
    of "policy.layout":
      discard # profile validation has already restricted this to scroller.
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
  model.settings = settings
