import std/tables

import ./core

## Passive records for the private policy model. No logic lives here; state
## transitions belong to `src/policy/state.nim` and geometry to
## `src/policy/projection.nim`.

type
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

  LayoutMode* {.pure.} = enum
    scroller
    tile
    grid
    monocle
    verticalScroller
    centerTile
    rightTile
    verticalGrid
    deck

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
    layout*: LayoutMode

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

  PolicySettings* = object
    viewCount*: int
    outerGap*, innerGap*, viewportOffset*: int32
    layoutCycle*: seq[LayoutMode]
    masterCount*: int
    masterRatio*: Scale
    gapStep*: int32
    gapsEnabled*: bool

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

  GroupData* = object
    ## A set of windows a user cycles as one. Membership changes nothing about
    ## where a layout puts them; it changes which windows one key steps through,
    ## and it is what a tabbed substrate will read to decide what a tab holds.
    id*: GroupId
    windows*: seq[WindowId]
    activeWindow*: WindowId

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
    groups*: EntityStore[GroupId, GroupData]
    groupOfWindow*: Table[WindowId, GroupId]
    visibleScratchpad*: WindowId
    scratchpadTag*: TagId
    counters*: IdCounters

const
  maxOutputAffinities* = 16
  maxFocusHistory* = 32
  maxMinimizedHistory* = 64
  maxWorkspaceNameBytes* = 64
  maxScratchpads* = 64
  maxNamedScratchpadSlots* = 4
  maxGroupMembers* = 32
  maxMasterCount* = 9
  maxGap* = 512
  # A master area narrower than a tenth or wider than nine tenths stops being
  # a master area, so the ratio is bounded rather than merely positive.
  minMasterRatio* = Scale(6554)
  maxMasterRatio* = Scale(58982)
  defaultMasterRatio* = Scale(32768)
  defaultGapStep* = 2'i32
  defaultLayoutCycle* = @[
    LayoutMode.scroller, LayoutMode.tile, LayoutMode.grid, LayoutMode.monocle,
    LayoutMode.verticalScroller,
  ]
  defaultPolicySettings* = PolicySettings(
    viewCount: 9,
    layoutCycle: defaultLayoutCycle,
    masterCount: 1,
    masterRatio: defaultMasterRatio,
    gapStep: defaultGapStep,
    gapsEnabled: true,
  )
