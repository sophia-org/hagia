import std/options
import ./core
import ./wm_v1
import ./wm_presentation

## Passive records for one unidirectional settlement round: the snapshot Hagia
## reconciled, the single reduced cause it applied, the complete projection it
## proposed, and Sophia's terminal outcome. The session state machine that
## drives them lives in `src/sophia/policy_session.nim`.

type
  ProjectionOutcomeKind* {.pure.} = enum
    committed = 1
    rejectedStale = 2
    rejectedInvalid = 3
    timedOut = 4
    disconnected = 5

  PolicySnapshot* = object
    generation*: uint64
    activeOutput*: uint64
    outputs*: seq[SnapshotOutput]
    surfaces*: seq[SnapshotSurface]
    actions*: seq[SnapshotAction]
    sessionOperations*: seq[SnapshotSessionOperation]
    classifications*: seq[SnapshotSurfaceClassification]
    launchOrigins*: seq[LaunchOriginRecord]

  ProjectionCauseKind* {.pure.} = enum
    sceneChanged = 0
    action = 1
    focus = 2
    interaction = 3
    ## The pointer settled on a different target. `action` carries the output
    ## the pointer is over; the target pair names a window on it, or is zero
    ## when the pointer crossed onto an output holding none. Sent only after
    ## `pointer_focus` is negotiated, so an unnegotiated one is a protocol
    ## error rather than something to ignore.
    pointerFocus = 4
    outputAction = 5
    presentationAction = 6
    ## Held or Ended for the chord behind a declared action: `activationSerial`
    ## names the chord's first Action, `lifecycleCount` its admitted Actions.
    actionLifecycle = 7
    ## A keyboard activation of a followed chord: `activationSerial` names it
    ## and `chordSerial` the chord's first activation, which its Held and Ended
    ## name in their `activationSerial`.
    chordAction = 8

  InteractionPhase* {.pure.} = enum
    none = 0
    begin = 1
    update = 2
    finish = 3
    cancel = 4

  InteractionKind* {.pure.} = enum
    none = 0
    move = 1
    resize = 2
    drag = 3
    scroll = 4

  InteractionAxis* {.pure.} = enum
    none = 0
    horizontal = 1
    vertical = 2

  ProjectionCause* = object
    kind*: ProjectionCauseKind
    interactionPhase*: InteractionPhase
    interactionKind*: InteractionKind
    interactionAxis*: InteractionAxis
    output*, outputGeneration*: uint64
    presentation*: PresentationIdentity
    activationSerial*: uint64
    action*: uint64
    targetIndex*: uint32
    targetGeneration*: uint32
    x*, y*, width*, height*: int32
    ## `actionLifecycle` only: phase 1 held, 2 ended; the reason is 0 when held,
    ## otherwise 1 released, 2 cancelled, 3 completed, 4 aborted, 5 timed out.
    lifecyclePhase*, lifecycleReason*: uint16
    lifecycleCount*: uint32
    ## `chordAction` only.
    chordSerial*: uint64

  ProjectionRequest* = object
    connectionEpoch*: uint64
    requestId*: uint64
    sceneGeneration*: uint64
    policyGeneration*: uint64
    affectedOutputs*: seq[uint64]
    cause*: ProjectionCause

  PolicyOutputProjection* = object
    output*: ProjectionOutput
    placements*: seq[ProjectionPlacement]

  ProjectionTabMember* = object
    surfaceIndex*, surfaceGeneration*: uint32

  ProjectionTabGroup* = object
    output*, group*: uint64
    x*, y*, width*, height*: int32
    selectedIndex*, selectedGeneration*: uint32
    focused*: bool
    members*: seq[ProjectionTabMember]

  ProjectionTranslationGroup* = object
    output*, group*: uint64
    x*, y*: int32
    members*: seq[ProjectionTabMember]

  PolicyProjection* = object
    presentation*: Option[WmPresentation]
    activeOutput*: uint64
    outputs*: seq[PolicyOutputProjection]
    indicators*: seq[ProjectionIndicator]
    outputStatuses*: seq[ProjectionOutputStatus]
    tabGroups*: seq[ProjectionTabGroup]
    translationGroups*: seq[ProjectionTranslationGroup]
    launchContexts*: seq[LaunchOriginRecord]
    outputLaunchContexts*: seq[OutputLaunchContext]

  LaunchDestination* = object
    ## Where a launch context points: a logical output and the tag set a window
    ## opened against it should carry. Deliberately not a window -- the source
    ## may close before the child appears, and the place it occupied is what the
    ## child inherits.
    output*: OutputId
    tags*: seq[TagId]

  ProjectionOutcome* = object
    transaction*: uint64
    connectionEpoch*: uint64
    requestId*: uint64
    sceneGeneration*: uint64
    kind*: ProjectionOutcomeKind

  SessionOperationIntent* = object
    requestId*: uint64
    operation*: uint64
    targetIndex*: uint32
    targetGeneration*: uint32

  ## The configuration Hagia installs, whatever the wire. Colours are
  ## 0x00RRGGBB; each wire encodes its own representation of them.
  PolicyConfiguration* = object
    transaction*, connectionEpoch*, generation*: uint64
    styleBits*: uint16
    focusWidth*, focusRgb*: uint32
    frameWidth*, frameFocusedRgb*, frameUnfocusedRgb*: uint32
    actions*: seq[SnapshotAction]
    ## Declared only when `action_lifecycle` was negotiated.
    actionLifecycles*: seq[ActionLifecycleInterest]

  ActionLifecycleInterest* = object
    action*: uint64
    heldMs*: uint32

  PolicyConfigurationOutcome* = object
    transaction*, connectionEpoch*, generation*: uint64
    kind*: ProjectionOutcomeKind

  ## A request for a fresh cycle over these outputs. No outcome answers it.
  PolicyDirty* = object
    policyGeneration*: uint64
    affectedOutputs*: seq[uint64]

  ## A settled projection and, where the wire states one, whether Sophia
  ## expects the session operation that projection carries. A wire without
  ## that statement reports none; nothing is inferred for it.
  ProjectionCompletion* = object
    outcome*: ProjectionOutcome
    expectSessionOperation*: Option[bool]

  PolicyTraceEntry* = object
    ## One cycle, including asynchronous receipts consumed before reduction.
    snapshot*: PolicySnapshot
    request*: ProjectionRequest
    transaction*: uint64
    presentationReceipts*: seq[PresentationReceipt]
    ## Whether this connection declared the switcher's chords, which changes
    ## what its Actions mean. Recorded on every cycle so a replay reduces each
    ## Action as the live session did; traces without it predate the
    ## lifecycle and replay as false.
    actionLifecycle*: bool
