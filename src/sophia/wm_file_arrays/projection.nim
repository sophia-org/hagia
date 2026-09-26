import std/[options, sets, unicode]

import ../../types/[session, wm_v1, wm_files, wm_file_arrays, wm_presentation]
import ../[wm_files, wm_file_payload, policy_semantics, policy_transport]
import ../[wm_tab_groups, wm_translation, wm_presentation]
from ../wm_v1 import
  encodeProjectionOutput, encodeProjectionPlacement, encodeProjectionIndicator,
  encodeProjectionOutputStatus, encodeLaunchOriginRecord, encodeOutputLaunchContext
from ../policy_codec import validateLaunchOrigins

## Complete candidate rows, independent of legacy chunking and ordinals.
## Optional motion/launch hints retain the existing client's omission rule.
## Scene membership, final authority and settlement remain Sophia's decision.
## Candidate construction refuses invalid placement handles/state generations
## earlier than Sophia's row codec, whose Engine owner also rejects them.

proc requireCount(count, maximum: int) =
  if count > maximum:
    failWmFile(WmFileErrorKind.value, "projection row count exceeds its bound")

proc rowWidth(kind: uint16): int =
  case kind
  of 1:
    projectionOutputSize
  of 2:
    projectionPlacementSize
  of 3:
    projectionIndicatorSize
  of 4:
    projectionOutputStatusSize
  of projectionTabGroupRecordKind:
    projectionTabGroupSize
  of projectionTabMemberRecordKind:
    projectionTabMemberSize
  of projectionTranslationGroupRecordKind:
    projectionTranslationGroupSize
  of projectionTranslationMemberRecordKind:
    projectionTranslationMemberSize
  of projectionLaunchContextRecordKind:
    launchOriginRecordSize
  of projectionOutputLaunchContextRecordKind:
    outputLaunchContextSize
  else:
    for index, recordKind in presentationRecordKinds:
      if kind == recordKind:
        return presentationRecordSizes[index]
    failWmFile(WmFileErrorKind.sections, "unknown projection section")

proc addSection(
    sections: var seq[WmFileSection], kind: uint16, count: int, rows: sink seq[byte]
) =
  if rows.len != count * kind.rowWidth():
    failWmFile(
      WmFileErrorKind.length, "projection row encoder returned the wrong width"
    )
  if count != 0:
    sections.add(WmFileSection(kind: kind, count: uint32(count), rows: rows))

proc has(selected, capability: uint64): bool =
  (selected and capability) == capability

proc validateLabel(label: array[indicatorLabelLen, byte], length: uint16) =
  if length == 0 or length > indicatorLabelLen:
    failWmFile(WmFileErrorKind.value, "projection label length is invalid")
  var text = newString(int(length))
  for index, value in label:
    if index < int(length):
      text[index] = char(value)
    elif value != 0:
      failWmFile(WmFileErrorKind.reserved, "projection label padding is nonzero")
  if text.validateUtf8() != -1:
    failWmFile(WmFileErrorKind.value, "projection label is not UTF-8")
  for rune in text.runes:
    if int32(rune) in 0'i32 .. 31'i32 or int32(rune) in 127'i32 .. 159'i32:
      failWmFile(WmFileErrorKind.value, "projection label has a control character")

