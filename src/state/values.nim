import std/math

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

proc scaleFromProportion*(value: float): Scale =
  ## A profile proportion as Q16.16, truncating exactly as `scaleFromRatio`
  ## does, so `proportion 0.33` and the percent `33` it replaces resolve to the
  ## same column. Saturates at the bounds; refusing an out-of-range value is
  ## the profile layer's job, because only it can say where it came from.
  if classify(value) notin {fcNormal, fcSubnormal, fcZero}:
    fail("layout proportion is not a finite number")
  let raw = value * float(uint32(scaleOne))
  if raw <= float(uint32(minimumScale)):
    return minimumScale
  if raw >= float(uint32(maximumScale)):
    return maximumScale
  Scale(uint32(raw))

proc proportionExtent*(scale: Scale): LayoutExtent =
  ## A proportion stated as an extent. Built by hand this reads as three facts
  ## where it is one, and the kind and the populated field have to agree.
  LayoutExtent(kind: LayoutExtentKind.proportion, scale: scale)

proc fixedExtent*(pixels: int32): LayoutExtent =
  ## Logical pixels stated as an extent.
  LayoutExtent(kind: LayoutExtentKind.fixed, pixels: pixels)

proc extentPixels*(extent: LayoutExtent, proportionBase, gap: int32): int32 =
  ## What an extent asks for, in pixels. A proportion is of the room a column
  ## can occupy less the gap it carries; niri computes the same way. A fixed
  ## extent is already a size and takes neither the base nor the gap, which is
  ## the whole of what makes it fixed.
  ##
  ## `automatic` is a caller error: it means a column that never chose a width
  ## reached the arithmetic without the configured default being substituted.
  case extent.kind
  of LayoutExtentKind.automatic:
    fail("layout extent was never resolved against a configured default")
  of LayoutExtentKind.proportion:
    max(1'i32, proportionBase.scaledExtent(extent.scale) - gap)
  of LayoutExtentKind.fixed:
    max(1'i32, extent.pixels)

proc isBoundedExtent*(extent: LayoutExtent): bool =
  ## Whether an extent is one the layout can use. `automatic` always is: it
  ## means the configured default stands in. A proportion is bounded because a
  ## width is a preference rather than a licence to put every other column out
  ## of reach; a fixed extent is bounded because the strip coordinates have to
  ## stay inside the int32 the wire carries.
  case extent.kind
  of LayoutExtentKind.automatic:
    true
  of LayoutExtentKind.proportion:
    uint32(extent.scale) >= uint32(minimumScale) and
      uint32(extent.scale) <= uint32(maximumScale)
  of LayoutExtentKind.fixed:
    extent.pixels >= 1 and extent.pixels <= maxFixedExtent

proc scaleForWidth*(proportionBase, gap, width: int32): Scale =
  ## The proportion that produces this width: the inverse of `extentPixels`,
  ## and the one owner of that arithmetic. It was open-coded where a column
  ## expands into its neighbours' space, and stepping a fixed column needs it
  ## too, because a step is proportional and has to start somewhere.
  let base = max(1'i32, proportionBase)
  let raw = (int64(width) + int64(gap)) * int64(uint32(scaleOne)) div int64(base)
  Scale(uint32(max(int64(uint32(minimumScale)), min(int64(uint32(maximumScale)), raw))))

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
