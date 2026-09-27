import ../types/wm_files

## Independent codec for the Sophia WM file envelope, written from
## `sophia-wm-files-v1.kdl`. It owns byte shape only: the common header and
## its class identity rules, complete row sections, and the submit and ack
## control records. Row grammar, domain values, admission and settlement stay
## with the typed body codec and its owners. Encoders refuse exactly what the
## decoders refuse, so Hagia never emits a record Sophia must reject.

type
  WmFileErrorKind* {.pure.} = enum
    length
    version
    kind
    class
    identity
    reserved
    sections
    ## A body field outside its schema range or fixed value.
    value
    ## A body the connection did not negotiate.
    capability
    ## A record for another connection epoch than the admitted one.
    epoch

  WmFileError* = object of CatchableError
    kind*: WmFileErrorKind

proc failWmFile*(kind: WmFileErrorKind, message: string) {.noreturn.} =
  var error = newException(WmFileError, message)
  error.kind = kind
  raise error

proc requireBytes(bytes: openArray[byte], offset, count: int) =
  if offset < 0 or offset > bytes.len or count > bytes.len - offset:
    failWmFile(WmFileErrorKind.length, "truncated WM file field")

proc readU16*(bytes: openArray[byte], offset: int): uint16 =
  bytes.requireBytes(offset, 2)
  uint16(bytes[offset]) or (uint16(bytes[offset + 1]) shl 8)

proc readU32*(bytes: openArray[byte], offset: int): uint32 =
  bytes.requireBytes(offset, 4)
  for index in 0 ..< 4:
    result = result or (uint32(bytes[offset + index]) shl (index * 8))

proc readU64*(bytes: openArray[byte], offset: int): uint64 =
  bytes.requireBytes(offset, 8)
  for index in 0 ..< 8:
    result = result or (uint64(bytes[offset + index]) shl (index * 8))

proc readI32*(bytes: openArray[byte], offset: int): int32 =
  cast[int32](bytes.readU32(offset))

proc addU16*(bytes: var seq[byte], value: uint16) =
  for index in 0 ..< 2:
    bytes.add(byte((value shr (index * 8)) and 0xff))

proc addU32*(bytes: var seq[byte], value: uint32) =
  for index in 0 ..< 4:
    bytes.add(byte((value shr (index * 8)) and 0xff))

proc addU64*(bytes: var seq[byte], value: uint64) =
  for index in 0 ..< 8:
    bytes.add(byte((value shr (index * 8)) and 0xff))

proc addI32*(bytes: var seq[byte], value: int32) =
  bytes.addU32(cast[uint32](value))

proc fileKind*(value: uint16): WmFileKind =
  ## Only the kinds the schema names; no cast from an arbitrary number.
  case value
  of 1:
    result = WmFileKind.limits
  of 2:
    result = WmFileKind.snapshot
  of 16:
    result = WmFileKind.negotiated
  of 17:
    result = WmFileKind.submitted
  of 18:
    result = WmFileKind.profilePrepare
  of 19:
    result = WmFileKind.profileActivate
  of 20:
    result = WmFileKind.profileRollback
  of 21:
    result = WmFileKind.configurationOutcome
  of 22:
    result = WmFileKind.cycle
  of 23:
    result = WmFileKind.projectionOutcome
  of 24:
    result = WmFileKind.sessionOperationOutcome
  of 25:
    result = WmFileKind.presentationReceipt
  of 256:
    result = WmFileKind.negotiate
  of 257:
    result = WmFileKind.profilePrepared
  of 258:
    result = WmFileKind.profileActive
  of 259:
    result = WmFileKind.profileRolledBack
  of 260:
    result = WmFileKind.configuration
  of 261:
    result = WmFileKind.dirty
  of 262:
    result = WmFileKind.projection
  of 263:
    result = WmFileKind.sessionOperation
  else:
    failWmFile(WmFileErrorKind.kind, "unknown WM file kind")

