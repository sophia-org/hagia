import ./[core, model, projection]

const
  overviewZoomDivisor* = 2'i64
  overviewGapDivisor* = 10'i32

## Logical overview geometry and navigation remain WM policy. Sophia receives
## only the adapter's generic instance/region records and opaque action ids.
type
  OverviewWorkspace* = object
    output*: OutputId
    view*: ViewId
    bounds*: Rect
    active*: bool
    focus*: WindowId
    placements*: seq[LogicalPlacement]
    navigation*: seq[LogicalPlacement]
    layout*: LayoutMode

  OverviewDirection* {.pure.} = enum
    left
    right
    up
    down

  OverviewPreview* = object
    workspace*: OverviewWorkspace
    geometry*, clip*: Rect
    placements*: seq[LogicalPlacement]
