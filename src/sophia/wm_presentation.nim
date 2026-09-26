import std/[sets, tables]

import ../types/[core, wm_v1, wm_presentation]
import ./[policy_semantics, policy_transport, wm_v1]

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

proc addRect(data: var seq[byte], rect: Rect) =
  for value in [rect.x, rect.y, rect.width, rect.height]:
    data.addU32(cast[uint32](value))

proc encodePresentation*(presentation: WmPresentation): PresentationRecords =
  presentation.validatePresentation()
  result[0].addU64(presentation.generation)
  result[0].addU64(presentation.keyboardOutput)
  result[0].addU16(uint16(presentation.outputs.len))
  result[0].addU16(uint16(presentation.bindings.len))
  result[0].addU32(uint32(presentation.instances.len))
  result[0].addU32(uint32(presentation.regions.len))
  result[0].addU32(0)
  for output in presentation.outputs:
    result[1].addU64(output.output)
    result[1].addU64(output.generation)
    result[1].addRect(output.coverage)
    result[1].addU16(uint16(output.mode))
    result[1].addU16(0)
    result[1].addU32(0)
  for instance in presentation.instances:
    result[2].addU64(instance.id)
    result[2].addU64(instance.generation)
    result[2].addU64(instance.output)
    result[2].addU32(instance.sourceIndex)
    result[2].addU32(instance.sourceGeneration)
    result[2].addRect(instance.destination)
    result[2].addRect(instance.clip)
    result[2].addU16(instance.opacityMillis)
    result[2].addU16(instance.zIndex)
    result[2].addU32(0)
    result[2].addU64(instance.action)
  for region in presentation.regions:
    result[3].addU64(region.id)
    result[3].addU64(region.generation)
    result[3].addU64(region.output)
    result[3].addRect(region.geometry)
    result[3].addRect(region.clip)
    result[3].addU16(region.zIndex)
    result[3].addU16(uint16(region.role))
    result[3].addU32(0)
    result[3].addU64(region.action)
  for binding in presentation.bindings:
    result[4].addU64(binding.action)
    result[4].addU32(binding.keycode)
    result[4].addU32(binding.modifiers)

proc decodePresentationReceipt*(
    frame: Frame, epoch, capabilities: uint64
): PresentationReceipt =
  if frame.kind != MessageKind.presentationOutcome or frame.payload.len != 44 or
      (capabilities and capabilitySurfaceInstances) == 0:
    fail("presentation receipt was not negotiated or is malformed")
  let outcome = frame.payload.u16At(40)
  result = PresentationReceipt(
    connectionEpoch: frame.payload.u64At(0),
    publicationGeneration: frame.payload.u64At(8),
    output: frame.payload.u64At(16),
    outputGeneration: frame.payload.u64At(24),
    presentationEpoch: frame.payload.u64At(32),
  )
  if result.connectionEpoch != epoch or epoch == 0 or not validReceiptIdentity(result) or
      outcome notin 1'u16 .. 3'u16 or frame.payload.u16At(42) != 0:
    fail("presentation receipt identity is invalid")
  result.outcome = PresentationOutcomeKind(outcome)
