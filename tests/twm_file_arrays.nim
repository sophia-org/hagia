import std/unittest

import types/[wm_v1, wm_files, wm_file_arrays]
import sophia/[wm_files, wm_file_arrays]

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

proc sections(extensions = true): seq[WmFileSection] =
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

proc snapshotBytes(rows: seq[WmFileSection], active = 7'u64): seq[byte] =
  var body: seq[byte]
  body.addU64(13)
  body.addU64(19)
  body.addU64(active)
  body.addU16(uint16(rows.len))
  body.add(newSeq[byte](6))
  body.add(rows.encodeSections())
  WmFileHeader(kind: WmFileKind.snapshot, connectionEpoch: 7).encodeRecord(body)

suite "complete WM file snapshot arrays":
  test "all sections preserve opaque identities and accept surface index zero":
    let value = sections().snapshotBytes().decodeFileSnapshot(7, high(uint64))
    check value.transaction == 13
    check value.snapshot.generation == 19
    check value.snapshot.outputs.len == 1
    check value.snapshot.outputs[0].focusIndex == 0
    check value.snapshot.outputs[0].focusGeneration == 1
    check value.snapshot.outputs[0].policyKey == 55
    check value.snapshot.surfaces[0].surfaceIndex == 0
    check value.snapshot.actions[0].name == "x"
    check value.snapshot.sessionOperations[0].operation == 12
    check value.snapshot.classifications[0].classification == 3
    check value.snapshot.launchOrigins[0].token == 77

  test "each unselected extension is refused before row conversion":
    let bytes = sections().snapshotBytes()
    for bit in [
      capabilityActions, capabilitySessionOperations, capabilityLaunchPlacement,
      capabilityLaunchOrigin, capabilityOutputPolicyKeys,
    ]:
      expect WmFileError:
        discard bytes.decodeFileSnapshot(7, high(uint64) xor bit)
    discard sections(false).snapshotBytes().decodeFileSnapshot(7, 0)

  test "peer counts and widths are bounded before row allocation":
    var rows = sections(false)
    rows[0].count = high(uint32)
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = sections(false)
    rows[0].rows.setLen(snapshotOutputSize - 1)
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = @[sections(false)[1]]
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "fragmented prefixes and section tails are never complete snapshots":
    let bytes = sections().snapshotBytes()
    for size in wmFileHeaderBytes ..< bytes.len:
      var prefix = bytes[0 ..< size]
      for index in 0 ..< 4:
        prefix[index] = byte((uint32(size) shr (index * 8)) and 255)
      expect WmFileError:
        discard prefix.decodeFileSnapshot(7, high(uint64))
    var reserved = bytes
    reserved[wmFileHeaderBytes + 26] = 1
    expect WmFileError:
      discard reserved.decodeFileSnapshot(7, high(uint64))

  test "epoch active output and launch membership are checked independently":
    expect WmFileError:
      discard sections().snapshotBytes().decodeFileSnapshot(8, high(uint64))
    expect WmFileError:
      discard sections().snapshotBytes(8).decodeFileSnapshot(7, high(uint64))
    var rows = sections()
    rows[5].rows[0] = 9
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = sections()
    rows[5].rows[8] = 8
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "output policy keys cannot name another generation or repeat":
    var rows = sections()
    rows[6].rows[8] = 2
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = sections()
    rows[6].rows.add(rows[6].rows)
    rows[6].count = 2
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "surface and operation bitfields refuse unknown bits":
    var rows = sections()
    rows[1].rows[25] = 128
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = sections()
    rows[3].rows[10] = 2
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
