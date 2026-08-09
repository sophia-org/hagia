import std/[hashes, tables]

type
  WindowId* = distinct uint32
  ViewId* = distinct uint32
  OutputId* = distinct uint32
  ColumnId* = distinct uint32
  TagMask* = distinct uint64
  Scale* = distinct uint32

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
    tags*: TagMask
    heightScale*: Scale
    floating*: bool
    floatingGeometry*: Rect
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
    selectedTags*: TagMask

  OutputData* = object
    id*: OutputId
    bounds*: Rect
    views*: seq[ViewId]
    activeView*: ViewId
    focusedWindow*: WindowId

  OutputAffinity* = object
    output*: OutputId
    views*: seq[ViewId]
    activeView*: ViewId
    focusedWindow*: WindowId
    disconnectedOrder*: uint64

  PolicyModel* = object
    windows*: Table[WindowId, WindowData]
    windowOrder*: seq[WindowId]
    columns*: Table[ColumnId, ColumnData]
    columnOrder*: seq[ColumnId]
    views*: Table[ViewId, ViewData]
    outputs*: Table[OutputId, OutputData]
    outputOrder*: seq[OutputId]
    affinities*: Table[OutputId, OutputAffinity]
    affinityOrder*: seq[OutputId]
    nextWindowId*: uint32
    nextColumnId*: uint32
    nextViewId*: uint32
    nextOutputId*: uint32
    nextTagSlot*: uint32
    nextDisconnectOrder*: uint64

const
  nullWindowId* = WindowId(0)
  nullViewId* = ViewId(0)
  nullOutputId* = OutputId(0)
  nullColumnId* = ColumnId(0)
  emptyTagMask* = TagMask(0)
  autoScale* = Scale(0)
  scaleOne* = Scale(1'u32 shl 16)
  minimumScale* = Scale(3277)
  maxTagBits* = 64'u32
  maxOutputAffinities* = 16

proc `==`*(left, right: WindowId): bool {.borrow.}
proc `==`*(left, right: ViewId): bool {.borrow.}
proc `==`*(left, right: OutputId): bool {.borrow.}
proc `==`*(left, right: ColumnId): bool {.borrow.}
proc `==`*(left, right: TagMask): bool {.borrow.}
proc `==`*(left, right: Scale): bool {.borrow.}

proc `$`*(id: WindowId): string {.borrow.}
proc `$`*(id: ViewId): string {.borrow.}
proc `$`*(id: OutputId): string {.borrow.}
proc `$`*(id: ColumnId): string {.borrow.}

proc hash*(id: WindowId): Hash =
  hash(uint32(id))

proc hash*(id: ViewId): Hash =
  hash(uint32(id))

proc hash*(id: OutputId): Hash =
  hash(uint32(id))

proc hash*(id: ColumnId): Hash =
  hash(uint32(id))

proc hash*(mask: TagMask): Hash =
  hash(uint64(mask))