proc class*(kind: WmFileKind): WmFileClass =
  case kind
  of WmFileKind.limits, WmFileKind.snapshot:
    WmFileClass.objectRecord
  of WmFileKind.negotiated, WmFileKind.submitted, WmFileKind.profilePrepare,
      WmFileKind.profileActivate, WmFileKind.profileRollback,
      WmFileKind.configurationOutcome, WmFileKind.cycle, WmFileKind.projectionOutcome,
      WmFileKind.sessionOperationOutcome, WmFileKind.presentationReceipt:
    WmFileClass.eventRecord
  of WmFileKind.negotiate, WmFileKind.profilePrepared, WmFileKind.profileActive,
      WmFileKind.profileRolledBack, WmFileKind.configuration, WmFileKind.dirty,
      WmFileKind.projection, WmFileKind.sessionOperation:
    WmFileClass.candidateRecord

proc validateHeader*(header: WmFileHeader) =
  ## Objects carry neither identity, candidates only their submission, and
  ## events only their journal sequence. Every record names its epoch.
  let valid =
    header.connectionEpoch != 0 and (
      case header.kind.class
      of WmFileClass.objectRecord:
        header.submissionId == 0 and header.sequence == 0
      of WmFileClass.candidateRecord:
        header.submissionId != 0 and header.sequence == 0
      of WmFileClass.eventRecord:
        header.submissionId == 0 and header.sequence != 0
    )
  if not valid:
    failWmFile(
      WmFileErrorKind.identity, "WM file header identity is invalid for its class"
    )

proc requireKind*(header: WmFileHeader, kind: WmFileKind) =
  ## A class check admits every kind of that class; a body codec names the
  ## exact kind it can decode.
  if header.kind != kind:
    failWmFile(WmFileErrorKind.kind, "WM file record is not the expected kind")

proc encodeRecord*(header: WmFileHeader, body: openArray[byte]): seq[byte] =
  header.validateHeader()
  if body.len > wmFileMaxBytes - wmFileHeaderBytes:
    failWmFile(WmFileErrorKind.length, "WM file record exceeds its bound")
  let size = wmFileHeaderBytes + body.len
  result = newSeqOfCap[byte](size)
  result.addU32(uint32(size))
  result.addU16(wmFileApiVersion)
  result.addU16(uint16(ord(header.kind)))
  result.addU64(header.connectionEpoch)
  result.addU64(header.submissionId)
  result.addU64(header.sequence)
  result.add(body)

proc decodeRecord*(bytes: openArray[byte], expected: WmFileClass): WmFileHeader =
  ## The caller keeps `bytes` and reads the body through
  ## `bytes.toOpenArray(wmFileHeaderBytes, bytes.high)`; a `bytes[a .. b]`
  ## slice would copy it. Fragment assembly and admitted-epoch matching belong
  ## to the file owner.
  # Compared as uint32: the length is already within 1 MiB, and converting the
  # peer's value first could fail a range check on a 32-bit target.
  if bytes.len < wmFileHeaderBytes or bytes.len > wmFileMaxBytes or
      bytes.readU32(0) != uint32(bytes.len):
    failWmFile(WmFileErrorKind.length, "WM file record length is inconsistent")
  if bytes.readU16(4) != wmFileApiVersion:
    failWmFile(WmFileErrorKind.version, "unsupported WM file version")
  result = WmFileHeader(
    kind: fileKind(bytes.readU16(6)),
    connectionEpoch: bytes.readU64(8),
    submissionId: bytes.readU64(16),
    sequence: bytes.readU64(24),
  )
  result.validateHeader()
  if result.kind.class != expected:
    failWmFile(WmFileErrorKind.class, "WM file record is in the wrong file")

proc encodeSections*(sections: openArray[WmFileSection]): seq[byte] =
  if sections.len > wmFileMaxSections:
    failWmFile(WmFileErrorKind.sections, "too many WM file sections")
  var total = 0
  var previous = 0'u16
  for section in sections:
    if section.kind <= previous or section.count == 0 or section.rows.len == 0:
      failWmFile(WmFileErrorKind.sections, "WM file sections are empty or out of order")
    if section.rows.len > wmFileMaxBytes - wmFileSectionHeaderBytes - total:
      failWmFile(WmFileErrorKind.length, "WM file sections exceed their bound")
    total += wmFileSectionHeaderBytes + section.rows.len
    previous = section.kind
  result = newSeqOfCap[byte](total)
  for section in sections:
    result.addU16(section.kind)
    result.addU16(0)
    result.addU32(section.count)
    result.addU32(uint32(section.rows.len))
    result.addU32(0)
    result.add(section.rows)

