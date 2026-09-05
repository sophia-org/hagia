import ./core

type
  TabTreeMode* {.pure.} = enum
    leaf
    horizontal
    vertical
    tabbed
    stacking

  TabTreePreselect* {.pure.} = enum
    none
    left
    right
    up
    down

  TabTreeNode* = object
    id*, parent*: uint32
    pendingSplit*: bool
    mode*, lastSplit*: TabTreeMode
    preselect*: TabTreePreselect
    weight*: Scale
    children*: seq[uint32]
    windows*: seq[WindowId]
    active*: WindowId
    selectedChild*: uint32

  TabTree* = object
    nodes*: seq[TabTreeNode]
    root*, focused*, nextId*: uint32
    frameStyle*: bool

  TabTreeDto* = object
    view*: uint32
    tree*: TabTree

  TabTreeCommand* {.pure.} = enum
    splitHorizontal
    splitVertical
    splitToggle
    unsplit
    layoutHorizontal
    layoutVertical
    layoutTabbed
    layoutStacking
    toggleSplit
    cycleAll
    focusParent
    focusChild
    nextTab
    previousTab
    nextSibling
    previousSibling
    focusLeft
    focusRight
    focusUp
    focusDown
    moveLeft
    moveRight
    moveUp
    moveDown
    resizeLeft
    resizeRight
    resizeUp
    resizeDown
    group
    ungroup
    preselectLeft
    preselectRight
    preselectUp
    preselectDown

  TabTreePlacement* = object
    window*: WindowId
    geometry*: Rect

  TabTreeGroup* = object
    id*: uint64
    geometry*: Rect
    focused*: bool
    selected*: WindowId
    members*: seq[WindowId]

  TabTreeProjection* = object
    placements*: seq[TabTreePlacement]
    groups*: seq[TabTreeGroup]

const
  maxTabTreeNodes* = 2048
  maxTabTreeDepth* = 64
  tabStripHeight* = 24'i32
