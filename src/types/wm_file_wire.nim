import std/[monotimes, options]
import ./[session, wm_presentation]

## Passive state of one admitted WM file connection as Hagia's file wire holds
## it: the fixed fids, event and submission counters, one bounded event
## assembly, at most one complete event held for its eventual consumer, the
## request its Cycle announced, and receipts awaiting the loop's shared
## application point. There is no phase here; phase belongs to PolicySession,
## the profile reducer and Sophia's driver.

const
  wmFileRootFid* = 1'u32
  wmFileSnapshotFid* = 2'u32
  wmFileEventsFid* = 3'u32
  wmFileSubmitFid* = 4'u32
  wmFileAckFid* = 5'u32
  wmFileTransactionFid* = 6'u32
  ## A candidate from encoding through its acknowledged Submitted is bounded
  ## by the schema's send timeout, and an event from its first byte to its
  ## last by its assembly timeout (wm_files); these budgets are Hagia's own.
  ## One deadline for the whole admission, from constructor entry, and the
  ## shorter one for discovery within it.
  wmFileAdmissionMillis* = 12_000
  wmFileDiscoveryMillis* = 4_000
  ## Each wait before policy traffic, as the legacy handoff read timeout.
  wmFileProfileWaitMillis* = 4_000
  ## A refused submit with no event progress waits this long before retrying.
  wmFileRetryPaceMillis* = 10
  ## An uncapped wait polls in these steps rather than giving up.
  wmFileIdlePollMillis* = 1_000
  ## Bytes of a 9P read or write request that are not data.
  wmFileIoOverhead* = 24
  ## The errno of a submit that transferred nothing and may be retried.
  wmFileRetryErrno* = 11'u32

type WmFileWireState* = object
  connectionEpoch*, selected*: uint64
  ## Waits are capped until policy traffic begins, as the legacy read timeout.
  profileWaits*: bool
  eventOffset*, lastSequence*, ackedThrough*: uint64
  ## The one outstanding events read and the count it asked for.
  eventTag*: Option[uint16]
  eventRequested*: uint32
  ## One record at most; a complete one is ready for its consumer. Its
  ## deadline starts with its first byte and is never renewed per fragment.
  assembly*: seq[byte]
  assemblyExpires*: Option[MonoTime]
  assemblyMillis*: int
  held*: Option[seq[byte]]
  nextSubmissionId*, nextTransaction*: uint64
  pendingRequest*: Option[ProjectionRequest]
  receipts*: seq[PresentationReceipt]
