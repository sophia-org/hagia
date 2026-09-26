import std/[strutils, unittest]
import types/wm_files
import sophia/wm_files

## Bytes below are written from `sophia-wm-files-v1.kdl` (Sophia cade1bae),
## little-endian, field by field; none comes from a Sophia encoder.

proc hex(text: string): seq[byte] =
  for value in text.splitWhitespace():
    result.add(byte(parseHexInt(value)))

template refuses(expected: WmFileErrorKind, body: untyped) =
  ## The body must raise `WmFileError` of this kind, and nothing else: an
  ## overflow or index defect is a failure, not a refusal.
  var raised = false
  try:
    body
  except WmFileError as error:
    raised = true
    check error.kind == expected
  check raised

proc setU16(bytes: var seq[byte], offset: int, value: uint16) =
  bytes[offset] = byte(value and 0xff)
  bytes[offset + 1] = byte(value shr 8)

proc setU32(bytes: var seq[byte], offset: int, value: uint32) =
  for index in 0 ..< 4:
    bytes[offset + index] = byte((value shr (index * 8)) and 0xff)

proc setU64(bytes: var seq[byte], offset: int, value: uint64) =
  for index in 0 ..< 8:
    bytes[offset + index] = byte((value shr (index * 8)) and 0xff)

# Limits object, epoch 7: total 32, version 1, kind 1, submission 0, sequence 0.
const limitsHex =
  "20 00 00 00 01 00 01 00 07 00 00 00 00 00 00 00 " &
  "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
# Dirty candidate (kind 261 = 0x0105), epoch 7, submission 9, body aa bb.
const dirtyHex =
  "22 00 00 00 01 00 05 01 07 00 00 00 00 00 00 00 " &
  "09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 aa bb"
# Cycle event (kind 22 = 0x16), epoch 7, sequence 3, body cc.
const cycleHex =
  "21 00 00 00 01 00 16 00 07 00 00 00 00 00 00 00 " &
  "00 00 00 00 00 00 00 00 03 00 00 00 00 00 00 00 cc"
# Two sections: kind 1, two rows, 4 bytes; kind 3, one row, 2 bytes.
const sectionsHex =
  "01 00 00 00 02 00 00 00 04 00 00 00 00 00 00 00 11 22 33 44 " &
  "03 00 00 00 01 00 00 00 02 00 00 00 00 00 00 00 55 66"
# Submit: epoch 7, submission 9, candidate 34 bytes, reserved 0.
const submitHex =
  "07 00 00 00 00 00 00 00 09 00 00 00 00 00 00 00 22 00 00 00 00 00 00 00"
# Ack: epoch 7, sequence 3.
const ackHex = "07 00 00 00 00 00 00 00 03 00 00 00 00 00 00 00"

const allKinds = [
  WmFileKind.limits, WmFileKind.snapshot, WmFileKind.negotiated, WmFileKind.submitted,
  WmFileKind.profilePrepare, WmFileKind.profileActivate, WmFileKind.profileRollback,
  WmFileKind.configurationOutcome, WmFileKind.cycle, WmFileKind.projectionOutcome,
  WmFileKind.sessionOperationOutcome, WmFileKind.presentationReceipt,
  WmFileKind.negotiate, WmFileKind.profilePrepared, WmFileKind.profileActive,
  WmFileKind.profileRolledBack, WmFileKind.configuration, WmFileKind.dirty,
  WmFileKind.projection, WmFileKind.sessionOperation,
]

proc limitsHeader(): WmFileHeader =
  WmFileHeader(kind: WmFileKind.limits, connectionEpoch: 7)

proc dirtyHeader(): WmFileHeader =
  WmFileHeader(kind: WmFileKind.dirty, connectionEpoch: 7, submissionId: 9)

proc cycleHeader(): WmFileHeader =
  WmFileHeader(kind: WmFileKind.cycle, connectionEpoch: 7, sequence: 3)

