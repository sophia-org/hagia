import ./core
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
