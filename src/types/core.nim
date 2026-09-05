import std/[hashes, tables]

## Passive identity, geometry, and storage primitives. This module defines data
## only: the sole procedures are the hashing and string interop Nim requires for
## distinct IDs, which `docs/data-oriented-design.md` admits as the one
## exception to the no-logic rule for a types module.

type
  WindowId* = distinct uint32
  ViewId* = distinct uint32
  OutputId* = distinct uint32
  ColumnId* = distinct uint32
  TagId* = distinct uint32
  ScratchpadSlotId* = distinct uint32
  GroupId* = distinct uint32
  TagMask* = distinct uint64
  Scale* = distinct uint32

  Rect* = object
    x*, y*, width*, height*: int32

  SizeConstraints* = object
    minWidth*, minHeight*: int32
    maxWidth*, maxHeight*: int32

  EntityStore*[Id, T] = object
    ## Dense entity storage. Logical identity and semantic order live outside the
    ## dense slot so swap-and-pop removal cannot change policy behavior.
    ##
    ## Adapted from Triad's dense EntityManager at baseline
    ## fb8fb27ec294e0fe2361375de0b2fa8c08be0ca9. See THIRD_PARTY_NOTICES.md and
    ## docs/provenance.md. Hagia stores IDs beside payloads so T need not embed id.
    entities*: seq[T]
    ids*: seq[Id]
    index*: Table[Id, int]

  IdCounters* = object
    windows*, columns*, views*, outputs*, tags*, groups*: uint32
    disconnects*: uint64

const
  nullWindowId* = WindowId(0)
  nullViewId* = ViewId(0)
  nullOutputId* = OutputId(0)
  nullColumnId* = ColumnId(0)
  nullTagId* = TagId(0)
  nullScratchpadSlotId* = ScratchpadSlotId(0)
  nullGroupId* = GroupId(0)
  emptyTagMask* = TagMask(0)
  autoScale* = Scale(0)
  scaleOne* = Scale(1'u32 shl 16)
  minimumScale* = Scale(3277)
  ## Ten times the room a column can occupy. A width is a preference, so it is
  ## bounded rather than free: past this the strip coordinates stop meaning
  ## anything and a single column can put every other one out of reach.
  maximumScale* = Scale(655360)
  ## The furthest a stored camera offset may sit from the strip origin, in
  ## either direction. Far beyond any real strip, and small enough that
  ## `position - offset` always stays representable. A checkpoint claiming
  ## more is corrupt, and refusing it here is what turns a crash loop -- die
  ## on the offset, restart, restore the same offset, die again -- into one
  ## discarded checkpoint and a fresh start.
  maxViewportOffset* = int32(1 shl 30)
  maxTagBits* = 64'u32
  maxWorkspaceTagSlot* = 63'u32
  scratchpadTagSlot* = 64'u32

proc `==`*(left, right: WindowId): bool {.borrow.}
proc `==`*(left, right: ViewId): bool {.borrow.}
proc `==`*(left, right: OutputId): bool {.borrow.}
proc `==`*(left, right: ColumnId): bool {.borrow.}
proc `==`*(left, right: TagId): bool {.borrow.}
proc `==`*(left, right: ScratchpadSlotId): bool {.borrow.}
proc `==`*(left, right: GroupId): bool {.borrow.}
proc `==`*(left, right: TagMask): bool {.borrow.}
proc `==`*(left, right: Scale): bool {.borrow.}

proc `$`*(id: WindowId): string {.borrow.}
proc `$`*(id: ViewId): string {.borrow.}
proc `$`*(id: OutputId): string {.borrow.}
proc `$`*(id: ColumnId): string {.borrow.}
proc `$`*(id: TagId): string {.borrow.}
proc `$`*(id: ScratchpadSlotId): string {.borrow.}
proc `$`*(id: GroupId): string {.borrow.}

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

proc hash*(id: GroupId): Hash =
  hash(uint32(id))

proc hash*(mask: TagMask): Hash =
  hash(uint64(mask))
