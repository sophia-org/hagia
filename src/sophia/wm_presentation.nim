import std/sets
import std/tables

import ../types/core
import ../types/wm_presentation
import ./policy_transport

proc validRect(rect: Rect): bool =
  rect.width > 0 and rect.height > 0 and
    int64(rect.x) + int64(rect.width) <= int64(high(int32)) and
    int64(rect.y) + int64(rect.height) <= int64(high(int32))

proc contains(outer, inner: Rect): bool =
  inner.x >= outer.x and inner.y >= outer.y and
    int64(inner.x) + int64(inner.width) <= int64(outer.x) + int64(outer.width) and
    int64(inner.y) + int64(inner.height) <= int64(outer.y) + int64(outer.height)

proc overlaps(left, right: Rect): bool =
  int64(left.x) < int64(right.x) + int64(right.width) and
    int64(right.x) < int64(left.x) + int64(left.width) and
    int64(left.y) < int64(right.y) + int64(right.height) and
    int64(right.y) < int64(left.y) + int64(left.height)

proc validatePresentation*(presentation: WmPresentation) =
  if presentation.generation == 0 or
      presentation.outputs.len notin 1 .. maxPresentationOutputs or
      presentation.instances.len > maxSurfaceInstances or
      presentation.regions.len > maxPresentationRegions or
      presentation.bindings.len > maxPresentationBindings:
    fail("presentation identity or count is invalid")
  var outputs = initTable[uint64, PresentationOutput]()
  for output in presentation.outputs:
    if output.output == 0 or output.generation == 0 or not output.coverage.validRect() or
        output.output in outputs:
      fail("presentation output is invalid")
    outputs[output.output] = output
  var ids = initHashSet[uint64]()
  var orders = initHashSet[(uint64, uint16)]()
  for index in 0 ..< presentation.instances.len + presentation.regions.len:
    let (id, generation, output, geometry, clip, zIndex) =
      if index < presentation.instances.len:
        let item = presentation.instances[index]
        if item.sourceGeneration == 0 or item.sourceIndex == high(uint32) or
            item.opacityMillis notin 1'u16 .. 1000'u16:
          fail("presentation source or opacity is invalid")
        (
          item.id, item.generation, item.output, item.destination, item.clip,
          item.zIndex,
        )
      else:
        let item = presentation.regions[index - presentation.instances.len]
        (item.id, item.generation, item.output, item.geometry, item.clip, item.zIndex)
    let coverage = outputs.getOrDefault(output).coverage
    if id == 0 or generation == 0 or id in ids or (output, zIndex) in orders or
        not geometry.validRect() or not clip.validRect() or not coverage.contains(clip) or
        not geometry.overlaps(clip):
      fail("presentation target is invalid")
    ids.incl(id)
    orders.incl((output, zIndex))
  for output in presentation.outputs:
    if output.mode == PresentationMode.replaceApplications:
      var backdrop = false
      for region in presentation.regions:
        if region.output == output.output and
            region.role == PresentationRegionRole.backdrop and
            region.geometry == output.coverage and region.clip == output.coverage and
            region.zIndex == 0 and region.action == 0:
          backdrop = true
      if not backdrop:
        fail("replacement presentation has no full backdrop")
    if presentation.keyboardOutput != 0 and
        output.mode != PresentationMode.replaceApplications:
      fail("modal presentation must replace applications")
  if presentation.keyboardOutput == 0:
    if presentation.bindings.len != 0:
      fail("presentation bindings require a modal scope")
  elif presentation.keyboardOutput notin outputs or presentation.bindings.len == 0:
    fail("presentation keyboard output is invalid")
  var chords = initHashSet[(uint32, uint32)]()
  for binding in presentation.bindings:
    if binding.action == 0 or binding.keycode notin 1'u32 .. 0x2ff'u32 or
        (binding.modifiers and not 15'u32) != 0 or
        (binding.keycode, binding.modifiers) in chords or
        (binding.keycode == 14 and (binding.modifiers and 6) == 6):
      fail("presentation binding is invalid or reserved")
    chords.incl((binding.keycode, binding.modifiers))
