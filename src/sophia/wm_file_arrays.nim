import std/sets

import ../types/[session, wm_v1, wm_files, wm_file_arrays]
import ./[wm_files, wm_file_payload, policy_snapshot, policy_transport]
from ./wm_v1 import
  PolicyProtocolError, decodeSnapshotOutput, decodeSnapshotSurface,
  decodeSnapshotAction, decodeSnapshotSessionOperation,
  decodeSnapshotSurfaceClassification, decodeLaunchOriginRecord
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
    if section.count > uint32(layout.maximum) or
        section.length != int(section.count) * layout.size:
      failWmFile(WmFileErrorKind.sections, "snapshot row count or width is invalid")
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
    failWmFile(WmFileErrorKind.value, "invalid snapshot rows")
