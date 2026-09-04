import ../types/[core, model, wm_v1]
import ../entities/window_ops

## Conversion from Sophia's wire snapshot records into Hagia's passive policy
## records, plus the refusal the whole adapter path shares. Nothing here holds
## adapter state, so a caller can convert one surface without a reconciliation.

type PolicyAdapterError* = object of CatchableError

proc fail(message: string) {.noreturn.} =
  raise newException(PolicyAdapterError, message)

proc surfaceKey*(index, generation: uint32): uint64 =
  uint64(index) or (uint64(generation) shl 32)

proc surfaceKey*(surface: SnapshotSurface): uint64 =
  surfaceKey(surface.surfaceIndex, surface.surfaceGeneration)

proc capabilities*(bits: uint16): WindowCapabilities =
  WindowCapabilities(
    movable: (bits and (1'u16 shl 0)) != 0,
    resizable: (bits and (1'u16 shl 1)) != 0,
    focusable: (bits and (1'u16 shl 2)) != 0,
    closable: (bits and (1'u16 shl 3)) != 0,
    fullscreenable: (bits and (1'u16 shl 4)) != 0,
  )

proc windowKind*(raw: uint16): WindowKind =
  case raw
  of 1:
    WindowKind.toplevel
  of 2:
    WindowKind.dialog
  of 3:
    WindowKind.utility
  of 4:
    WindowKind.popup
  of 5, 0:
    WindowKind.unknown
  else:
    fail("surface kind is invalid")

proc applyPresentation*(model: var PolicyModel, window: WindowId, bits: uint16) =
  model.setWindowPresentation(
    window,
    (bits and (1'u16 shl 0)) != 0,
    (bits and (1'u16 shl 1)) != 0,
    (bits and (1'u16 shl 2)) != 0,
  )

proc constraints*(surface: SnapshotSurface): SizeConstraints =
  SizeConstraints(
    minWidth: surface.minWidth,
    minHeight: surface.minHeight,
    maxWidth: surface.maxWidth,
    maxHeight: surface.maxHeight,
  )

proc bounds*(output: SnapshotOutput): Rect =
  ## Layout uses Engine's bounded work rectangle; panels and other reserved
  ## shell regions never become private Hagia policy.
  if output.workWidth > 0 and output.workHeight > 0:
    Rect(
      x: output.workX,
      y: output.workY,
      width: output.workWidth,
      height: output.workHeight,
    )
  else:
    # Unit-level policy fixtures may construct semantic records directly. The
    # live wire validator requires a positive work rectangle before this layer.
    Rect(x: output.x, y: output.y, width: output.width, height: output.height)

proc handle*(output: SnapshotOutput): OutputHandle =
  (output: output.output, generation: output.generation)

proc constrainedExtent*(extent, minimum, maximum, exact: int32): int32 =
  if exact > 0:
    return exact
  result = extent
  if minimum > 0:
    result = max(result, minimum)
  if maximum > 0:
    result = min(result, maximum)

proc idOrder*[T](left, right: T): int =
  cmp(uint32(left.id), uint32(right.id))
