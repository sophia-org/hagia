import ./wire/types/wm_files
import types/wm_v1
import ./wire/sophia/wm_files

# Fixed rows are assembled from the published layout, not a snapshot encoder.
proc outputRow(): seq[byte] =
  result.addU64(7)
  result.addU64(1)
  result.addU32(0)
  result.addU32(1)
  for value in [0'i32, 0, 640, 480, 0, 0, 640, 480]:
    result.addI32(value)

proc surfaceRow(): seq[byte] =
  result.addU32(0)
  result.addU32(1)
  result.addU64(1)
  result.addU64(7)
  for value in [surfaceFocusable, 1'u16, 0, 0]:
    result.addU16(value)
  result.addU32(0)
  result.addU32(0)
  for value in [0'i32, 0, 320, 240, 0, 0, 0, 0, 0, 0]:
    result.addI32(value)

proc snapshotSections*(extensions = true): seq[WmFileSection] =
  result = @[
    WmFileSection(kind: 1, count: 1, rows: outputRow()),
    WmFileSection(kind: 2, count: 1, rows: surfaceRow()),
  ]
  if not extensions:
    return
  var action: seq[byte]
  action.addU64(11)
  action.addU16(1)
  action.addU16(1)
  action.add(byte('x'))
  action.add(newSeq[byte](127))
  result.add(WmFileSection(kind: 3, count: 1, rows: action))
  var operation: seq[byte]
  operation.addU64(12)
  operation.addU16(1)
  operation.addU16(1)
  result.add(WmFileSection(kind: 4, count: 1, rows: operation))
  var classification: seq[byte]
  classification.addU32(0)
  classification.addU32(1)
  classification.addU64(3)
  result.add(WmFileSection(kind: 0xff00, count: 1, rows: classification))
  var origin: seq[byte]
  origin.addU32(0)
  origin.addU32(1)
  origin.addU64(7)
  origin.addU64(77)
  result.add(WmFileSection(kind: 0xff06, count: 1, rows: origin))
  var key: seq[byte]
  key.addU64(7)
  key.addU64(1)
  key.addU64(55)
  result.add(WmFileSection(kind: 0xff07, count: 1, rows: key))

proc snapshotBytes*(rows: seq[WmFileSection], active = 7'u64): seq[byte] =
  var body: seq[byte]
  body.addU64(13)
  body.addU64(19)
  body.addU64(active)
  body.addU16(uint16(rows.len))
  body.add(newSeq[byte](6))
  body.add(rows.encodeSections())
  WmFileHeader(kind: WmFileKind.snapshot, connectionEpoch: 7).encodeRecord(body)
