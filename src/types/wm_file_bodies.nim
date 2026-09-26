import ./session
import ./wm_files
import ./wm_presentation

## Passive records for the typed bodies of `sophia_wm_fs_v1` above the
## envelope: admission, cycles and scalar controls. Where Hagia already has a
## record for a value (a projection request, outcome, receipt, profile command
## or completion, session-operation intent), these wrap it rather than
## duplicate it. Encoding, decoding and validation live under
## `src/sophia/wm_file_bodies`. Array bodies are not here.

const
  wmFileLimitsBytes* = 32
  wmFileNegotiateBytes* = 16
  wmFileNegotiatedBytes* = 8
  wmFileProfileCommandBytes* = 48
  wmFileProfileCompletionBytes* = 56
  wmFileCyclePrefixBytes* = 48
  wmFileDirtyPrefixBytes* = 16
  wmFileSessionOperationBytes* = 32
  wmFileConfigurationOutcomeBytes* = 24
  wmFileProjectionOutcomeBytes* = 32
  wmFileSessionOperationOutcomeBytes* = 24
  wmFilePresentationReceiptBytes* = 48
  wmFileSubmittedBytes* = 16

type
  ## The file's cause numbering, which differs from the legacy scalar frame's:
  ## PointerFocus is 3 and Interaction 4 here. It is converted explicitly,
  ## never cast, to Hagia's `ProjectionCauseKind`.
  WmFileCauseKind* {.pure.} = enum
    sceneChanged = 0
    action = 1
    focus = 2
    pointerFocus = 3
    interaction = 4
    outputAction = 5
    presentationAction = 6

  WmFileLimits* = object
    capabilityCeiling*: uint64
    profileRequired*: bool

  WmFileNegotiationOffer* = object
    required*: uint64
    optional*: uint64

  WmFileCycle* = object
    snapshotTransaction*: uint64
    requestTransaction*: uint64
    request*: ProjectionRequest

  WmFileProjectionOutcome* = object
    outcome*: ProjectionOutcome
    expectSessionOperation*: bool

  WmFileConfigurationOutcome* = object
    transaction*: uint64
    generation*: uint64
    kind*: ProjectionOutcomeKind

  WmFileSessionOperationOutcome* = object
    transaction*: uint64
    requestId*: uint64
    kind*: ProjectionOutcomeKind

  ## The file body carries the neutral dirty record unchanged.
  WmFileDirty* = PolicyDirty

  WmFileSessionOperation* = object
    transaction*: uint64
    intent*: SessionOperationIntent

  WmFilePresentationReceipt* = object
    transaction*: uint64
    receipt*: PresentationReceipt

  WmFileSubmitted* = object
    acceptedSubmissionId*: uint64
    candidateKind*: WmFileKind
