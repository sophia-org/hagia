import std/options
import ../types/desktop_sdk
import ../types/sdk_candidate
import ../types/session
import ../types/wm_v1
import ../types/wm_presentation
import ./sdk_rows
import ./policy_transport
from ./policy_projection_validation import validateProjectionRows

proc addSection(
    value: var SdkCandidate, kind: uint16, count: int, rows: sink seq[byte]
) =
  if count == 0:
    return
  if count < 0 or uint64(count) > uint64(high(uint32)) or value.record.sectionCount >= 32:
    fail("SDK candidate section bound exceeded")
  let index = int(value.record.sectionCount)
  var size = rows.len
  for i in 0 ..< index:
    size += value.rows[i].len
  if size > 1_048_576:
    fail("SDK candidate byte bound exceeded")
  value.rows[index] = rows
  value.record.sections[index] = WfSection(kind: kind, count: uint32(count))
  inc value.record.sectionCount

proc bindRows*(value: var SdkCandidate) =
  ## Call after moving/constructing the value, immediately before submit.
  for i in 0 ..< int(value.record.sectionCount):
    if value.rows[i].len == 0:
      fail("empty SDK candidate section")
    value.record.sections[i].rows =
      cast[ptr UncheckedArray[uint8]](addr value.rows[i][0])
    value.record.sections[i].bytes = csize_t(value.rows[i].len)

proc configurationCandidate*(value: PolicyConfiguration): SdkCandidate =
  result.record.header.kind = 260
  result.record.value.configuration = WfConfiguration(
    transaction: value.transaction,
    generation: value.generation,
    styleBits: value.styleBits,
    focusWidth: value.focusWidth,
    focusRgb: value.focusRgb,
    frameWidth: value.frameWidth,
    frameFocusedRgb: value.frameFocusedRgb,
    frameUnfocusedRgb: value.frameUnfocusedRgb,
  )
  if value.actions.len > maxBindings:
    fail("too many policy actions")
  var rows: seq[byte]
  for action in value.actions:
    rows.add(action.sdkValue().encodeRow())
  result.addSection(3, value.actions.len, rows)
  var lifecycles: seq[byte]
  for interest in value.actionLifecycles:
    lifecycles.add(
      WfConfigurationActionLifecycle(action: interest.action, heldMs: interest.heldMs).encodeRow()
    )
  result.addSection(
    configurationActionLifecycleKind, value.actionLifecycles.len, lifecycles
  )

proc addPresentation(value: var SdkCandidate, p: WmPresentation) =
  let header = WfProjectionPresentation(
    generation: p.generation,
    keyboardOutput: p.keyboardOutput,
    outputCount: uint16(p.outputs.len),
    bindingCount: uint16(p.bindings.len),
    instanceCount: uint32(p.instances.len),
    regionCount: uint32(p.regions.len),
  )
  value.addSection(presentationRecordKinds[0], 1, header.encodeRow())
  var outputs, instances, regions, bindings: seq[byte]
  for v in p.outputs:
    outputs.add(
      WfProjectionPresentationOutput(
        output: v.output,
        generation: v.generation,
        x: v.coverage.x,
        y: v.coverage.y,
        width: v.coverage.width,
        height: v.coverage.height,
        mode: uint16(v.mode),
      ).encodeRow()
    )
  for v in p.instances:
    instances.add(
      WfProjectionSurfaceInstance(
        id: v.id,
        generation: v.generation,
        output: v.output,
        sourceIndex: v.sourceIndex,
        sourceGeneration: v.sourceGeneration,
        x: v.destination.x,
        y: v.destination.y,
        width: v.destination.width,
        height: v.destination.height,
        clipX: v.clip.x,
        clipY: v.clip.y,
        clipWidth: v.clip.width,
        clipHeight: v.clip.height,
        opacityMillis: v.opacityMillis,
        zIndex: v.zIndex,
        action: v.action,
      ).encodeRow()
    )
  for v in p.regions:
    regions.add(
      WfProjectionPresentationRegion(
        id: v.id,
        generation: v.generation,
        output: v.output,
        x: v.geometry.x,
        y: v.geometry.y,
        width: v.geometry.width,
        height: v.geometry.height,
        clipX: v.clip.x,
        clipY: v.clip.y,
        clipWidth: v.clip.width,
        clipHeight: v.clip.height,
        zIndex: v.zIndex,
        role: uint16(v.role),
        action: v.action,
      ).encodeRow()
    )
  for v in p.bindings:
    bindings.add(
      WfProjectionPresentationBinding(
        action: v.action, keycode: v.keycode, modifiers: v.modifiers
      ).encodeRow()
    )
  value.addSection(presentationRecordKinds[1], p.outputs.len, outputs)
  value.addSection(presentationRecordKinds[2], p.instances.len, instances)
  value.addSection(presentationRecordKinds[3], p.regions.len, regions)
  value.addSection(presentationRecordKinds[4], p.bindings.len, bindings)

