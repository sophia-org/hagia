import std/sets

import ../types/session
import ../types/wm_v1
import ./policy_transport
import ./policy_snapshot as snapshot_checks

## Validation of complete policy values. Connection custody and file decoding
## stay with their respective owners.

proc validateSnapshot*(snapshot: PolicySnapshot) =
  snapshot_checks.validateFileSnapshot(snapshot)

proc validateLaunchOrigins*(records: openArray[LaunchOriginRecord], epoch: uint64) =
  ## Index zero is a surface; the all-ones index is not one. Everything else has
  ## to be present, the epoch has to be this connection's so a record held
  ## across a restart cannot resolve against a fresh token space, and no surface
  ## may appear twice -- two contexts for one window have no resolution.
  if records.len > maxLaunchOriginRecords:
    fail("policy launch origin records exceed their bound")
  var seen = initHashSet[uint64]()
  for record in records:
    if record.surfaceIndex == high(uint32) or record.surfaceGeneration == 0 or
        record.epoch == 0 or record.token == 0 or record.epoch != epoch:
      fail("policy launch origin record is invalid")
    let key = uint64(record.surfaceGeneration) shl 32 or uint64(record.surfaceIndex)
    if key in seen:
      fail("policy launch origin names a surface twice")
    seen.incl(key)
