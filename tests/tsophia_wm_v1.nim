import std/[os, strutils, unittest]

import sophia/wm_v1

proc hexNibble(character: char): int =
  case character
  of '0' .. '9':
    ord(character) - ord('0')
  of 'a' .. 'f':
    ord(character) - ord('a') + 10
  else:
    -1

proc decodeHex(text: string): seq[byte] =
  if text.len mod 2 != 0:
    raise newException(ValueError, "odd hexadecimal input")
  result = newSeq[byte](text.len div 2)
  for index in 0 ..< result.len:
    let high = text[index * 2].hexNibble()
    let low = text[index * 2 + 1].hexNibble()
    if high < 0 or low < 0:
      raise newException(ValueError, "invalid hexadecimal input")
    result[index] = byte((high shl 4) or low)

proc kindFor(name: string): MessageKind =
  case name
  of "client_hello":
    MessageKind.clientHello
  of "server_welcome":
    MessageKind.serverWelcome
  of "snapshot_begin":
    MessageKind.snapshotBegin
  of "snapshot_chunk":
    MessageKind.snapshotChunk
  of "snapshot_end":
    MessageKind.snapshotEnd
  of "projection_request":
    MessageKind.projectionRequest
  of "projection_begin":
    MessageKind.projectionBegin
  of "projection_chunk":
    MessageKind.projectionChunk
  of "projection_end":
    MessageKind.projectionEnd
  of "projection_outcome":
    MessageKind.projectionOutcome
  of "policy_configuration":
    MessageKind.policyConfiguration
  of "policy_configuration_outcome":
    MessageKind.policyConfigurationOutcome
  of "policy_dirty":
    MessageKind.policyDirty
  of "session_operation_request":
    MessageKind.sessionOperationRequest
  of "session_operation_outcome":
    MessageKind.sessionOperationOutcome
  else:
    raise newException(ValueError, "unknown corpus message")

proc errorFor(name: string): PolicyProtocolErrorKind =
  case name
  of "truncated":
    PolicyProtocolErrorKind.truncated
  of "bad_magic":
    PolicyProtocolErrorKind.badMagic
  of "unsupported_frame_version":
    PolicyProtocolErrorKind.unsupportedFrameVersion
  of "wrong_message_kind":
    PolicyProtocolErrorKind.wrongMessageKind
  of "payload_too_large":
    PolicyProtocolErrorKind.payloadTooLarge
  of "reserved_nonzero":
    PolicyProtocolErrorKind.reservedNonzero
  of "trailing_bytes":
    PolicyProtocolErrorKind.trailingBytes
  of "invalid_transaction":
    PolicyProtocolErrorKind.invalidTransaction
  of "field_too_large":
    PolicyProtocolErrorKind.fieldTooLarge
  else:
    raise newException(ValueError, "unknown corpus error")

proc corpusLines(path: string): seq[string] =
  for line in readFile(path).splitLines():
    let stripped = line.strip()
    if stripped.len > 0 and not stripped.startsWith("#"):
      result.add(stripped)

proc checkValidFrames(path: string) =
  let lines = path.corpusLines()
  check lines.len == 15
  for line in lines:
    let fields = line.split('|')
    check fields.len == 3
    let bytes = fields[2].decodeHex()
    let frame = bytes.decodeFrame(fields[0].kindFor())
    check frame.transaction == uint64(parseBiggestUInt(fields[1]))
    check frame.encodeFrame() == bytes

proc checkMalformedFrames(path: string) =
  let lines = path.corpusLines()
  check lines.len == 11
  for line in lines:
    let fields = line.split('|')
    check fields.len == 4
    var rejected = false
    try:
      discard fields[3].decodeHex().decodeFrame(fields[1].kindFor())
    except PolicyProtocolError as error:
      rejected = true
      check error.kind == fields[2].errorFor()
    check rejected

proc checkRecords(path: string) =
  let lines = path.corpusLines()
  check lines.len == 6
  for line in lines:
    let fields = line.split('|')
    check fields.len == 2
    let bytes = fields[1].decodeHex()
    case fields[0]
    of "snapshot_output":
      check bytes.decodeSnapshotOutput().output == 1
    of "snapshot_surface":
      check bytes.decodeSnapshotSurface().surfaceIndex == 3
    of "snapshot_binding":
      let binding = bytes.decodeSnapshotBinding()
      check binding.action == 5
      check binding.keycode == 33
      check binding.modifierBits == 8
    of "snapshot_session_operation":
      let operation = bytes.decodeSnapshotSessionOperation()
      check operation.operation == 11
      check operation.slot == 1
      check operation.targetBits == 1
    of "projection_output":
      check bytes.decodeProjectionOutput().output == 1
    of "projection_placement":
      check bytes.decodeProjectionPlacement().surfaceIndex == 3
    else:
      check false

suite "independent Sophia WM v1 wire":
  test "shared golden and malformed corpora":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    checkValidFrames(sophiaRoot / "protocol/golden/sophia-wm-v1.frames")
    checkMalformedFrames(sophiaRoot / "protocol/golden/sophia-wm-v1-malformed.frames")
    checkRecords(sophiaRoot / "protocol/golden/sophia-wm-v1.records")
