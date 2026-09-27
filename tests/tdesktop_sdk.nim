import std/unittest
import types/desktop_sdk
import types/sdk_candidate
import types/session
import ./support/wire/types/wm_file_bodies
import ./support/wire/types/wm_files
import types/wm_v1
import types/wm_presentation
import sophia/desktop_sdk
import sophia/sdk_candidate
import sophia/sdk_cycle
import sophia/sdk_rows
import sophia/sdk_snapshot
import ./support/wire/sophia/wm_file_bodies
import ./support/wire/sophia/wm_file_arrays
import support/wm_file_projection_fixture
import support/wm_file_snapshot_fixture

const allCaps = (1'u64 shl 20) - 1

proc encoded(candidate: var SdkCandidate): seq[byte] =
  candidate.bindRows()
  candidate.record.header.epoch = 9
  candidate.record.header.submission = 1
  result = newSeq[byte](1_048_576)
  var size: csize_t
  sdkCheck(
    wfEncode(
      addr result[0], csize_t(result.len), allCaps, addr candidate.record, addr size
    )
  )
  result.setLen(int(size))

suite "Hagia typed C SDK binding":
  test "all projection families match the independent file corpus encoder":
    let request = fileProjectionRequest()
    let projection = fileProjection()
    var candidate = projectionCandidate(request, 15, projection, allCaps)
    let expected = WmFileHeader(
      kind: WmFileKind.projection, connectionEpoch: 9, submissionId: 1
    ).encodeFileProjection(15, request, projection, allCaps)
    check candidate.encoded() == expected

  test "configuration action names and chrome preserve the complete value":
    let value = PolicyConfiguration(
      transaction: 1,
      connectionEpoch: 9,
      generation: 2,
      styleBits: 2,
      focusRgb: 0xffb6b0,
      frameWidth: 1,
      frameFocusedRgb: 0xffb6b0,
      frameUnfocusedRgb: 0x7c7c7c,
      actions:
        @[SnapshotAction(action: 7, sessionOperationSlot: 2, name: "open-terminal")],
    )
    var candidate = value.configurationCandidate()
    let expected = WmFileHeader(
      kind: WmFileKind.configuration, connectionEpoch: 9, submissionId: 1
    ).encodeFileConfiguration(value, allCaps)
    check candidate.encoded() == expected

  test "pointer focus keeps the reducer's output-as-action convention":
    let request = ProjectionRequest(
      connectionEpoch: 9,
      requestId: 3,
      sceneGeneration: 4,
      policyGeneration: 5,
      affectedOutputs: @[7'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.pointerFocus,
        action: 7,
        targetIndex: 2,
        targetGeneration: 1,
      ),
    )
    let bytes = WmFileHeader(kind: WmFileKind.cycle, connectionEpoch: 9, sequence: 1).encodeCycle(
      WmFileCycle(snapshotTransaction: 1, requestTransaction: 2, request: request),
      allCaps,
    )
    var record: WfRecord
    sdkCheck(wfDecode(unsafeAddr bytes[0], csize_t(bytes.len), allCaps, addr record))
    check record.policyRequest() == request

  test "every Cycle cause preserves the reducer value":
    let causes = [
      ProjectionCause(kind: ProjectionCauseKind.sceneChanged),
      ProjectionCause(kind: ProjectionCauseKind.action, activationSerial: 2, action: 11),
      ProjectionCause(
        kind: ProjectionCauseKind.focus, targetIndex: 0, targetGeneration: 1
      ),
      ProjectionCause(
        kind: ProjectionCauseKind.pointerFocus,
        action: 7,
        targetIndex: 0,
        targetGeneration: 1,
      ),
      ProjectionCause(
        kind: ProjectionCauseKind.interaction,
        interactionPhase: InteractionPhase.update,
        interactionKind: InteractionKind.move,
        targetIndex: 0,
        targetGeneration: 1,
        x: -2,
        y: 3,
        width: 640,
        height: 480,
      ),
      ProjectionCause(
        kind: ProjectionCauseKind.outputAction,
        activationSerial: 2,
        action: 11,
        output: 7,
        outputGeneration: 1,
      ),
      ProjectionCause(
        kind: ProjectionCauseKind.presentationAction,
        activationSerial: 2,
        action: 11,
        presentation: PresentationIdentity(
          publicationGeneration: 3,
          output: 7,
          outputGeneration: 1,
          presentationEpoch: 4,
          targetId: 5,
          targetGeneration: 1,
        ),
      ),
    ]
    for cause in causes:
      var request = fileProjectionRequest()
      request.cause = cause
      let bytes = WmFileHeader(kind: WmFileKind.cycle, connectionEpoch: 9, sequence: 1).encodeCycle(
        WmFileCycle(snapshotTransaction: 1, requestTransaction: 2, request: request),
        allCaps,
      )
      var record: WfRecord
      sdkCheck(wfDecode(unsafeAddr bytes[0], csize_t(bytes.len), allCaps, addr record))
      check record.policyRequest() == request

  test "all snapshot families copy the independent corpus value":
    var bytes = snapshotSections().snapshotBytes()
    let expected = bytes.decodeFileSnapshot(7, allCaps).snapshot
    var record: WfRecord
    sdkCheck(wfDecode(addr bytes[0], csize_t(bytes.len), allCaps, addr record))
    let copied = record.policySnapshot(7)
    for b in bytes.mitems:
      b = 0
    check copied == expected
