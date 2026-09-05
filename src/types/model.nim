import std/tables

import ./core
import ./tab_tree

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

  ## Which rule the scroller camera follows when the focused column moves,
  ## mirroring niri's center-focused-column. `onOverflow` centers only when
  ## the focused column and the one it came from cannot share the screen;
  ## otherwise the camera scrolls the shortest distance that reveals it.
  CenterFocusedColumn* {.pure.} = enum
    never
    always
    onOverflow

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
    spiral
    tgmix
    frameTree
    notion
    splitTree
    dwindle

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
    ## Whether this column is showing at full width. It is a flag rather than
    ## a width because maximising must be reversible: overwriting widthScale
    ## loses the width the column had, and it can only be recovered by
    ## pressing the same key on the same column before focus moves. niri keeps
    ## the same pair, and setting a width clears the flag.
    fullWidth*: bool

  ViewData* = object
    id*: ViewId
    preferredOutput*: OutputId
    layout*: LayoutMode
    # Where the scroller camera sits on this view, in virtual strip
    # coordinates. It lives here rather than in settings because it is
    # position, not preference: niri keeps one per workspace so a view stays
    # where it was scrolled to while another view is visited and returned to.
    # It may be negative, which is how a column narrower than the screen sits
    # centred with space to its left.
    viewportOffset*: int32

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

  ViewSlotName* = object
    slot*: int
    name*: string

  ViewSlotLayout* = object
    slot*: int
    layout*: LayoutMode

  PolicySettings* = object
    viewCount*: int
    outerGap*, innerGap*, viewportOffset*: int32
    # What a column gets when it has never been given a width of its own.
    # niri calls this default-column-width; a scroller needs one because
    # column widths no longer follow from how many columns there are.
    defaultColumnWidthPercent*: int32
    # never | always | on-overflow. Which of these the camera obeys when the
    # focused column moves, mirroring niri's center-focused-column.
    centerFocusedColumn*: CenterFocusedColumn
    ## Centre a lone column whatever the rule above says. A single window at
    ## its configured proportion otherwise sits against the left edge with the
    ## rest of the screen empty, which reads as a mistake rather than a
    ## setting. niri offers the same and defaults it off; this defaults on.
    alwaysCenterSingleColumn*: bool
    layoutCycle*: seq[LayoutMode]
    masterCount*: int
    masterRatio*: Scale
    gapStep*: int32
    gapsEnabled*: bool
    viewNames*: seq[ViewSlotName]
    viewLayouts*: seq[ViewSlotLayout]
    columnWidthPresets*: seq[int32]
    scratchpadWidthPercent*, scratchpadHeightPercent*: int32
    floatingWidthPercent*, floatingHeightPercent*: int32

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
    tabTrees*: Table[ViewId, TabTree]
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
  maxColumnWidthPresets* = 8
  maxViewNameBytes* = 32
  maxMasterCount* = 9
  maxGap* = 512
  # A master area narrower than a tenth or wider than nine tenths stops being
  # a master area, so the ratio is bounded rather than merely positive.
  minMasterRatio* = Scale(6554)
  maxMasterRatio* = Scale(58982)
  defaultMasterRatio* = Scale(32768)
  defaultColumnWidthPercent* = 50'i32
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
    scratchpadWidthPercent: 70,
    scratchpadHeightPercent: 60,
    columnWidthPresets: @[33'i32, 50, 67],
    defaultColumnWidthPercent: defaultColumnWidthPercent,
    centerFocusedColumn: CenterFocusedColumn.onOverflow,
    alwaysCenterSingleColumn: true,
  )
