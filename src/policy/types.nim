import std/[hashes, tables]

type
  WindowId* = distinct uint32
  ViewId* = distinct uint32
  OutputId* = distinct uint32
  TagMask* = distinct uint64

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
    tags*: TagMask
    capabilities*: WindowCapabilities
    constraints*: SizeConstraints

  ViewData* = object
    id*: ViewId
    selectedTags*: TagMask

  OutputData* = object
    id*: OutputId
    bounds*: Rect
    views*: seq[ViewId]
    activeView*: ViewId
    focusedWindow*: WindowId

  PolicyModel* = object
    windows*: Table[WindowId, WindowData]
    windowOrder*: seq[WindowId]
    views*: Table[ViewId, ViewData]
    outputs*: Table[OutputId, OutputData]
    outputOrder*: seq[OutputId]
    nextWindowId*: uint32
    nextViewId*: uint32
    nextOutputId*: uint32
    nextTagSlot*: uint32

const
  nullWindowId* = WindowId(0)
  nullViewId* = ViewId(0)
  nullOutputId* = OutputId(0)
  emptyTagMask* = TagMask(0)
  maxTagBits* = 64'u32

proc `==`*(left, right: WindowId): bool {.borrow.}
proc `==`*(left, right: ViewId): bool {.borrow.}
proc `==`*(left, right: OutputId): bool {.borrow.}
proc `==`*(left, right: TagMask): bool {.borrow.}

proc `$`*(id: WindowId): string {.borrow.}
proc `$`*(id: ViewId): string {.borrow.}
proc `$`*(id: OutputId): string {.borrow.}

proc hash*(id: WindowId): Hash =
  hash(uint32(id))

proc hash*(id: ViewId): Hash =
  hash(uint32(id))

proc hash*(id: OutputId): Hash =
  hash(uint32(id))

proc hash*(mask: TagMask): Hash =
  hash(uint64(mask))
