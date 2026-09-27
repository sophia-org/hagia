import ../../../../src/types/core
import ../../../../src/types/wm_presentation
import ./wm_v1
import ../../../../src/sophia/wm_presentation

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
