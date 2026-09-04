import std/options

## Passive wire and model records for Sophia's shell descriptor protocol.
## Offsets, bounds, and capability bits are a fixed contract with Sophia's
## corpus; encoding, validation, and the reducer live in
## `src/sophia/shell_v1.nim`.

const
  shellFrameHeaderLen* = 24
  shellMaxPayloadLen* = 65536
  shellMaxDescriptors* = 16
  shellMaxLabelBytes* = 128
  shellDescriptorCapability* = 1'u64
  shellReservationCapability* = 2'u64
  shellMaxReservationThickness* = 512'u16

type
  ShellMessageKind* {.pure.} = enum
    clientHello = 96
    serverWelcome = 97
    descriptorSnapshot = 98
    candidate = 99
    candidateOutcome = 100
    activation = 101
    activationAck = 102

  ShellFrame* = object
    kind*: ShellMessageKind
    transaction*: uint64
    payload*: seq[byte]

  ShellActionRef* = object
    token*: uint64
    issuerEpoch*: uint64
    issuerRevocationEpoch*: uint64
    recipientEpoch*: uint64
    targetSlot*: uint16
    targetGeneration*: uint64

  ShellDescriptor* = object
    slot*: uint16
    generation*: uint64
    label*: Option[string]
    labelRedacted*: bool
    trust*: uint8
    attention*: uint8
    action*: ShellActionRef

  ShellSnapshot* = object
    connectionEpoch*: uint64
    generation*: uint64
    output*: uint64
    outputGeneration*: uint64
    brokerEpoch*: uint64
    brokerRevocationEpoch*: uint64
    descriptors*: seq[ShellDescriptor]

  ShellDescriptorKey* = object
    slot*: uint16
    generation*: uint64

  ShellReservationEdge* {.pure.} = enum
    top = 1
    bottom = 2
    left = 3
    right = 4

  ShellReservation* = object
    edge*: ShellReservationEdge
    thicknessPx*: uint16

  ShellCandidate* = object
    connectionEpoch*: uint64
    snapshotGeneration*: uint64
    generation*: uint64
    output*: uint64
    visible*: bool
    selected*: Option[uint16]
    reservation*: Option[ShellReservation]
    entries*: seq[ShellDescriptorKey]

  ShellCandidateOutcomeKind* {.pure.} = enum
    prepared = 1
    presented = 2
    rejected = 3
    superseded = 4

  ShellCandidateOutcome* = object
    connectionEpoch*: uint64
    candidateGeneration*: uint64
    presentationEpoch*: uint64
    kind*: ShellCandidateOutcomeKind

  ShellActivation* = object
    connectionEpoch*: uint64
    candidateGeneration*: uint64
    presentationEpoch*: uint64
    activation*: uint64
    action*: ShellActionRef

  ShellActivationDisposition* {.pure.} = enum
    consumed = 1
    rejectedStale = 2

  ShellModel* = object
    connectionEpoch*: uint64
    snapshotGeneration*: uint64
    output*: uint64
    order*: seq[ShellDescriptorKey]
    selected*: Option[uint16]
    presentedGeneration*: uint64
    presentationEpoch*: uint64
    lastActivation*: uint64
