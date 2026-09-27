import ./support/wire/sophia/presentation_oracle
import std/unittest
import types/core
import types/session
import types/wm_v1
import types/wm_presentation
import sophia/policy_transport
import ./support/wire/sophia/wm_v1
import ./support/wire/sophia/wm_file_bodies
import ./support/wire/sophia/wm_files
import ./support/wire/types/wm_files
import ./support/wire/types/wm_file_bodies
import types/desktop_sdk
import sophia/desktop_sdk
import sophia/sdk_cycle
import sophia/sdk_rows

proc presentation(): WmPresentation =
  let bounds = Rect(width: 400, height: 200)
  WmPresentation(
    generation: 1,
    outputs: @[
      PresentationOutput(
        output: 1, generation: 1, coverage: bounds, mode: PresentationMode.overlay
      )
    ],
    instances: @[
      SurfaceInstance(
        id: 1,
        generation: 1,
        output: 1,
        sourceIndex: 0,
        sourceGeneration: 2,
        destination: bounds,
        clip: bounds,
        opacityMillis: 1000,
        zIndex: 0,
      ),
      SurfaceInstance(
        id: 2,
        generation: 1,
        output: 1,
        sourceIndex: 0,
        sourceGeneration: 2,
        destination: Rect(x: 100, width: 100, height: 100),
        clip: bounds,
        opacityMillis: 500,
        zIndex: 1,
      ),
    ],
  )

const presentationCaps =
  capabilityActions or capabilitySurfaceInstances or capabilityPresentationActions

proc actionRecord(target: uint64): seq[byte] =
  let request = ProjectionRequest(
    connectionEpoch: 2,
    requestId: 3,
    sceneGeneration: 4,
    policyGeneration: 5,
    affectedOutputs: @[1'u64],
    cause: ProjectionCause(
      kind: ProjectionCauseKind.presentationAction,
      activationSerial: 6,
      action: 7,
      presentation: PresentationIdentity(
        publicationGeneration: 1,
        output: 1,
        outputGeneration: 8,
        presentationEpoch: 9,
        targetId: target,
        targetGeneration: target,
      ),
    ),
  )
  WmFileHeader(kind: WmFileKind.cycle, connectionEpoch: 2, sequence: 1).encodeCycle(
    WmFileCycle(snapshotTransaction: 1, requestTransaction: 2, request: request),
    presentationCaps,
  )

proc decoded(bytes: seq[byte], caps: uint64): WfRecord =
  sdkCheck(wfDecode(unsafeAddr bytes[0], csize_t(bytes.len), caps, addr result))

suite "generic WM presentation boundary":
  test "one source has independent instances and fixed bounded records":
    let records = presentation().encodePresentation()
    check records[0].len == 32
    check records[1].len == 40
    check records[2].len == 160
    check records[2].u64At(0) == 1
    check records[2].u64At(80) == 2
    check records[2].u32At(24) == records[2].u32At(104)
    check records[2].u32At(28) == records[2].u32At(108)

  test "invalid geometry, repeated identities, order and unbounded lists fail closed":
    for failure in 0 .. 6:
      var p = presentation()
      case failure
      of 0:
        p.instances[1].id = 1
      of 1:
        p.instances[1].zIndex = 0
      of 2:
        p.instances[0].clip.x = 500
      of 3:
        p.instances[0].destination.x = high(int32)
      of 4:
        p.instances[0].opacityMillis = 0
      of 5:
        p.outputs[0].mode = PresentationMode.replaceApplications
      else:
        p.instances.setLen(maxSurfaceInstances + 1)
      expect PolicyClientError:
        discard p.encodePresentation()

  test "keyboard and pointer actions require exact complete identity and negotiation":
    for target in [0'u64, 10]:
      let bytes = actionRecord(target)
      let request = bytes.decoded(presentationCaps).policyRequest()
      check request.connectionEpoch == 2
      check request.cause.kind == ProjectionCauseKind.presentationAction
      check request.cause.presentation.targetId == target
      check request.cause.presentation.presentationEpoch == 9
      for capabilities in [
        0'u64,
        capabilitySurfaceInstances,
        capabilityPresentationActions,
        presentationCaps xor capabilityActions,
        presentationCaps xor capabilitySurfaceInstances,
        presentationCaps xor capabilityPresentationActions,
      ]:
        expect PolicyClientError:
          discard bytes.decoded(capabilities)
      # Required envelope epoch, request identities and presentation cause fields.
      # Cycle has a 48-byte prefix and one 8-byte affected output before its cause.
      for offset in [8, 48, 56, 64, 88, 96, 104, 112, 120, 128]:
        var bad = actionRecord(target)
        for index in offset ..< offset + 8:
          bad[index] = 0
        expect PolicyClientError:
          discard bad.decoded(presentationCaps)
      var bad = actionRecord(0)
      bad[136] = 1 # target id without its generation
      expect PolicyClientError:
        discard bad.decoded(presentationCaps)

  test "receipts require actual presentation epoch and known lifecycle outcome":
    for outcome in 1'u16 .. 3'u16:
      let bytes = WmFileHeader(
        kind: WmFileKind.presentationReceipt, connectionEpoch: 2, sequence: 1
      ).encodePresentationReceipt(
        WmFilePresentationReceipt(
          transaction: 1,
          receipt: PresentationReceipt(
            connectionEpoch: 2,
            publicationGeneration: 3,
            output: 4,
            outputGeneration: 5,
            presentationEpoch: 6,
            outcome: PresentationOutcomeKind(outcome),
          ),
        ),
        capabilitySurfaceInstances,
      )
      let record = bytes.decoded(capabilitySurfaceInstances)
      check record.header.epoch == 2
      check record.value.presentationReceipt.outcome == outcome
      # Epoch admission is owned by the SDK session. The independent oracle
      # retains the old explicit expected-epoch characterization here.
      expect WmFileError:
        discard bytes.decodePresentationReceipt(3, capabilitySurfaceInstances)
      expect PolicyClientError:
        discard bytes.decoded(0)
      for offset in [40, 48, 56, 64]:
        var bad = bytes
        for index in offset ..< offset + 8:
          bad[index] = 0
        expect PolicyClientError:
          discard bad.decoded(capabilitySurfaceInstances)
      for invalid in [0'u8, 4'u8]:
        var bad = bytes
        bad[72] = invalid
        expect PolicyClientError:
          discard bad.decoded(capabilitySurfaceInstances)