proc validateProjectionRows(
    projection: PolicyProjection, request: ProjectionRequest, selected: uint64
) =
  if not request.affectedOutputs.validAffectedOutputs() or
      projection.outputs.len != request.affectedOutputs.len:
    failWmFile(WmFileErrorKind.value, "projection output coverage is invalid")
  var seen = initHashSet[uint64]()
  var placements = 0
  for output in projection.outputs:
    if output.output.output notin request.affectedOutputs or
        seen.containsOrIncl(output.output.output) or
        not validOptionalSurface(
          output.output.focusIndex, output.output.focusGeneration
        ):
      failWmFile(WmFileErrorKind.value, "projection output identity is invalid")
    output.placements.len.requireCount(maxSurfaces - placements)
    if output.output.placementCount != uint32(output.placements.len):
      failWmFile(WmFileErrorKind.value, "projection placement partition is invalid")
    placements += output.placements.len
    for placement in output.placements:
      if not validSurface(placement.surfaceIndex, placement.surfaceGeneration) or
          placement.stateGeneration == 0:
        failWmFile(WmFileErrorKind.value, "projection placement identity is invalid")
      if placement.transform != 1 or (placement.presentationBits and not 7'u16) != 0:
        failWmFile(
          WmFileErrorKind.value, "projection placement transform or state is invalid"
        )
      if not (
        (placement.requestedWidth == 0 and placement.requestedHeight == 0) or
        (placement.requestedWidth > 0 and placement.requestedHeight > 0)
      ):
        failWmFile(WmFileErrorKind.value, "projection requested size is invalid")
      if placement.cropWidth == 0 and placement.cropHeight == 0:
        if placement.cropX != 0 or placement.cropY != 0:
          failWmFile(WmFileErrorKind.value, "absent projection crop has a position")
      elif placement.cropWidth <= 0 or placement.cropHeight <= 0:
        failWmFile(WmFileErrorKind.value, "projection crop is invalid")
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
        failWmFile(WmFileErrorKind.value, "tab selection identity is invalid")
      for member in group.members:
        if not validSurface(member.surfaceIndex, member.surfaceGeneration):
          failWmFile(WmFileErrorKind.value, "tab member identity is invalid")
  if selected.has(capabilityTranslationGroups):
    projection.translationGroups.len.requireCount(maxOutputs)
    var members = 0
    for group in projection.translationGroups:
      group.members.len.requireCount(maxSurfaces - members)
      members += group.members.len
      if group.output == 0 or group.group == 0 or group.members.len == 0:
        failWmFile(WmFileErrorKind.value, "translation group is empty or invalid")
      for member in group.members:
        if not validSurface(member.surfaceIndex, member.surfaceGeneration):
          failWmFile(WmFileErrorKind.value, "translation member identity is invalid")
  if selected.has(capabilityLaunchOrigin):
    try:
      projection.launchContexts.validateLaunchOrigins(request.connectionEpoch)
    except PolicyClientError:
      failWmFile(WmFileErrorKind.value, getCurrentExceptionMsg())
  if selected.has(capabilityLaunchOrigin or capabilityOutputLaunchContext):
    projection.outputLaunchContexts.len.requireCount(maxOutputs)
    var outputs = initHashSet[uint64]()
    for context in projection.outputLaunchContexts:
      if context.output == 0 or context.generation == 0 or context.token == 0 or
          context.epoch != request.connectionEpoch or
          outputs.containsOrIncl(context.output):
        failWmFile(WmFileErrorKind.value, "output launch context is invalid")
  if projection.presentation.isSome:
    let presentation = projection.presentation.get()
    selected.requireCapabilities(capabilitySurfaceInstances)
    try:
      presentation.validatePresentation()
    except PolicyClientError:
      failWmFile(WmFileErrorKind.value, getCurrentExceptionMsg())
    var actions = presentation.bindings.len != 0
    for instance in presentation.instances:
      actions = actions or instance.action != 0
    for region in presentation.regions:
      actions = actions or region.action != 0
    if actions:
      selected.requireCapabilities(capabilityActions or capabilityPresentationActions)

proc encodeFileProjection*(
    header: WmFileHeader,
    transaction: uint64,
    request: ProjectionRequest,
    projection: PolicyProjection,
    selected: uint64,
): seq[byte] =
  header.validateHeader()
  header.requireKind(WmFileKind.projection)
  header.requireEpoch(request.connectionEpoch)
  requireNonzero(
    [transaction, request.requestId, request.sceneGeneration, projection.activeOutput]
  )
  projection.validateProjectionRows(request, selected)
  var sections: seq[WmFileSection]
  var outputs, placements, indicators, statuses: seq[byte]
  var placementCount = 0
  for output in projection.outputs:
    outputs.add(output.output.encodeProjectionOutput())
    for placement in output.placements:
      placements.add(placement.encodeProjectionPlacement())
      inc placementCount
  for indicator in projection.indicators:
    indicators.add(indicator.encodeProjectionIndicator())
  for status in projection.outputStatuses:
    statuses.add(status.encodeProjectionOutputStatus())
  sections.addSection(1, projection.outputs.len, outputs)
  sections.addSection(2, placementCount, placements)
  sections.addSection(3, projection.indicators.len, indicators)
  sections.addSection(4, projection.outputStatuses.len, statuses)
  if projection.tabGroups.len != 0:
    var groups, members: seq[byte]
    var count = 0
    for group in projection.tabGroups:
      groups.add(group.encodeTabGroup())
      for member in group.members:
        members.add(group.encodeTabMember(member))
        inc count
    sections.addSection(projectionTabGroupRecordKind, projection.tabGroups.len, groups)
    sections.addSection(projectionTabMemberRecordKind, count, members)
  if selected.has(capabilityTranslationGroups):
    var groups, members: seq[byte]
    var count = 0
    for group in projection.translationGroups:
      groups.add(group.encodeTranslationGroup())
      for member in group.members:
        members.add(group.encodeTranslationMember(member))
        inc count
    sections.addSection(
      projectionTranslationGroupRecordKind, projection.translationGroups.len, groups
    )
    sections.addSection(projectionTranslationMemberRecordKind, count, members)
  if selected.has(capabilityLaunchOrigin):
    var rows: seq[byte]
    for context in projection.launchContexts:
      rows.add(context.encodeLaunchOriginRecord())
    sections.addSection(
      projectionLaunchContextRecordKind, projection.launchContexts.len, rows
    )
  if selected.has(capabilityLaunchOrigin or capabilityOutputLaunchContext):
    var rows: seq[byte]
    for context in projection.outputLaunchContexts:
      rows.add(context.encodeOutputLaunchContext())
    sections.addSection(
      projectionOutputLaunchContextRecordKind, projection.outputLaunchContexts.len, rows
    )
  if projection.presentation.isSome:
    let records = projection.presentation.get().encodePresentation()
    for index, rows in records:
      sections.addSection(
        presentationRecordKinds[index],
        rows.len div presentationRecordSizes[index],
        rows,
      )
  var body: seq[byte]
  for field in [
    transaction, request.requestId, request.sceneGeneration, projection.activeOutput
  ]:
    body.addU64(field)
  body.addU16(uint16(sections.len))
  body.add(newSeq[byte](6))
  let rows = sections.encodeSections()
  if rows.len > wmFileMaxBytes - wmFileHeaderBytes - wmFileProjectionPrefixBytes:
    failWmFile(WmFileErrorKind.length, "projection exceeds the complete object bound")
  body.add(rows)
  header.encodePayload(WmFileKind.projection, body)
