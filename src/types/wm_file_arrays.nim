import ./session

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

  ## The file body carries the neutral configuration record unchanged.
  WmFileConfiguration* = PolicyConfiguration
