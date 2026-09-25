import std/unittest
import types/[core, session, wm_v1, wm_presentation]
import sophia/[policy_codec, policy_transport, wm_presentation, wm_v1]

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

proc actionFrame(target: uint64): Frame =
  result = Frame(kind: MessageKind.presentationActionRequest, transaction: 1)
  for value in [2'u64, 3, 4, 5, 6, 7, 1, 1, 8, 9, target, target]:
    result.payload.addU64(value)
  result.payload.addU16(1)
  result.payload.addU16(0)
  result.payload.addU64(1)

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
    let caps = capabilitySurfaceInstances or capabilityPresentationActions
    for target in [0'u64, 10]:
      let frame = actionFrame(target)
      let request = frame.decodeProjectionRequest(2, caps)
      check request.cause.kind == ProjectionCauseKind.presentationAction
      check request.cause.presentation.targetId == target
      check request.cause.presentation.presentationEpoch == 9
      for capabilities in [
        0'u64, capabilitySurfaceInstances, capabilityPresentationActions
      ]:
        expect PolicyClientError:
          discard frame.decodeProjectionRequest(2, capabilities)
      for offset in [0, 8, 16, 24, 32, 40, 48, 56, 64, 72]:
        var bad = actionFrame(target)
        for index in offset ..< offset + 8:
          bad.payload[index] = 0
        expect PolicyClientError:
          discard bad.decodeProjectionRequest(2, caps)
      var bad = actionFrame(0)
      bad.payload[80] = 1
      expect PolicyClientError:
        discard bad.decodeProjectionRequest(2, caps)

  test "receipts require actual presentation epoch and known lifecycle outcome":
    for outcome in 1'u16 .. 3'u16:
      var frame = Frame(kind: MessageKind.presentationOutcome, transaction: 1)
      for value in [2'u64, 3, 4, 5, 6]:
        frame.payload.addU64(value)
      frame.payload.addU16(outcome)
      frame.payload.addU16(0)
      check frame.decodePresentationReceipt(2, capabilitySurfaceInstances).outcome ==
        PresentationOutcomeKind(outcome)
      expect PolicyClientError:
        discard frame.decodePresentationReceipt(3, capabilitySurfaceInstances)
      expect PolicyClientError:
        discard frame.decodePresentationReceipt(2, 0)
      frame.payload[32] = 0
      expect PolicyClientError:
        discard frame.decodePresentationReceipt(2, capabilitySurfaceInstances)
