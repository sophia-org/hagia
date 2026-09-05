import ./core
import ./model
import ./tab_tree

## Deterministic geometry results. Projection builders in
## `src/policy/projection.nim` read a valid model and return these records
## without mutating state or performing I/O.

type
  LogicalPlacement* = object
    window*: WindowId
    geometry*: Rect
    requestedWidth*, requestedHeight*: int32

  LogicalOutputProjection* = object
    tabGroups*: seq[TabTreeGroup]
    output*: OutputId
    placements*: seq[LogicalPlacement]
    focus*: WindowId
    viewportOffset*: int32
    ## Whether this projection decided where the camera sits. Only a scroller
    ## does. Without this the field's zero default reads as "scrolled to the
    ## origin", so every tile, grid, monocle or tabbed projection quietly
    ## reset the view a scroller had been left at, and switching layout and
    ## back lost the scroll position.
    cameraDecided*: bool
    camera*: CameraAnchor
