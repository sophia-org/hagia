import ./session
import ./wm_v1

const
  wmFileSnapshotPrefixBytes* = 32
  wmFileConfigurationPrefixBytes* = 48
  wmFileProjectionPrefixBytes* = 40
  wmFileChromeMaxWidth* = 64'u32
  snapshotOutputPolicyKeySize* = 24

type
  WmFileSnapshot* = object
    transaction*: uint64
    snapshot*: PolicySnapshot

  WmFileConfiguration* = object
    transaction*, connectionEpoch*, generation*: uint64
    styleBits*: uint16
    focusWidth*, focusRgb*: uint32
    frameWidth*, frameFocusedRgb*, frameUnfocusedRgb*: uint32
    actions*: seq[SnapshotAction]
