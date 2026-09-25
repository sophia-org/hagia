import ./[core, projection]

## Workspace previews are spatial facts. Pixel sources and thumbnail scaling
## remain with Sophia; shell selection uses broker-local slots.
type
  OverviewWorkspace* = object
    output*: OutputId
    view*: ViewId
    bounds*: Rect
    active*: bool
    focus*: WindowId
    placements*: seq[LogicalPlacement]

  OverviewSelection* = object
    output*: OutputId
    view*: ViewId
    window*: WindowId ## Null selects the workspace, including an empty one.