proc sections(): seq[WmFileSection] =
  @[
    WmFileSection(kind: 1, count: 2, rows: hex("11 22 33 44")),
    WmFileSection(kind: 3, count: 1, rows: hex("55 66")),
  ]

suite "independent WM file envelope":
  test "each class matches its specified header layout":
    check limitsHeader().encodeRecord([]) == hex(limitsHex)
    check dirtyHeader().encodeRecord([0xaa'u8, 0xbb]) == hex(dirtyHex)
    check cycleHeader().encodeRecord([0xcc'u8]) == hex(cycleHex)
    check hex(limitsHex).decodeRecord(WmFileClass.objectRecord) == limitsHeader()
    let dirty = hex(dirtyHex)
    check dirty.decodeRecord(WmFileClass.candidateRecord) == dirtyHeader()
    check @(dirty.toOpenArray(wmFileHeaderBytes, dirty.high)) == @[0xaa'u8, 0xbb]
    check hex(cycleHex).decodeRecord(WmFileClass.eventRecord) == cycleHeader()

  test "every kind value round trips and every other value is refused":
    for kind in allKinds:
      check fileKind(uint16(ord(kind))) == kind
    var known = 0
    for value in 0 .. int(high(uint16)):
      try:
        discard fileKind(uint16(value))
        inc known
      except WmFileError as error:
        check error.kind == WmFileErrorKind.kind
    check known == allKinds.len

  test "the class of each kind is the schema's":
    for kind in allKinds:
      let expected =
        if ord(kind) <= 2:
          WmFileClass.objectRecord
        elif ord(kind) < 256:
          WmFileClass.eventRecord
        else:
          WmFileClass.candidateRecord
      check kind.class == expected

  test "a record in the wrong file is refused; exact kinds are the caller's":
    for (text, own) in [
      (limitsHex, WmFileClass.objectRecord),
      (dirtyHex, WmFileClass.candidateRecord),
      (cycleHex, WmFileClass.eventRecord),
    ]:
      for expected in WmFileClass:
        if expected != own:
          refuses WmFileErrorKind.class:
            discard hex(text).decodeRecord(expected)
    refuses WmFileErrorKind.kind:
      dirtyHeader().requireKind(WmFileKind.projection)
    dirtyHeader().requireKind(WmFileKind.dirty)

  test "every truncation and inconsistent total length is refused":
    let dirty = hex(dirtyHex)
    for length in 0 ..< dirty.len:
      refuses WmFileErrorKind.length:
        discard dirty[0 ..< length].decodeRecord(WmFileClass.candidateRecord)
    var trailing = dirty
    trailing.add(0)
    refuses WmFileErrorKind.length:
      discard trailing.decodeRecord(WmFileClass.candidateRecord)
    for size in [0'u32, 31, 33, 35, uint32(wmFileMaxBytes) + 1, high(uint32)]:
      var wrong = dirty
      wrong.setU32(0, size)
      refuses WmFileErrorKind.length:
        discard wrong.decodeRecord(WmFileClass.candidateRecord)

  test "version and kind values outside the schema are refused":
    for version in [0'u16, 2, high(uint16)]:
      var wrong = hex(limitsHex)
      wrong.setU16(4, version)
      refuses WmFileErrorKind.version:
        discard wrong.decodeRecord(WmFileClass.objectRecord)
    for kind in [0'u16, 3, 15, 26, 255, 264, high(uint16)]:
      var wrong = hex(limitsHex)
      wrong.setU16(6, kind)
      refuses WmFileErrorKind.kind:
        discard wrong.decodeRecord(WmFileClass.objectRecord)

  test "each class carries exactly its own identities, in both directions":
    # (kind, epoch, submission, sequence) that the class rules refuse.
    let invalid = [
      (WmFileKind.limits, 0'u64, 0'u64, 0'u64),
      (WmFileKind.limits, 7'u64, 1'u64, 0'u64),
      (WmFileKind.limits, 7'u64, 0'u64, 1'u64),
      (WmFileKind.dirty, 7'u64, 0'u64, 0'u64),
      (WmFileKind.dirty, 7'u64, 9'u64, 1'u64),
      (WmFileKind.dirty, 0'u64, 9'u64, 0'u64),
      (WmFileKind.cycle, 7'u64, 0'u64, 0'u64),
      (WmFileKind.cycle, 7'u64, 1'u64, 3'u64),
    ]
    for (kind, epoch, submission, sequence) in invalid:
      refuses WmFileErrorKind.identity:
        discard WmFileHeader(
          kind: kind,
          connectionEpoch: epoch,
          submissionId: submission,
          sequence: sequence,
        ).encodeRecord([])
      var bytes = hex(limitsHex)
      bytes.setU16(6, uint16(ord(kind)))
      bytes.setU64(8, epoch)
      bytes.setU64(16, submission)
      bytes.setU64(24, sequence)
      refuses WmFileErrorKind.identity:
        discard bytes.decodeRecord(kind.class)

  test "exactly one mebibyte is a record and one byte more is not":
    let body = newSeq[byte](wmFileMaxBytes - wmFileHeaderBytes)
    let largest = limitsHeader().encodeRecord(body)
    check largest.len == wmFileMaxBytes
    check largest.decodeRecord(WmFileClass.objectRecord) == limitsHeader()
    refuses WmFileErrorKind.length:
      discard limitsHeader().encodeRecord(newSeq[byte](body.len + 1))
    var tooLarge = largest
    tooLarge.add(0)
    tooLarge.setU32(0, uint32(tooLarge.len))
    refuses WmFileErrorKind.length:
      discard tooLarge.decodeRecord(WmFileClass.objectRecord)

suite "independent WM file sections":
  test "sections match their specified layout and decode as views":
    let bytes = hex(sectionsHex)
    check sections().encodeSections() == bytes
    let views = bytes.decodeSections(2)
    check views ==
      @[
        WmFileSectionView(kind: 1, count: 2, offset: 16, length: 4),
        WmFileSectionView(kind: 3, count: 1, offset: 36, length: 2),
      ]
    check @(bytes.toOpenArray(views[1].offset, views[1].offset + views[1].length - 1)) ==
      hex("55 66")
    check decodeSections(newSeq[byte](), 0).len == 0
    check encodeSections(newSeq[WmFileSection]()).len == 0

  test "count, order and reserved fields are the envelope's":
    let bytes = hex(sectionsHex)
    refuses WmFileErrorKind.sections:
      discard bytes.decodeSections(33)
    refuses WmFileErrorKind.length:
      discard bytes.decodeSections(1)
    refuses WmFileErrorKind.length:
      discard bytes.decodeSections(0)
    refuses WmFileErrorKind.length:
      discard bytes.decodeSections(3)
    for (offset, value, expected) in [
      (0, 0'u16, WmFileErrorKind.sections), # kind zero
      (20, 1'u16, WmFileErrorKind.sections), # equal kinds
      (20, 0'u16, WmFileErrorKind.sections), # descending
      (2, 1'u16, WmFileErrorKind.reserved), # reserved after kind
      (34, 1'u16, WmFileErrorKind.reserved), # reserved tail, second section
    ]:
      var wrong = bytes
      wrong.setU16(offset, value)
      refuses expected:
        discard wrong.decodeSections(2)

  test "row counts and lengths cannot exceed or misstate the block":
    let bytes = hex(sectionsHex)
    for (offset, value) in [
      (4, 0'u32), # zero rows
      (8, 0'u32), # zero length
      (8, 23'u32), # first length runs past the block
      (28, 3'u32), # last length runs past the block
      (28, high(uint32)), # would overflow if added
    ]:
      var wrong = bytes
      wrong.setU32(offset, value)
      refuses WmFileErrorKind.length:
        discard wrong.decodeSections(2)
    for length in 0 ..< bytes.len:
      if length != 20:
        refuses WmFileErrorKind.length:
          discard bytes[0 ..< length].decodeSections(if length < 20: 1 else: 2)
    var trailing = bytes
    trailing.add(0)
    refuses WmFileErrorKind.length:
      discard trailing.decodeSections(2)
    let tooLarge = newSeq[byte](wmFileMaxBytes + 1)
    refuses WmFileErrorKind.sections:
      discard tooLarge.decodeSections(1)

  test "the encoder refuses what the decoder refuses":
    var many: seq[WmFileSection]
    for kind in 1'u16 .. 33'u16:
      many.add(WmFileSection(kind: kind, count: 1, rows: @[0'u8]))
    refuses WmFileErrorKind.sections:
      discard many.encodeSections()
    for wrong in [
      @[sections()[1], sections()[0]],
      @[sections()[0], sections()[0]],
      @[WmFileSection(kind: 0, count: 1, rows: @[0'u8])],
      @[WmFileSection(kind: 1, count: 0, rows: @[0'u8])],
      @[WmFileSection(kind: 1, count: 1, rows: @[])],
    ]:
      refuses WmFileErrorKind.sections:
        discard wrong.encodeSections()
    let whole = WmFileSection(
      kind: 1, count: 1, rows: newSeq[byte](wmFileMaxBytes - wmFileSectionHeaderBytes)
    )
    check @[whole].encodeSections().len == wmFileMaxBytes
    refuses WmFileErrorKind.length:
      discard
        @[WmFileSection(kind: 1, count: 1, rows: whole.rows & @[0'u8])].encodeSections()

suite "independent WM file submit and ack":
  test "submit and ack match their specified layouts":
    let submit = WmFileSubmit(connectionEpoch: 7, submissionId: 9, candidateBytes: 34)
    check submit.encodeSubmit() == hex(submitHex)
    check hex(submitHex).decodeSubmit() == submit
    let ack = WmFileAck(connectionEpoch: 7, sequence: 3)
    check ack.encodeAck() == hex(ackHex)
    check hex(ackHex).decodeAck() == ack

  test "submit refuses wrong length, reserved bytes, null identity and impossible candidates":
    let bytes = hex(submitHex)
    for length in [0, 23, 25]:
      var wrong = bytes
      wrong.setLen(length)
      refuses WmFileErrorKind.length:
        discard wrong.decodeSubmit()
    var reserved = bytes
    reserved.setU32(20, 1)
    refuses WmFileErrorKind.reserved:
      discard reserved.decodeSubmit()
    for offset in [0, 8]:
      var null = bytes
      null.setU64(offset, 0)
      refuses WmFileErrorKind.identity:
        discard null.decodeSubmit()
    for candidate in [0'u32, 31, uint32(wmFileMaxBytes) + 1, high(uint32)]:
      var wrong = bytes
      wrong.setU32(16, candidate)
      refuses WmFileErrorKind.length:
        discard wrong.decodeSubmit()
      refuses WmFileErrorKind.length:
        discard WmFileSubmit(
          connectionEpoch: 7, submissionId: 9, candidateBytes: candidate
        ).encodeSubmit()
    for candidate in [32'u32, uint32(wmFileMaxBytes)]:
      var edge = bytes
      edge.setU32(16, candidate)
      check edge.decodeSubmit().candidateBytes == candidate
    refuses WmFileErrorKind.identity:
      discard WmFileSubmit(connectionEpoch: 0, submissionId: 9, candidateBytes: 34).encodeSubmit()
    refuses WmFileErrorKind.identity:
      discard WmFileSubmit(connectionEpoch: 7, submissionId: 0, candidateBytes: 34).encodeSubmit()

  test "ack refuses wrong length and null identity":
    let bytes = hex(ackHex)
    for length in [0, 15, 17]:
      var wrong = bytes
      wrong.setLen(length)
      refuses WmFileErrorKind.length:
        discard wrong.decodeAck()
    for offset in [0, 8]:
      var null = bytes
      null.setU64(offset, 0)
      refuses WmFileErrorKind.identity:
        discard null.decodeAck()
    refuses WmFileErrorKind.identity:
      discard WmFileAck(connectionEpoch: 7, sequence: 0).encodeAck()
