import std/options
import std/sets
import std/unicode
import ../types/session
import ../types/wm_v1
import ../types/wm_presentation
import ./policy_semantics
import ./policy_transport
import ./policy_codec
import ./wm_presentation

## Hagia policy-value checks before handing a candidate to the C SDK.
## Wire encoding, framing, negotiation and custody belong to the SDK.
proc requireCount(count, maximum: int) =
  if count > maximum:
    fail("projection row count exceeds its bound")

proc has(selected, capability: uint64): bool =
  (selected and capability) == capability

proc requireCapabilities(selected, required: uint64) =
  if (selected and required) != required:
    fail("projection needs unnegotiated capabilities")

proc validateLabel(label: array[indicatorLabelLen, byte], length: uint16) =
  if length == 0 or length > indicatorLabelLen:
    fail("projection label length is invalid")
  var text = newString(int(length))
  for index, value in label:
    if index < int(length):
      text[index] = char(value)
    elif value != 0:
      fail("projection label padding is nonzero")
  if text.validateUtf8() != -1:
    fail("projection label is not UTF-8")
  for rune in text.runes:
    if int32(rune) in 0'i32 .. 31'i32 or int32(rune) in 127'i32 .. 159'i32:
      fail("projection label has a control character")

proc validateProjectionRows*(
    projection: PolicyProjection, request: ProjectionRequest, selected: uint64
) =
  if not request.affectedOutputs.validAffectedOutputs() or
      projection.outputs.len != request.affectedOutputs.len:
    fail("projection output coverage is invalid")
  var seen = initHashSet[uint64]()
  var placements = 0
  for output in projection.outputs:
    if output.output.output notin request.affectedOutputs or
        seen.containsOrIncl(output.output.output) or
        not validOptionalSurface(
          output.output.focusIndex, output.output.focusGeneration
        ):
      fail("projection output identity is invalid")
    output.placements.len.requireCount(maxSurfaces - placements)
    if output.output.placementCount != uint32(output.placements.len):
      fail("projection placement partition is invalid")
    placements += output.placements.len
    for placement in output.placements:
      if not validSurface(placement.surfaceIndex, placement.surfaceGeneration) or
          placement.stateGeneration == 0:
        fail("projection placement identity is invalid")
      if placement.transform != 1 or (placement.presentationBits and not 7'u16) != 0:
        fail("projection placement transform or state is invalid")
      if not (
        (placement.requestedWidth == 0 and placement.requestedHeight == 0) or
        (placement.requestedWidth > 0 and placement.requestedHeight > 0)
      ):
        fail("projection requested size is invalid")
      if placement.cropWidth == 0 and placement.cropHeight == 0:
        if placement.cropX != 0 or placement.cropY != 0:
          fail("absent projection crop has a position")
      elif placement.cropWidth <= 0 or placement.cropHeight <= 0:
        fail("projection crop is invalid")
  projection.indicators.len.requireCount(maxIndicators)
  projection.outputStatuses.len.requireCount(maxOutputs)
  if projection.indicators.len != 0 or projection.outputStatuses.len != 0:
    selected.requireCapabilities(capabilityIndicators)
  for indicator in projection.indicators:
    indicator.label.validateLabel(indicator.labelLen)
  for status in projection.outputStatuses:
    status.layout.validateLabel(status.layoutLen)
  if projection.tabGroups.len != 0:
    selected.requireCapabilities(capabilityTabGroups)
    projection.tabGroups.len.requireCount(maxTabGroups)
    var members = 0
    for group in projection.tabGroups:
      group.members.len.requireCount(maxTabMembers - members)
      members += group.members.len
      if not validOptionalSurface(group.selectedIndex, group.selectedGeneration):
        fail("tab selection identity is invalid")
      for member in group.members:
        if not validSurface(member.surfaceIndex, member.surfaceGeneration):
          fail("tab member identity is invalid")
  if selected.has(capabilityTranslationGroups):
    projection.translationGroups.len.requireCount(maxOutputs)
    var members = 0
    for group in projection.translationGroups:
      group.members.len.requireCount(maxSurfaces - members)
      members += group.members.len
      if group.output == 0 or group.group == 0 or group.members.len == 0:
        fail("translation group is empty or invalid")
      for member in group.members:
        if not validSurface(member.surfaceIndex, member.surfaceGeneration):
          fail("translation member identity is invalid")
  if selected.has(capabilityLaunchOrigin):
    try:
      projection.launchContexts.validateLaunchOrigins(request.connectionEpoch)
    except PolicyClientError:
      fail(getCurrentExceptionMsg())
  if selected.has(capabilityLaunchOrigin or capabilityOutputLaunchContext):
    projection.outputLaunchContexts.len.requireCount(maxOutputs)
    var outputs = initHashSet[uint64]()
    for context in projection.outputLaunchContexts:
      if context.output == 0 or context.generation == 0 or context.token == 0 or
          context.epoch != request.connectionEpoch or
          outputs.containsOrIncl(context.output):
        fail("output launch context is invalid")
  if projection.presentation.isSome:
    let presentation = projection.presentation.get()
    selected.requireCapabilities(capabilitySurfaceInstances)
    try:
      presentation.validatePresentation()
    except PolicyClientError:
      fail(getCurrentExceptionMsg())
    var actions = presentation.bindings.len != 0
    for instance in presentation.instances:
      actions = actions or instance.action != 0
    for region in presentation.regions:
      actions = actions or region.action != 0
    if actions:
      selected.requireCapabilities(capabilityActions or capabilityPresentationActions)
