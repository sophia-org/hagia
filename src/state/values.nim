import ../types/core

## Pure value helpers over passive types. Nothing here reads or writes a
## `PolicyModel`; these are the arithmetic and predicates the layers above
## share. The error every layer raises lives here too, because `fail` is the
## shared refusal and an error type belongs with the code that raises it.

type PolicyStateError* = object of CatchableError

proc fail*(message: string) {.noreturn.} =
  raise newException(PolicyStateError, message)

proc tagForSlot*(slot: uint32): TagMask =
  if slot == 0 or slot > maxTagBits:
    fail("tag slot is outside Hagia's bounded mask")
  TagMask(1'u64 shl (slot - 1))

proc scaledExtent*(base: int32, scale: Scale): int32 =
  ## How much of `base` a scale asks for, saturating rather than wrapping.
  if base <= 0:
    return 0
  let scaled = int64(base) * int64(uint32(scale)) div int64(uint32(scaleOne))
  if scaled > int64(high(int32)):
    return high(int32)
  int32(scaled)

proc scaleFromRatio*(numerator, denominator: uint32): Scale =
  if denominator == 0:
    fail("scale denominator must be nonzero")
  let raw = uint64(numerator) * uint64(uint32(scaleOne)) div uint64(denominator)
  if raw < uint64(uint32(minimumScale)):
    return minimumScale
  if raw > uint64(high(uint32)):
    return Scale(high(uint32))
  Scale(uint32(raw))

proc intersects*(left, right: TagMask): bool =
  (uint64(left) and uint64(right)) != 0

proc union*(left, right: TagMask): TagMask =
  TagMask(uint64(left) or uint64(right))

proc intersects*(left, right: openArray[TagId]): bool =
  for leftTag in left:
    if leftTag in right:
      return true
  false

proc unionTags*(left, right: openArray[TagId]): seq[TagId] =
  result = @left
  for tag in right:
    if tag notin result:
      result.add(tag)

proc contains*(bounds, geometry: Rect): bool =
  geometry.width > 0 and geometry.height > 0 and geometry.x >= bounds.x and
    geometry.y >= bounds.y and
    int64(geometry.x) + int64(geometry.width) <= int64(bounds.x) + int64(bounds.width) and
    int64(geometry.y) + int64(geometry.height) <= int64(bounds.y) + int64(bounds.height)

proc centeredGeometry*(
    bounds: Rect, constraints: SizeConstraints, desiredWidth, desiredHeight: int32
): Rect =
  var width = max(1'i32, min(bounds.width, desiredWidth))
  var height = max(1'i32, min(bounds.height, desiredHeight))
  if constraints.minWidth > 0:
    width = max(width, constraints.minWidth)
  if constraints.maxWidth > 0:
    width = min(width, constraints.maxWidth)
  if constraints.minHeight > 0:
    height = max(height, constraints.minHeight)
  if constraints.maxHeight > 0:
    height = min(height, constraints.maxHeight)
  width = min(width, bounds.width)
  height = min(height, bounds.height)
  Rect(
    x: bounds.x + (bounds.width - width) div 2,
    y: bounds.y + (bounds.height - height) div 2,
    width: width,
    height: height,
  )

proc wrappedIndex*(current, delta, length: int): int =
  if length <= 0:
    fail("cannot wrap an empty policy sequence")
  ((current + delta) mod length + length) mod length

proc adjustedScale*(current: Scale, delta: int, whenAutomatic: Scale): Scale =
  ## Step a width one notch. `whenAutomatic` is what a column that never chose
  ## a width is currently showing, so the first step moves from what is on
  ## screen. Reading `autoScale` as 1.0 instead made one press jump a
  ## half-width column past the whole viewport.
  let base =
    if current == autoScale:
      uint64(uint32(whenAutomatic))
    else:
      uint64(uint32(current))
  let step = uint64(uint32(scaleOne)) div 20
  if delta > 0:
    return Scale(uint32(min(uint64(uint32(maximumScale)), base + step * uint64(delta))))
  let reduction = step * uint64(-delta)
  let reduced =
    if reduction >= base:
      0'u64
    else:
      base - reduction
  Scale(uint32(max(uint64(uint32(minimumScale)), reduced)))
