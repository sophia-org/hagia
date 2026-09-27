import ../presentation_oracle
import ../../../../../src/sophia/policy_projection_validation
import std/options

import ../../../../../src/types/session
import ../../../../../src/types/wm_v1
import ../../../../../src/types/wm_presentation
import ../../types/wm_files
import ../../types/wm_file_arrays
import ../wm_files
import ../wm_file_payload
import ../../../../../src/sophia/policy_transport
import ../wm_tab_groups
import ../wm_translation
from ../wm_v1 import
  encodeProjectionOutput, encodeProjectionPlacement, encodeProjectionIndicator,
  encodeProjectionOutputStatus, encodeLaunchOriginRecord, encodeOutputLaunchContext
from ../../../../../src/sophia/policy_codec import validateLaunchOrigins

## Complete candidate rows, independent of legacy chunking and ordinals.
## Optional motion/launch hints retain the existing client's omission rule.
## Scene membership, final authority and settlement remain Sophia's decision.
## Candidate construction refuses invalid placement handles/state generations
## earlier than Sophia's row codec, whose Engine owner also rejects them.

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
  try:
    projection.validateProjectionRows(request, selected)
  except PolicyClientError:
    failWmFile(WmFileErrorKind.value, getCurrentExceptionMsg())
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
