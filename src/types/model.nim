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
  ## `onOverflow` centers only when
  ## the focused column and the one it came from cannot share the screen;
  ## otherwise the camera scrolls the shortest distance that reveals it.
  ## What a camera action asked for, if anything.
  ScrollerStrip* = object
    ## Where every column of a scroller sits, in strip coordinates.
    ##
    ## The projection needs this to place windows and an action needs it to
    ## decide what is on screen, so it is computed once, by `scrollerStrip`,
    ## rather than twice with two chances to disagree.
    positions*: seq[int32]
    widths*: seq[int32]
    usableWidth*: int32
    focused*: int

  CameraIntent* {.pure.} = enum
    none
    centerFocused
    centerVisible

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

  FloatingIntent* {.pure.} = enum
    ## Where a floating window's position comes from.
    ##
    ## `automatic` is a rule still to be evaluated -- a dialog sits on its
    ## parent, wherever the parent has ended up this cycle -- and `manual` is a
    ## position the operator chose, which nothing may recompute. The two have
    ## to be stored apart because the rectangle they produce looks the same,
    ## and guessing from the rectangle is how a dragged dialog springs back.
    automatic
    manual

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
    ## Whether `floatingGeometry`'s position is a rule or a decision. The size
    ## is stored either way; only the position is derived.
    floatingIntent*: FloatingIntent
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
    ## What this column asks for along the scrolling axis. A proportion
    ## rescales with the output; a fixed extent does not, which is the whole
    ## of what makes it fixed. `automatic` means the column never chose, and
    ## resolves to the configured default wherever it is read.
    width*: LayoutExtent
    ## Whether this column is showing at full width. It is a flag rather than
    ## a width because maximising must be reversible: overwriting the width
    ## loses the one the column had, and it can only be recovered by
    ## pressing the same key on the same column before focus moves. Setting a
    ## width clears the flag.
    fullWidth*: bool

  CameraAnchor* = object
    column*: ColumnId
    position*: int32

  ViewData* = object
    id*: ViewId
    preferredOutput*: OutputId
    layout*: LayoutMode
    # Where the scroller camera sits on this view, in virtual strip
    # coordinates. It lives here rather than in settings because it is
    # position, not preference: one per workspace keeps a view
    # where it was scrolled to while another view is visited and returned to.
    # It may be negative, which is how a column narrower than the screen sits
    # centred with space to its left.
    viewportOffset*: int32
    # The same camera for the vertical scroller. The two layouts scroll along
    # different axes, so one field cannot serve both: an x offset applied as y
    # scrolls the view somewhere nobody asked for the moment a view switches
    # between them.
    viewportOffsetY*: int32
    ## A camera move asked for by name rather than derived from focus. The
    ## projection is the only place the strip geometry exists, so an action
    ## that wants to centre something records what it wants and the projection
    ## works out where that is. Cleared once a projection commits.
    cameraIntent*: CameraIntent
    camera*, cameraY*: CameraAnchor
    openedColumn*: ColumnId
    openingFocus*: WindowId
    openingOffset*, openingOffsetY*: int32

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

  GapModel* {.pure.} = enum
    legacy
    uniform

  LayoutStruts* = object
    left*, right*, top*, bottom*: int32

  PolicySettings* = object
    viewCount*: int
    outerGap*, innerGap*, viewportOffset*: int32
    # Legacy profiles keep their two insets; uniform gaps reserve along-axis
    # padding once, through the scroller camera.
    gapModel*: GapModel
    gaps*: int32
    struts*: LayoutStruts
    # What a column gets when it has never been given a width of its own.
    # `default-column-width` names it; a scroller needs one because
    # column widths no longer follow from how many columns there are.
    defaultColumnWidth*: LayoutExtent
    # never | always | on-overflow. Which of these the camera obeys when the
    # focused column moves.
    centerFocusedColumn*: CenterFocusedColumn
    ## What a vertical-scroller row gets when it never chose a height, and the
    ## presets its cycle key steps through. `automatic` and empty mean inherit
    ## the column values: the vertical scroller is the same machine along y, so
    ## its extent-along-the-axis default is the column width's unless a profile
    ## says otherwise.
    ##
    ## These two are Triad vocabulary. They name the scroll-axis extent of a
    ## vertical scroller, which is not the cross-axis share of a window inside
    ## a column -- Hagia spells that `WindowData.heightScale` and does not
    ## expose it as a preset list.
    defaultRowHeight*: LayoutExtent
    presetRowHeights*: seq[LayoutExtent]
    ## Centre a lone column whatever the rule above says. A single window at
    ## its configured proportion otherwise sits against the left edge with the
    ## rest of the screen empty, which reads as a mistake rather than a
    ## setting. On by default.
    alwaysCenterSingleColumn*: bool
    ## Move focus to whatever the pointer is over, including an output holding
    ## no window. Off by default: a pointer that crosses a
    ## window on its way somewhere else should not take focus with it unless
    ## the operator asked for that. Hagia owns the preference; Sophia owns the
    ## hit test and sends an observation only when this is on.
    focusFollowsMouse*: bool
    layoutCycle*: seq[LayoutMode]
    masterCount*: int
    masterRatio*: Scale
    gapStep*: int32
    gapsEnabled*: bool
    viewNames*: seq[ViewSlotName]
    viewLayouts*: seq[ViewSlotLayout]
    presetColumnWidths*: seq[LayoutExtent]
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
    floatingIntent*: FloatingIntent
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
  maxSizePresets* = 8
  maxViewNameBytes* = 32
  maxMasterCount* = 9
  maxGap* = 512
  ## How far a dialog chain is walked when focus falls back through it. Trees
  ## are shallow; the bound is what makes the walk terminate regardless.
  maxFamilyDepth* = 8
  # A master area narrower than a tenth or wider than nine tenths stops being
  # a master area, so the ratio is bounded rather than merely positive.
  minMasterRatio* = Scale(6554)
  maxMasterRatio* = Scale(58982)
  defaultMasterRatio* = Scale(32768)
  defaultColumnWidth* =
    LayoutExtent(kind: LayoutExtentKind.proportion, scale: Scale(32768))
  defaultGapStep* = 2'i32
  ## One gap around and between tiles. The legacy
  ## outer/inner pair is unaffected: it only applies under `GapModel.legacy`,
  ## and a model that never read a profile stays there.
  defaultGaps* = 16'i32
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
    # The percentages these replace, as the exact Q16.16 scales the percent
    # resolver produced, so nothing on screen moves for a profile that states
    # neither key.
    presetColumnWidths: @[
      LayoutExtent(kind: LayoutExtentKind.proportion, scale: Scale(21626)),
      LayoutExtent(kind: LayoutExtentKind.proportion, scale: Scale(32768)),
      LayoutExtent(kind: LayoutExtentKind.proportion, scale: Scale(43909)),
    ],
    defaultColumnWidth: defaultColumnWidth,
    centerFocusedColumn: CenterFocusedColumn.onOverflow,
    alwaysCenterSingleColumn: true,
    defaultRowHeight: automaticExtent,
    presetRowHeights: @[],
    focusFollowsMouse: false,
  )
