import std/strutils
import std/unittest

import types/wm_v1
import ./support/wire/types/wm_files
import ./support/wire/types/wm_file_arrays
import ./support/wire/sophia/wm_files
import ./support/wire/sophia/wm_file_arrays

import support/wm_file_snapshot_fixture

suite "complete WM file snapshot arrays":
  test "all sections preserve opaque identities and accept surface index zero":
    let value = snapshotSections().snapshotBytes().decodeFileSnapshot(7, high(uint64))
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
    let bytes = snapshotSections().snapshotBytes()
    for bit in [
      capabilityActions, capabilitySessionOperations, capabilityLaunchPlacement,
      capabilityLaunchOrigin, capabilityOutputPolicyKeys,
    ]:
      expect WmFileError:
        discard bytes.decodeFileSnapshot(7, high(uint64) xor bit)
    discard snapshotSections(false).snapshotBytes().decodeFileSnapshot(7, 0)

  test "peer counts and widths are bounded before row allocation":
    var rows = snapshotSections(false)
    rows[0].count = high(uint32)
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = snapshotSections(false)
    rows[0].rows.setLen(snapshotOutputSize - 1)
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = @[snapshotSections(false)[1]]
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "fragmented prefixes and section tails are never complete snapshots":
    let bytes = snapshotSections().snapshotBytes()
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
      discard snapshotSections().snapshotBytes().decodeFileSnapshot(8, high(uint64))
    expect WmFileError:
      discard snapshotSections().snapshotBytes(8).decodeFileSnapshot(7, high(uint64))
    var rows = snapshotSections()
    rows[5].rows[0] = 9
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = snapshotSections()
    rows[5].rows[8] = 8
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "output policy keys cannot name another generation or repeat":
    var rows = snapshotSections()
    rows[6].rows[8] = 2
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = snapshotSections()
    rows[6].rows.add(rows[6].rows)
    rows[6].count = 2
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "surface and operation bitfields refuse unknown bits":
    var rows = snapshotSections()
    rows[1].rows[25] = 128
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
    rows = snapshotSections()
    rows[3].rows[10] = 2
    expect WmFileError:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))

  test "row diagnostics preserve the rule and distinguish counts from lengths":
    try:
      discard snapshotSections().snapshotBytes(8).decodeFileSnapshot(7, high(uint64))
      check false
    except WmFileError as error:
      check error.kind == WmFileErrorKind.value
      check "active output" in error.msg
    var rows = snapshotSections(false)
    rows[0].count = high(uint32)
    try:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
      check false
    except WmFileError as error:
      check error.kind == WmFileErrorKind.value
    rows = snapshotSections(false)
    rows[0].rows.setLen(snapshotOutputSize - 1)
    try:
      discard rows.snapshotBytes().decodeFileSnapshot(7, high(uint64))
      check false
    except WmFileError as error:
      check error.kind == WmFileErrorKind.length

proc configuration(): WmFileConfiguration =
  WmFileConfiguration(
    transaction: 13,
    connectionEpoch: 7,
    generation: 19,
    styleBits: 2,
    frameWidth: 1,
    focusRgb: 0x123456,
    frameFocusedRgb: 0xabcdef,
    frameUnfocusedRgb: 0x987654,
    actions: @[SnapshotAction(action: 11, sessionOperationSlot: 1, name: "x")],
  )

proc candidate(): WmFileHeader =
  WmFileHeader(kind: WmFileKind.configuration, connectionEpoch: 7, submissionId: 23)

suite "complete WM file configuration arrays":
  test "prefix and action row match the published layout":
    var body: seq[byte]
    body.addU64(13)
    body.addU64(19)
    body.addU16(2)
    body.addU16(1)
    for value in [0'u32, 0x123456, 1, 0xabcdef, 0x987654]:
      body.addU32(value)
    body.addU64(0)
    body.add(@[snapshotSections()[2]].encodeSections())
    check candidate().encodeFileConfiguration(configuration(), high(uint64)) ==
      candidate().encodeRecord(body)

  test "empty actions and disabled chrome need only configuration":
    let value = WmFileConfiguration(transaction: 1, connectionEpoch: 7, generation: 1)
    let bytes = candidate().encodeFileConfiguration(value, capabilityConfiguration)
    check bytes.len == wmFileHeaderBytes + wmFileConfigurationPrefixBytes
    check bytes.readU16(wmFileHeaderBytes + 18) == 0

  test "each populated component requires its selected capability":
    for bit in [capabilityConfiguration, capabilityChrome, capabilityActions]:
      expect WmFileError:
        discard
          candidate().encodeFileConfiguration(configuration(), high(uint64) xor bit)

  test "wrong direction epoch and null semantic identity are refused":
    var header = candidate()
    header.kind = WmFileKind.snapshot
    expect WmFileError:
      discard header.encodeFileConfiguration(configuration(), high(uint64))
    var value = configuration()
    value.connectionEpoch = 8
    expect WmFileError:
      discard candidate().encodeFileConfiguration(value, high(uint64))
    value = configuration()
    value.transaction = 0
    expect WmFileError:
      discard candidate().encodeFileConfiguration(value, high(uint64))

  test "file RGB and chrome widths are strict":
    for color in [0xff123456'u32, high(uint32)]:
      var value = configuration()
      value.focusRgb = color
      expect WmFileError:
        discard candidate().encodeFileConfiguration(value, high(uint64))
    for width in [0'u32, wmFileChromeMaxWidth + 1, high(uint32)]:
      var value = configuration()
      value.frameWidth = width
      expect WmFileError:
        discard candidate().encodeFileConfiguration(value, high(uint64))
    var value = configuration()
    value.styleBits = 0
    expect WmFileError:
      discard candidate().encodeFileConfiguration(value, high(uint64))

  test "action bounds names and uniqueness are checked":
    var value = configuration()
    value.actions.setLen(maxBindings + 1)
    expect WmFileError:
      discard candidate().encodeFileConfiguration(value, high(uint64))
    for name in ["", "bad/name", repeat("x", maxActionNameBytes + 1)]:
      value = configuration()
      value.actions[0].name = name
      expect WmFileError:
        discard candidate().encodeFileConfiguration(value, high(uint64))
    value = configuration()
    value.actions.add(value.actions[0])
    expect WmFileError:
      discard candidate().encodeFileConfiguration(value, high(uint64))
    value.actions[1].action = 12
    expect WmFileError:
      discard candidate().encodeFileConfiguration(value, high(uint64))
