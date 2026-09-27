## Snapshot rows are borrowed only until SDK snapshot_release. Copy complete
## values first, then apply Hagia's semantic validation before model mutation.
import std/sets
import ../types/desktop_sdk
import ../types/session
import ../types/wm_v1
import ./sdk_rows
import ./policy_snapshot
import ./policy_codec
import ./policy_transport

proc policySnapshot*(record: WfRecord, epoch: uint64): PolicySnapshot =
  if record.header.kind != 2 or record.header.epoch != epoch:
    fail("unexpected SDK snapshot identity")
  result.generation = record.value.snapshot.sceneGeneration
  result.activeOutput = record.value.snapshot.activeOutput
  var keys: seq[WfSnapshotOutputPolicyKey]
  for i in 0 ..< int(record.sectionCount):
    let section = record.sections[i]
    for index in 0 ..< int(section.count):
      case section.kind
      of 1:
        var row: WfSnapshotOutput
        section.decodeRow(index, row)
        result.outputs.add(row.policyValue())
      of 2:
        var row: WfSnapshotSurface
        section.decodeRow(index, row)
        result.surfaces.add(row.policyValue())
      of 3:
        var row: WfSnapshotAction
        section.decodeRow(index, row)
        result.actions.add(row.policyValue())
      of 4:
        var row: WfSnapshotSessionOperation
        section.decodeRow(index, row)
        result.sessionOperations.add(row.policyValue())
      of snapshotSurfaceClassificationRecordKind:
        var row: WfSnapshotSurfaceClassification
        section.decodeRow(index, row)
        result.classifications.add(row.policyValue())
      of snapshotLaunchOriginRecordKind:
        var row: WfSnapshotLaunchOrigin
        section.decodeRow(index, row)
        result.launchOrigins.add(row.policyValue())
      of snapshotOutputPolicyKeyRecordKind:
        var row: WfSnapshotOutputPolicyKey
        section.decodeRow(index, row)
        keys.add(row)
      else:
        fail("unsupported SDK snapshot section")
  for key in keys:
    result.outputs.applyOutputPolicyKey(key.output, key.generation, key.policyKey)
  result.validateFileSnapshot()
  result.launchOrigins.validateLaunchOrigins(epoch)
  var live = initHashSet[(uint32, uint32)]()
  for surface in result.surfaces:
    live.incl((surface.surfaceIndex, surface.surfaceGeneration))
  for origin in result.launchOrigins:
    if (origin.surfaceIndex, origin.surfaceGeneration) notin live:
      fail("snapshot launch origin is not live")
