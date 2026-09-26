import std/sets

import ../types/[session, wm_v1, wm_files, wm_file_arrays]
import ./[wm_files, wm_file_payload, policy_snapshot, policy_transport]
from ./wm_v1 import
  PolicyProtocolError, decodeSnapshotOutput, decodeSnapshotSurface,
  decodeSnapshotAction, decodeSnapshotSessionOperation,
  decodeSnapshotSurfaceClassification, decodeLaunchOriginRecord, encodeSnapshotAction
from ./policy_codec import validateLaunchOrigins

## Complete arrays reuse fixed row codecs and typed validation, never legacy
## frames or transfers. Shape, capability and aggregate checks precede row work.

proc snapshotLayout(kind: uint16): tuple[size, maximum: int, capability: uint64] =
  case kind
  of 1:
    (snapshotOutputSize, maxOutputs, 0'u64)
  of 2:
    (snapshotSurfaceSize, maxSurfaces, 0'u64)
  of 3:
    (snapshotActionSize, maxBindings, capabilityActions)
  of 4:
    (snapshotSessionOperationSize, maxBindings, capabilitySessionOperations)
  of snapshotSurfaceClassificationRecordKind:
    (snapshotSurfaceClassificationSize, maxSurfaces, capabilityLaunchPlacement)
  of snapshotLaunchOriginRecordKind:
    (launchOriginRecordSize, maxLaunchOriginRecords, capabilityLaunchOrigin)
  of snapshotOutputPolicyKeyRecordKind:
    (snapshotOutputPolicyKeySize, maxOutputs, capabilityOutputPolicyKeys)
  else:
    failWmFile(WmFileErrorKind.sections, "unknown snapshot section")

proc decodeFileSnapshot*(
    bytes: openArray[byte], expectedEpoch, selected: uint64
): WmFileSnapshot =
  discard
    bytes.prefixedPayload(WmFileKind.snapshot, expectedEpoch, wmFileSnapshotPrefixBytes)
  const prefix = wmFileHeaderBytes
  const rows = prefix + wmFileSnapshotPrefixBytes
  result.transaction = bytes.readU64(prefix)
  result.snapshot.generation = bytes.readU64(prefix + 8)
  result.snapshot.activeOutput = bytes.readU64(prefix + 16)
  requireNonzero(
    [result.transaction, result.snapshot.generation, result.snapshot.activeOutput]
  )
  bytes.requireReserved(prefix + 26, 6)
  let count = bytes.readU16(prefix + 24)
  if count == 0:
    failWmFile(WmFileErrorKind.sections, "snapshot has no output section")
  let sections = bytes.toOpenArray(rows, bytes.high).decodeSections(count)
  var hasOutputs = false
  for section in sections:
    let layout = snapshotLayout(section.kind)
    # The raw peer count is bounded before conversion or multiplication.
    if section.count > uint32(layout.maximum):
      failWmFile(WmFileErrorKind.value, "snapshot row count exceeds its bound")
    if section.length != int(section.count) * layout.size:
      failWmFile(WmFileErrorKind.length, "snapshot row width is invalid")
    selected.requireCapabilities(layout.capability)
    hasOutputs = hasOutputs or section.kind == 1
  if not hasOutputs:
    failWmFile(WmFileErrorKind.sections, "snapshot has no output section")

  try:
    for section in sections:
      let size = snapshotLayout(section.kind).size
      for index in 0 ..< int(section.count):
        let at = rows + section.offset + index * size
        case section.kind
        of 1:
          result.snapshot.outputs.add(
            bytes.toOpenArray(at, at + size - 1).decodeSnapshotOutput()
          )
        of 2:
          result.snapshot.surfaces.add(
            bytes.toOpenArray(at, at + size - 1).decodeSnapshotSurface()
          )
        of 3:
          result.snapshot.actions.add(
            bytes.toOpenArray(at, at + size - 1).decodeSnapshotAction()
          )
        of 4:
          result.snapshot.sessionOperations.add(
            bytes.toOpenArray(at, at + size - 1).decodeSnapshotSessionOperation()
          )
        of snapshotSurfaceClassificationRecordKind:
          result.snapshot.classifications.add(
            bytes.toOpenArray(at, at + size - 1).decodeSnapshotSurfaceClassification()
          )
        of snapshotLaunchOriginRecordKind:
          result.snapshot.launchOrigins.add(
            bytes.toOpenArray(at, at + size - 1).decodeLaunchOriginRecord()
          )
        of snapshotOutputPolicyKeyRecordKind:
          result.snapshot.outputs.applyOutputPolicyKey(
            bytes.readU64(at), bytes.readU64(at + 8), bytes.readU64(at + 16)
          )
        else:
          failWmFile(WmFileErrorKind.sections, "unknown snapshot section")
    result.snapshot.validateFileSnapshot()
    result.snapshot.launchOrigins.validateLaunchOrigins(expectedEpoch)
    var live = initHashSet[(uint32, uint32)]()
    for surface in result.snapshot.surfaces:
      live.incl((surface.surfaceIndex, surface.surfaceGeneration))
    for origin in result.snapshot.launchOrigins:
      if (origin.surfaceIndex, origin.surfaceGeneration) notin live:
        failWmFile(WmFileErrorKind.value, "snapshot launch origin is not live")
  except PolicyClientError, PolicyProtocolError:
    failWmFile(
      WmFileErrorKind.value, "invalid snapshot rows: " & getCurrentExceptionMsg()
    )

proc encodeFileConfiguration*(
    header: WmFileHeader, value: WmFileConfiguration, selected: uint64
): seq[byte] =
  header.validateHeader()
  header.requireKind(WmFileKind.configuration)
  header.requireEpoch(value.connectionEpoch)
  requireNonzero([value.transaction, value.generation])
  selected.requireCapabilities(capabilityConfiguration)
  if (value.styleBits and not 3'u16) != 0:
    failWmFile(WmFileErrorKind.reserved, "configuration style bits are invalid")
  for color in [value.focusRgb, value.frameFocusedRgb, value.frameUnfocusedRgb]:
    if (color shr 24) != 0:
      failWmFile(WmFileErrorKind.reserved, "file configuration requires 00RRGGBB")
  for (enabled, width) in [
    ((value.styleBits and 1) != 0, value.focusWidth),
    ((value.styleBits and 2) != 0, value.frameWidth),
  ]:
    if width > wmFileChromeMaxWidth or enabled != (width > 0):
      failWmFile(WmFileErrorKind.value, "configuration chrome width is invalid")
  if value.styleBits != 0:
    selected.requireCapabilities(capabilityChrome)
  if value.actions.len > maxBindings:
    failWmFile(WmFileErrorKind.value, "too many configuration actions")
  if value.actions.len > 0:
    selected.requireCapabilities(capabilityActions)
  var ids = initHashSet[uint64]()
  var names = initHashSet[string]()
  var rows: seq[byte]
  for action in value.actions:
    if action.action == 0 or ids.containsOrIncl(action.action) or
        names.containsOrIncl(action.name):
      failWmFile(WmFileErrorKind.value, "configuration action is null or repeated")
    try:
      rows.add(action.encodeSnapshotAction())
    except PolicyProtocolError:
      failWmFile(WmFileErrorKind.value, getCurrentExceptionMsg())
  var sections: seq[WmFileSection]
  if value.actions.len > 0:
    sections.add(WmFileSection(kind: 3, count: uint32(value.actions.len), rows: rows))
  var body: seq[byte]
  body.addU64(value.transaction)
  body.addU64(value.generation)
  body.addU16(value.styleBits)
  body.addU16(uint16(sections.len))
  for field in [
    value.focusWidth, value.focusRgb, value.frameWidth, value.frameFocusedRgb,
    value.frameUnfocusedRgb,
  ]:
    body.addU32(field)
  body.addU64(0)
  body.add(sections.encodeSections())
  header.encodePayload(WmFileKind.configuration, body)