proc projectionCandidate*(
    request: ProjectionRequest,
    transaction: uint64,
    projection: PolicyProjection,
    selected: uint64,
): SdkCandidate =
  projection.validateProjectionRows(request, selected)
  result.record.header.kind = 262
  result.record.value.projection = WfProjection(
    transaction: transaction,
    requestId: request.requestId,
    baseGeneration: request.sceneGeneration,
    activeOutput: projection.activeOutput,
  )
  var outputs, placements, indicators, statuses: seq[byte]
  var count = 0
  for output in projection.outputs:
    outputs.add(output.output.sdkValue().encodeRow())
    for placement in output.placements:
      placements.add(placement.sdkValue().encodeRow())
      inc count
  for row in projection.indicators:
    indicators.add(row.sdkValue().encodeRow())
  for row in projection.outputStatuses:
    statuses.add(row.sdkValue().encodeRow())
  result.addSection(1, projection.outputs.len, outputs)
  result.addSection(2, count, placements)
  result.addSection(3, projection.indicators.len, indicators)
  result.addSection(4, projection.outputStatuses.len, statuses)
  var groups, members: seq[byte]
  count = 0
  for g in projection.tabGroups:
    groups.add(
      WfProjectionTabGroup(
        output: g.output,
        group: g.group,
        x: g.x,
        y: g.y,
        width: g.width,
        height: g.height,
        selectedIndex: g.selectedIndex,
        selectedGeneration: g.selectedGeneration,
        memberCount: uint32(g.members.len),
        focused: uint32(g.focused),
      ).encodeRow()
    )
    for m in g.members:
      members.add(
        WfProjectionTabMember(
          output: g.output,
          group: g.group,
          surfaceIndex: m.surfaceIndex,
          surfaceGeneration: m.surfaceGeneration,
        ).encodeRow()
      )
      inc count
  result.addSection(projectionTabGroupRecordKind, projection.tabGroups.len, groups)
  result.addSection(projectionTabMemberRecordKind, count, members)
  if (selected and capabilityTranslationGroups) != 0:
    groups = @[]
    members = @[]
    count = 0
    for g in projection.translationGroups:
      groups.add(
        WfProjectionTranslationGroup(
          output: g.output,
          group: g.group,
          x: g.x,
          y: g.y,
          memberCount: uint32(g.members.len),
        ).encodeRow()
      )
      for m in g.members:
        members.add(
          WfProjectionTranslationMember(
            output: g.output,
            group: g.group,
            surfaceIndex: m.surfaceIndex,
            surfaceGeneration: m.surfaceGeneration,
          ).encodeRow()
        )
        inc count
    result.addSection(
      projectionTranslationGroupRecordKind, projection.translationGroups.len, groups
    )
    result.addSection(projectionTranslationMemberRecordKind, count, members)
  if (selected and capabilityLaunchOrigin) != 0:
    var rows: seq[byte]
    for v in projection.launchContexts:
      rows.add(v.sdkValue().encodeRow())
    result.addSection(
      projectionLaunchContextRecordKind, projection.launchContexts.len, rows
    )
  let outputContextCaps = capabilityLaunchOrigin or capabilityOutputLaunchContext
  if (selected and outputContextCaps) == outputContextCaps:
    var rows: seq[byte]
    for v in projection.outputLaunchContexts:
      rows.add(v.sdkValue().encodeRow())
    result.addSection(
      projectionOutputLaunchContextRecordKind, projection.outputLaunchContexts.len, rows
    )
  if projection.presentation.isSome:
    result.addPresentation(projection.presentation.get())
