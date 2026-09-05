import sophia/wm_translation
import sophia/wm_tab_groups
import types/session
import std/[os, strutils, unittest]

import sophia/wm_v1
import types/wm_v1 as wmTypes

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
  of "profile_prepare":
    MessageKind.profilePrepare
  of "profile_prepared":
    MessageKind.profilePrepared
  of "profile_activate":
    MessageKind.profileActivate
  of "profile_active":
    MessageKind.profileActive
  of "profile_rollback":
    MessageKind.profileRollback
  of "profile_rolled_back":
    MessageKind.profileRolledBack
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
  check lines.len == 21
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
  check lines.len == 13
  for line in lines:
    let fields = line.split('|')
    check fields.len == 2
    let bytes = fields[1].decodeHex()
    case fields[0]
    of "snapshot_output":
      check bytes.decodeSnapshotOutput().output == 1
    of "snapshot_surface":
      check bytes.decodeSnapshotSurface().surfaceIndex == 3
    of "snapshot_action":
      let action = bytes.decodeSnapshotAction()
      check action.action == 5
      check action.name.len == 10
    of "snapshot_session_operation":
      let operation = bytes.decodeSnapshotSessionOperation()
      check operation.operation == 11
      check operation.slot == 1
      check operation.targetBits == 1
    of "snapshot_surface_classification":
      # The capability-gated extension record, proven from the same corpus the
      # generated codecs parse now that the schema declares it.
      let classification = bytes.decodeSnapshotSurfaceClassification()
      check classification.surfaceIndex == 3
      check classification.surfaceGeneration == 1
      check classification.classification == 2
    of "projection_tab_group", "projection_tab_member":
      let group = ProjectionTabGroup(
        output: 1,
        group: 1,
        x: 1,
        y: 1,
        width: 1,
        height: 1,
        selectedIndex: 1,
        selectedGeneration: 1,
        focused: true,
        members: @[ProjectionTabMember(surfaceIndex: 1, surfaceGeneration: 1)],
      )
      if fields[0] == "projection_tab_group":
        check group.encodeTabGroup() == bytes
      else:
        check group.encodeTabMember(group.members[0]) == bytes
    of "projection_translation_group", "projection_translation_member":
      let group = ProjectionTranslationGroup(
        output: 1,
        group: 1,
        x: 1,
        y: 0,
        members: @[ProjectionTabMember(surfaceIndex: 1, surfaceGeneration: 1)],
      )
      if fields[0] == "projection_translation_group":
        check group.encodeTranslationGroup() == bytes
      else:
        check group.encodeTranslationMember(group.members[0]) == bytes
    of "projection_output":
      check bytes.decodeProjectionOutput().output == 1
    of "projection_placement":
      check bytes.decodeProjectionPlacement().surfaceIndex == 3
    of "projection_indicator":
      let indicator = bytes.decodeProjectionIndicator()
      check indicator.output == 1
      check indicator.action == 5
      check indicator.labelLen == 3
      check indicator.label[0] == byte('w')
      check indicator.label[1] == byte('e')
      check indicator.label[2] == byte('b')
      check indicator.label[3] == 0
    of "projection_output_status":
      let status = bytes.decodeProjectionOutputStatus()
      check status.output == 1
      check status.layoutLen == 4
      check status.layout[0] == byte('T')
      check status.layout[3] == byte('l')
      check status.layout[4] == 0
    else:
      check false

suite "independent Sophia WM v1 wire":
  test "shared golden and malformed corpora":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    checkValidFrames(sophiaRoot / "protocol/golden/sophia-wm-v1.frames")
    checkMalformedFrames(sophiaRoot / "protocol/golden/sophia-wm-v1-malformed.frames")
    checkRecords(sophiaRoot / "protocol/golden/sophia-wm-v1.records")

  test "typed profile controls retain exact identity and closed outcomes":
    var identity = ProfileIdentity(connectionEpoch: 9, profileGeneration: 7)
    for index in 0 ..< profileDigestLen:
      identity.profileDigest[index] = byte(index + 1)

    for kind in {
      MessageKind.profilePrepare, MessageKind.profileActivate,
      MessageKind.profileRollback,
    }:
      let command =
        kind.profileCommandFrame(11, identity).encodeFrame().decodeFrame(kind)
      check command.decodeProfileCommand() ==
        ProfileCommand(transaction: 11, identity: identity)

    for kind in {
      MessageKind.profilePrepared, MessageKind.profileActive,
      MessageKind.profileRolledBack,
    }:
      let completion =
        kind.profileCompletionFrame(11, identity, ProfileOutcomeKind.accepted)
      check completion.encodeFrame().decodeFrame(kind).decodeProfileCompletion() ==
        ProfileCompletion(
          transaction: 11, identity: identity, outcome: ProfileOutcomeKind.accepted
        )

  test "typed profile controls reject every null identity field":
    var identity = ProfileIdentity(connectionEpoch: 9, profileGeneration: 7)
    identity.profileDigest[0] = 1

    for invalid in [
      ProfileIdentity(
        connectionEpoch: 0,
        profileGeneration: identity.profileGeneration,
        profileDigest: identity.profileDigest,
      ),
      ProfileIdentity(
        connectionEpoch: identity.connectionEpoch,
        profileGeneration: 0,
        profileDigest: identity.profileDigest,
      ),
      ProfileIdentity(connectionEpoch: 9, profileGeneration: 7),
    ]:
      expect PolicyProtocolError:
        discard MessageKind.profilePrepare.profileCommandFrame(11, invalid)

  test "typed profile controls reject null transactions":
    var identity = ProfileIdentity(connectionEpoch: 9, profileGeneration: 7)
    identity.profileDigest[0] = 1
    let command = MessageKind.profilePrepare.profileCommandFrame(11, identity)
    expect PolicyProtocolError:
      discard Frame(kind: command.kind, transaction: 0, payload: command.payload).decodeProfileCommand()
    let completion = MessageKind.profilePrepared.profileCompletionFrame(
      11, identity, ProfileOutcomeKind.accepted
    )
    expect PolicyProtocolError:
      discard Frame(kind: completion.kind, transaction: 0, payload: completion.payload).decodeProfileCompletion()
