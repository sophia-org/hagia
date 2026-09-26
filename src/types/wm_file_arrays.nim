import ./session

const
  wmFileSnapshotPrefixBytes* = 32
  snapshotOutputPolicyKeySize* = 24

type WmFileSnapshot* = object
  transaction*: uint64
  snapshot*: PolicySnapshot
