## Literal file-cycle bodies for independent decoder controls. The envelope
## uses the public codec; the fixed body offsets do not use encodeCycle.
import ./wire/types/wm_files
import ./wire/sophia/wm_files

proc cycleRecord*(
    epoch: uint64,
    kind: uint16,
    cause: openArray[byte],
    affected: openArray[uint64] = [10'u64],
): seq[byte] =
  var body: seq[byte]
  for value in [1'u64, 2, 3, 4, 5]:
    body.addU64(value)
  body.addU16(kind)
  body.addU16(uint16(affected.len))
  body.addU32(0)
  for output in affected:
    body.addU64(output)
  body.add(cause)
  WmFileHeader(kind: WmFileKind.cycle, connectionEpoch: epoch, sequence: 1).encodeRecord(
    body
  )

proc interactionRecord*(
    phase, kind, axis: uint16, x, y, width, height: int32
): seq[byte] =
  var cause: seq[byte]
  for value in [phase, kind, axis, 0'u16]:
    cause.addU16(value)
  cause.addU32(1)
  cause.addU32(1)
  for value in [x, y, width, height]:
    cause.addU32(cast[uint32](value))
  cycleRecord(7, 4, cause)
