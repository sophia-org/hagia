import ./core

const
  maxPresentationOutputs* = 16
  maxSurfaceInstances* = 1024
  maxPresentationRegions* = 1024
  maxPresentationBindings* = 256
  presentationRecordKinds* =
    [0xff09'u16, 0xff0a'u16, 0xff0b'u16, 0xff0c'u16, 0xff0d'u16]
  presentationRecordSizes* = [32, 40, 80, 72, 16]

type
  PresentationMode* {.pure.} = enum
    overlay = 1
    replaceApplications = 2

  PresentationRegionRole* {.pure.} = enum
    backdrop = 1
    frame = 2
    emphasis = 3

  PresentationOutput* = object
    output*, generation*: uint64
    coverage*: Rect
    mode*: PresentationMode

  SurfaceInstance* = object
    id*, generation*, output*: uint64
    sourceIndex*, sourceGeneration*: uint32
    destination*, clip*: Rect
    opacityMillis*, zIndex*: uint16
    action*: uint64

  PresentationRegion* = object
    id*, generation*, output*: uint64
    geometry*, clip*: Rect
    zIndex*: uint16
    role*: PresentationRegionRole
    action*: uint64

  PresentationBinding* = object
    action*: uint64
    keycode*, modifiers*: uint32

  WmPresentation* = object
    generation*, keyboardOutput*: uint64
    outputs*: seq[PresentationOutput]
    instances*: seq[SurfaceInstance]
    regions*: seq[PresentationRegion]
    bindings*: seq[PresentationBinding]

  PresentationRecords* = array[5, seq[byte]]

  PresentationIdentity* = object
    publicationGeneration*, output*, outputGeneration*: uint64
    presentationEpoch*, targetId*, targetGeneration*: uint64

  PresentationOutcomeKind* {.pure.} = enum
    presented = 1
    revoked = 2
    withdrawn = 3

  PresentationReceipt* = object
    connectionEpoch*, publicationGeneration*: uint64
    output*, outputGeneration*, presentationEpoch*: uint64
    outcome*: PresentationOutcomeKind
