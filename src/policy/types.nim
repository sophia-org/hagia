import std/[hashes, tables]

import ./entity_store

export entity_store

type
  WindowId* = distinct uint32
  ViewId* = distinct uint32
  OutputId* = distinct uint32
  ColumnId* = distinct uint32
  TagId* = distinct uint32
  ScratchpadSlotId* = distinct uint32
  TagMask* = distinct uint64
  Scale* = distinct uint32

  TagKind* {.pure.} = enum
    profile
    dynamic
    scratchpad

  WindowKind* {.pure.} = enum
    toplevel
    dialog
    utility
    popup
    unknown

  Rect* = object
    x*, y*, width*, height*: int32

  SizeConstraints* = object
    minWidth*, minHeight*: int32
    maxWidth*, maxHeight*: int32

  WindowCapabilities* = object
    movable*, resizable*, focusable*, closable*, fullscreenable*: bool

  WindowData* = object
    id*: WindowId
    homeOutput*: OutputId
    preferredOutput*: OutputId
    column*: ColumnId
    kind*: WindowKind
    parent*: WindowId
    heightScale*: Scale
    floating*: bool
    floatingGeometry*: Rect
    fullscreen*: bool
    maximized*: bool
    minimized*: bool
    capabilities*: WindowCapabilities
    constraints*: SizeConstraints

  ColumnData* = object
    id*: ColumnId
    homeOutput*: OutputId
    preferredOutput*: OutputId
    windows*: seq[WindowId]
    widthScale*: Scale

  ViewData* = object
    id*: ViewId
    preferredOutput*: OutputId

  TagData* = object
    id*: TagId
    slot*: uint32
    kind*: TagKind
    name*: string

  WindowTagMembership* = object
    window*: WindowId
    tag*: TagId

  ViewTagMembership* = object
    view*: ViewId
    tag*: TagId

  IdCounters* = object
    windows*, columns*, views*, outputs*, tags*: uint32
    disconnects*: uint64

  PolicySettings* = object
    viewCount*: int
    outerGap*, innerGap*, viewportOffset*: int32

  OutputData* = object
    id*: OutputId
    bounds*: Rect
    views*: seq[ViewId]
    activeView*: ViewId
    focusedWindow*: WindowId
    focusHistory*: seq[WindowId]

  OutputAffinity* = object
    output*: OutputId
    views*: seq[ViewId]
    activeView*: ViewId
    focusedWindow*: WindowId
    disconnectedOrder*: uint64

  ScratchpadRestoreData* = object
    tags*: seq[TagId]
    output*: OutputId
    floating*: bool
    floatingGeometry*: Rect
    fullscreen*: bool
    maximized*: bool
    minimized*: bool

  PolicyModel* = object
    settings*: PolicySettings
    windows*: EntityStore[WindowId, WindowData]
    windowOrder*: seq[WindowId]
    columns*: EntityStore[ColumnId, ColumnData]
    columnOrder*: seq[ColumnId]
    views*: EntityStore[ViewId, ViewData]
    tags*: EntityStore[TagId, TagData]
    outputs*: EntityStore[OutputId, OutputData]
    outputOrder*: seq[OutputId]
    windowTags*: Table[WindowId, seq[TagId]]
    viewTags*: Table[ViewId, seq[TagId]]
    activeOutput*: OutputId
    minimizedOrder*: seq[WindowId]
    affinities*: Table[OutputId, OutputAffinity]
    affinityOrder*: seq[OutputId]
    scratchpadOrder*: seq[WindowId]
    scratchpadRestore*: Table[WindowId, ScratchpadRestoreData]
    namedScratchpads*: Table[ScratchpadSlotId, WindowId]
    visibleScratchpad*: WindowId
    scratchpadTag*: TagId
    counters*: IdCounters

const
  nullWindowId* = WindowId(0)
  nullViewId* = ViewId(0)
  nullOutputId* = OutputId(0)
  nullColumnId* = ColumnId(0)
  nullTagId* = TagId(0)
  nullScratchpadSlotId* = ScratchpadSlotId(0)
  emptyTagMask* = TagMask(0)
  autoScale* = Scale(0)
  scaleOne* = Scale(1'u32 shl 16)
  minimumScale* = Scale(3277)
  maxTagBits* = 64'u32
  maxWorkspaceTagSlot* = 63'u32
  scratchpadTagSlot* = 64'u32
  maxOutputAffinities* = 16
  maxFocusHistory* = 32
  maxMinimizedHistory* = 64
  maxWorkspaceNameBytes* = 64
  maxScratchpads* = 64
  defaultPolicySettings* = PolicySettings(viewCount: 9)

proc `==`*(left, right: WindowId): bool {.borrow.}
proc `==`*(left, right: ViewId): bool {.borrow.}
proc `==`*(left, right: OutputId): bool {.borrow.}
proc `==`*(left, right: ColumnId): bool {.borrow.}
proc `==`*(left, right: TagId): bool {.borrow.}
proc `==`*(left, right: ScratchpadSlotId): bool {.borrow.}
proc `==`*(left, right: TagMask): bool {.borrow.}
proc `==`*(left, right: Scale): bool {.borrow.}

proc `$`*(id: WindowId): string {.borrow.}
proc `$`*(id: ViewId): string {.borrow.}
proc `$`*(id: OutputId): string {.borrow.}
proc `$`*(id: ColumnId): string {.borrow.}
proc `$`*(id: TagId): string {.borrow.}
proc `$`*(id: ScratchpadSlotId): string {.borrow.}

proc hash*(id: WindowId): Hash =
  hash(uint32(id))

proc hash*(id: ViewId): Hash =
  hash(uint32(id))

proc hash*(id: OutputId): Hash =
  hash(uint32(id))

proc hash*(id: ColumnId): Hash =
  hash(uint32(id))

proc hash*(id: TagId): Hash =
  hash(uint32(id))

proc hash*(id: ScratchpadSlotId): Hash =
  hash(uint32(id))

proc hash*(mask: TagMask): Hash =
  hash(uint64(mask))