proc decodeSections*(bytes: openArray[byte], count: uint16): seq[WmFileSectionView] =
  ## Checks the envelope only: counts, order, reserved fields and lengths. It
  ## never interprets rows. Every byte of the block belongs to a section. A
  ## view's rows are `bytes.toOpenArray(view.offset, view.offset + view.length - 1)`
  ## of the block the caller passed and still holds; nothing is copied.
  ## Every length is compared by subtraction from what remains, so a malformed
  ## count or size raises `WmFileError`, never an overflow or index defect.
  let expected = int(count)
  if expected > wmFileMaxSections or bytes.len > wmFileMaxBytes:
    failWmFile(WmFileErrorKind.sections, "too many WM file sections")
  result = newSeqOfCap[WmFileSectionView](expected)
  var offset = 0
  var previous = 0'u16
  for _ in 0 ..< expected:
    if bytes.len - offset < wmFileSectionHeaderBytes:
      failWmFile(WmFileErrorKind.length, "truncated WM file section header")
    let kind = bytes.readU16(offset)
    if kind <= previous:
      failWmFile(WmFileErrorKind.sections, "WM file section kinds are not ascending")
    if bytes.readU16(offset + 2) != 0 or bytes.readU32(offset + 12) != 0:
      failWmFile(WmFileErrorKind.reserved, "WM file section reserved field is nonzero")
    let rows = bytes.readU32(offset + 4)
    let rawSize = bytes.readU32(offset + 8)
    let remaining = bytes.len - offset - wmFileSectionHeaderBytes
    # The peer's size is bounded by what remains (at most 1 MiB) before it is
    # converted, so a 32-bit target raises WmFileError, not a range defect.
    if rows == 0 or rawSize == 0 or rawSize > uint32(remaining):
      failWmFile(WmFileErrorKind.length, "WM file section length is inconsistent")
    let size = int(rawSize)
    result.add(
      WmFileSectionView(
        kind: kind, count: rows, offset: offset + wmFileSectionHeaderBytes, length: size
      )
    )
    offset += wmFileSectionHeaderBytes + size
    previous = kind
  if offset != bytes.len:
    failWmFile(WmFileErrorKind.length, "trailing bytes after WM file sections")

proc validateSubmit(submit: WmFileSubmit) =
  if submit.connectionEpoch == 0 or submit.submissionId == 0:
    failWmFile(WmFileErrorKind.identity, "WM file submit identity is null")
  if submit.candidateBytes < uint32(wmFileHeaderBytes) or
      submit.candidateBytes > uint32(wmFileMaxBytes):
    failWmFile(WmFileErrorKind.length, "WM file submit names an impossible candidate")

proc encodeSubmit*(submit: WmFileSubmit): seq[byte] =
  submit.validateSubmit()
  result = newSeqOfCap[byte](wmFileSubmitBytes)
  result.addU64(submit.connectionEpoch)
  result.addU64(submit.submissionId)
  result.addU32(submit.candidateBytes)
  result.addU32(0)

proc decodeSubmit*(bytes: openArray[byte]): WmFileSubmit =
  if bytes.len != wmFileSubmitBytes:
    failWmFile(WmFileErrorKind.length, "WM file submit has the wrong length")
  if bytes.readU32(20) != 0:
    failWmFile(WmFileErrorKind.reserved, "WM file submit reserved field is nonzero")
  result = WmFileSubmit(
    connectionEpoch: bytes.readU64(0),
    submissionId: bytes.readU64(8),
    candidateBytes: bytes.readU32(16),
  )
  result.validateSubmit()

proc validateAck(ack: WmFileAck) =
  if ack.connectionEpoch == 0 or ack.sequence == 0:
    failWmFile(WmFileErrorKind.identity, "WM file ack identity is null")

proc encodeAck*(ack: WmFileAck): seq[byte] =
  ack.validateAck()
  result = newSeqOfCap[byte](wmFileAckBytes)
  result.addU64(ack.connectionEpoch)
  result.addU64(ack.sequence)

proc decodeAck*(bytes: openArray[byte]): WmFileAck =
  if bytes.len != wmFileAckBytes:
    failWmFile(WmFileErrorKind.length, "WM file ack has the wrong length")
  result = WmFileAck(connectionEpoch: bytes.readU64(0), sequence: bytes.readU64(8))
  result.validateAck()
