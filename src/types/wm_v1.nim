## Passive wire records for Sophia's WM v1 protocol. Every offset, size, and
## bound here is a fixed contract with Sophia's corpus; the encoders, decoders,
## and validation that enforce it live in `src/sophia/wm_v1.nim`.

const
  ## Fixed octet run shared by indicator labels and layout names. Declared
  ## ahead of the type section because it bounds an array field.
  indicatorLabelLen* = 32
  profileDigestLen* = 32

type
  MessageKind* {.pure.} = enum
    clientHello = 32
    serverWelcome = 33
    snapshotBegin = 34
    snapshotChunk = 35
    snapshotEnd = 36
    projectionRequest = 37
    projectionBegin = 38
    projectionChunk = 39
    projectionEnd = 40
    projectionOutcome = 41
    policyConfiguration = 42
    policyConfigurationOutcome = 43
    policyDirty = 44
    sessionOperationRequest = 45
    sessionOperationOutcome = 46
    profilePrepare = 47
    profilePrepared = 48
    profileActivate = 49
    profileActive = 50
    profileRollback = 51
    profileRolledBack = 52

  Frame* = object
    kind*: MessageKind
    transaction*: uint64
    payload*: seq[byte]

  ProfileIdentity* = object
    connectionEpoch*: uint64
    profileGeneration*: uint64
    profileDigest*: array[profileDigestLen, byte]

  ProfileOutcomeKind* {.pure.} = enum
    accepted = 1
    rejectedIdentity = 2
    rejectedState = 3

  ProfileCommand* = object
    transaction*: uint64
    identity*: ProfileIdentity

  ProfileCompletion* = object
    transaction*: uint64
    identity*: ProfileIdentity
    outcome*: ProfileOutcomeKind

  SnapshotOutput* = object
    output*: uint64
    generation*: uint64
    focusIndex*: uint32
    focusGeneration*: uint32
    x*: int32
    y*: int32
    width*: int32
    height*: int32
    workX*: int32
    workY*: int32
    workWidth*: int32
    workHeight*: int32

  SnapshotSurface* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    stateGeneration*: uint64
    currentOutput*: uint64
    capabilityBits*: uint16
    kind*: uint16
    requestStateBits*: uint16
    currentStateBits*: uint16
    transientIndex*: uint32
    transientGeneration*: uint32
    x*: int32
    y*: int32
    width*: int32
    height*: int32
    minWidth*: int32
    minHeight*: int32
    maxWidth*: int32
    maxHeight*: int32
    exactWidth*: int32
    exactHeight*: int32

  SnapshotAction* = object
    action*: uint64
    sessionOperationSlot*: uint16
    name*: string

  SnapshotSessionOperation* = object
    operation*: uint64
    slot*: uint16
    targetBits*: uint16

  SnapshotSurfaceClassification* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    classification*: uint64

  ProjectionOutput* = object
    output*: uint64
    placementCount*: uint32
    focusIndex*: uint32
    focusGeneration*: uint32

  ## Policy-authored desktop status. The label is a fixed octet run so the
  ## record stays fixed width; `labelLen` gives the used prefix and the rest
  ## must be zero.
  ProjectionIndicator* = object
    output*: uint64
    slot*: uint32
    indicator*: uint64
    action*: uint64
    stateBits*: uint16
    labelLen*: uint16
    label*: array[indicatorLabelLen, byte]

  ProjectionOutputStatus* = object
    output*: uint64
    focusBits*: uint16
    layoutLen*: uint16
    layout*: array[indicatorLabelLen, byte]

  ProjectionPlacement* = object
    surfaceIndex*: uint32
    surfaceGeneration*: uint32
    stateGeneration*: uint64
    x*: int32
    y*: int32
    width*: int32
    height*: int32
    requestedWidth*: int32
    requestedHeight*: int32
    cropX*: int32
    cropY*: int32
    cropWidth*: int32
    cropHeight*: int32
    transform*: uint16
    presentationBits*: uint16

const
  ## Snapshot record discriminator and the capability bit the codec reads to
  ## decide whether a surface may take focus.
  snapshotSurfaceClassificationRecordKind* = 0xFF00'u16
  surfaceFocusable* = 1'u16 shl 2

  frameHeaderLen* = 24
  maxPayloadLen* = 65536
  maxOutputs* = 16
  maxSurfaces* = 1024
  maxBindings* = 256
  maxActionNameBytes* = 128
  snapshotOutputSize* = 56
  snapshotSurfaceSize* = 80
  snapshotActionSize* = 140
  snapshotSurfaceClassificationSize* = 16
  snapshotSessionOperationSize* = 12
  projectionOutputSize* = 24
  projectionPlacementSize* = 60
  projectionIndicatorSize* = 64
  projectionOutputStatusSize* = 48
  maxIndicators* = 256
