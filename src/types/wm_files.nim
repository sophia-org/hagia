## Passive records for the Sophia WM file envelope, `sophia_wm_fs_v1`. Every
## offset, size, bound and kind value is a fixed contract with Sophia's
## `protocol/sophia-wm-files-v1.kdl`; the encoders, decoders and validation that
## enforce it live in `src/sophia/wm_files.nim`. Body semantics belong to the
## typed codecs above this envelope.

const
  wmFileApiVersion* = 1'u16
  wmFileHeaderBytes* = 32
  wmFileMaxBytes* = 1_048_576
  wmFileMaxSections* = 32
  wmFileSectionHeaderBytes* = 16
  wmFileSubmitBytes* = 24
  wmFileAckBytes* = 16

type
  WmFileKind* {.pure.} = enum
    limits = 1
    snapshot = 2
    negotiated = 16
    submitted = 17
    profilePrepare = 18
    profileActivate = 19
    profileRollback = 20
    configurationOutcome = 21
    cycle = 22
    projectionOutcome = 23
    sessionOperationOutcome = 24
    presentationReceipt = 25
    negotiate = 256
    profilePrepared = 257
    profileActive = 258
    profileRolledBack = 259
    configuration = 260
    dirty = 261
    projection = 262
    sessionOperation = 263

  ## Which file a record belongs in, the KDL's object, event and candidate:
  ## objects are published whole by Sophia, events are journaled by Sophia,
  ## candidates are staged by the WM.
  WmFileClass* {.pure.} = enum
    objectRecord
    eventRecord
    candidateRecord

  WmFileHeader* = object
    kind*: WmFileKind
    connectionEpoch*: uint64
    submissionId*: uint64
    sequence*: uint64

  ## One complete row section to encode. Row grammar and aggregate bounds
  ## belong to the typed body codec, not the envelope.
  WmFileSection* = object
    kind*: uint16
    count*: uint32
    rows*: seq[byte]

  ## One decoded section, located inside the section block the decoder was
  ## given rather than copied out of it.
  WmFileSectionView* = object
    kind*: uint16
    count*: uint32
    offset*: int
    length*: int

  WmFileSubmit* = object
    connectionEpoch*: uint64
    submissionId*: uint64
    candidateBytes*: uint32

  WmFileAck* = object
    connectionEpoch*: uint64
    sequence*: uint64
