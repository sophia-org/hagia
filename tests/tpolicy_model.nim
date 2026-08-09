import std/[net, options, os, posix, tempfiles, unittest]

import policy/[actions, projection, state, types]
import
  sophia/[
    policy_adapter, policy_checkpoint, policy_client, policy_session, session_types,
    wm_v1,
  ]

proc focusableCapabilities(): WindowCapabilities =
  WindowCapabilities(
    movable: true, resizable: true, focusable: true, fullscreenable: true
  )

proc surface(
    index: uint32, output: uint64, stateGeneration: uint64 = 1, minWidth: int32 = 0
): SnapshotSurface =
  SnapshotSurface(
    surfaceIndex: index,
    surfaceGeneration: 1,
    stateGeneration: stateGeneration,
    currentOutput: output,
    capabilityBits: 31,
    width: 400,
    height: 300,
    minWidth: minWidth,
    minHeight: (if minWidth == 0: 0 else: 100),
  )

proc snapshot(
    generation: uint64, outputs: seq[SnapshotOutput], surfaces: seq[SnapshotSurface]
): PolicySnapshot =
  PolicySnapshot(
    generation: generation,
    activeOutput: outputs[0].output,
    outputs: outputs,
    surfaces: surfaces,
  )

proc binaryString(bytes: openArray[byte]): string =
  result = newString(bytes.len)
  for index, value in bytes:
    result[index] = char(value)

proc appendFrame(bytes: var seq[byte], frame: Frame) =
  bytes.add(frame.encodeFrame())

proc appendWireCycle(
    bytes: var seq[byte],
    epoch, generation, requestId, snapshotTransaction, requestTransaction,
      proposalTransaction: uint64,
    outcome: ProjectionOutcomeKind,
    policyGeneration = 1'u64,
    action = 0'u64,
) =
  var beginPayload: seq[byte]
  beginPayload.addU64(epoch)
  beginPayload.addU64(generation)
  beginPayload.addU64(10)
  beginPayload.addU16(2)
  beginPayload.addU16(1)
  beginPayload.addU32(1)
  beginPayload.addU16(0)
  beginPayload.addU16(0)
  bytes.appendFrame(
    Frame(
      kind: MessageKind.snapshotBegin,
      transaction: snapshotTransaction,
      payload: beginPayload,
    )
  )

  var outputRecord: seq[byte]
  outputRecord.addU64(10)
  outputRecord.addU64(1)
  outputRecord.addU32(1)
  outputRecord.addU32(1)
  outputRecord.addU32(0)
  outputRecord.addU32(0)
  outputRecord.addU32(800)
  outputRecord.addU32(600)
  outputRecord.addU32(0)
  outputRecord.addU32(0)
  outputRecord.addU32(800)
  outputRecord.addU32(600)
  var outputPayload: seq[byte]
  outputPayload.addU64(epoch)
  outputPayload.addU16(0)
  outputPayload.addU16(1)
  outputPayload.addU32(1)
  outputPayload.add(outputRecord)
  bytes.appendFrame(
    Frame(
      kind: MessageKind.snapshotChunk,
      transaction: snapshotTransaction,
      payload: outputPayload,
    )
  )

  var surfaceRecord: seq[byte]
  surfaceRecord.addU32(1)
  surfaceRecord.addU32(1)
  surfaceRecord.addU64(generation)
  surfaceRecord.addU64(10)
  surfaceRecord.addU16(31)
  surfaceRecord.addU16(1)
  surfaceRecord.addU16(0)
  surfaceRecord.addU16(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(800)
  surfaceRecord.addU32(600)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  surfaceRecord.addU32(0)
  var surfacePayload: seq[byte]
  surfacePayload.addU64(epoch)
  surfacePayload.addU16(1)
  surfacePayload.addU16(2)
  surfacePayload.addU32(1)
  surfacePayload.add(surfaceRecord)
  bytes.appendFrame(
    Frame(
      kind: MessageKind.snapshotChunk,
      transaction: snapshotTransaction,
      payload: surfacePayload,
    )
  )

  var endPayload: seq[byte]
  endPayload.addU64(epoch)
  endPayload.addU64(generation)
  endPayload.addU16(2)
  endPayload.addU16(0)
  bytes.appendFrame(
    Frame(
      kind: MessageKind.snapshotEnd,
      transaction: snapshotTransaction,
      payload: endPayload,
    )
  )

  var requestPayload: seq[byte]
  requestPayload.addU64(epoch)
  requestPayload.addU64(requestId)
  requestPayload.addU64(generation)
  requestPayload.addU64(policyGeneration)
  requestPayload.addU16(if action == 0: 0 else: 1)
  requestPayload.addU16(0)
  requestPayload.addU16(0)
  requestPayload.addU16(0)
  requestPayload.addU64(if action == 0: 0'u64 else: requestId)
  requestPayload.addU64(action)
  requestPayload.addU32(0)
  requestPayload.addU32(0)
  requestPayload.addU32(0)
  requestPayload.addU32(0)
  requestPayload.addU32(0)
  requestPayload.addU32(0)
  requestPayload.addU16(1)
  requestPayload.addU16(0)
  requestPayload.addU64(10)
  bytes.appendFrame(
    Frame(
      kind: MessageKind.projectionRequest,
      transaction: requestTransaction,
      payload: requestPayload,
    )
  )

  var outcomePayload: seq[byte]
  outcomePayload.addU64(epoch)
  outcomePayload.addU64(requestId)
  outcomePayload.addU64(generation + 1)
  outcomePayload.addU16(uint16(ord(outcome)))
  outcomePayload.addU16(0)
  bytes.appendFrame(
    Frame(
      kind: MessageKind.projectionOutcome,
      transaction: proposalTransaction,
      payload: outcomePayload,
    )
  )

proc appendWelcome(bytes: var seq[byte], epoch: uint64) =
  var payload: seq[byte]
  payload.addU16(1)
  payload.addU16(0)
  payload.addU64(7 or (1'u64 shl 8))
  payload.addU64(epoch)
  payload.addU16(16)
  payload.addU16(256)
  payload.addU32(1024)
  payload.addU32(65520)
  bytes.appendFrame(Frame(kind: MessageKind.serverWelcome, payload: payload))

proc runWireSession(serverBytes: seq[byte]): seq[byte] =
  var handles: array[0 .. 1, cint]
  doAssert posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, handles) == 0
  let clientSocket =
    newSocket(SocketHandle(handles[0]), net.AF_UNIX, net.SOCK_STREAM, net.IPPROTO_IP)
  let encodedServer = serverBytes.binaryString()
  var sent = 0
  while sent < encodedServer.len:
    let count =
      posix.write(handles[1], unsafeAddr encodedServer[sent], encodedServer.len - sent)
    doAssert count > 0
    sent += count
  clientSocket.runPolicySessionOnSocket()
  var buffer: array[4096, char]
  while true:
    let count = posix.read(handles[1], addr buffer[0], buffer.len)
    if count == 0:
      break
    doAssert count > 0
    for index in 0 ..< count:
      result.add(byte(buffer[index]))
  discard posix.close(handles[1])

proc proposalTransactions(clientWire: seq[byte]): seq[uint64] =
  var offset = 0
  while offset < clientWire.len:
    doAssert clientWire.len - offset >= frameHeaderLen
    let payloadLen = int(clientWire.u32At(offset + 16))
    let frameLen = frameHeaderLen + payloadLen
    doAssert offset + frameLen <= clientWire.len
    let kind = clientWire.u16At(offset + 6)
    if kind == uint16(ord(MessageKind.projectionBegin)):
      result.add(clientWire.u64At(offset + 8))
    offset += frameLen

proc policyDirtyFrames(clientWire: seq[byte]): seq[Frame] =
  var offset = 0
  while offset < clientWire.len:
    doAssert clientWire.len - offset >= frameHeaderLen
    let payloadLen = int(clientWire.u32At(offset + 16))
    let frameLen = frameHeaderLen + payloadLen
    doAssert offset + frameLen <= clientWire.len
    if clientWire.u16At(offset + 6) == uint16(ord(MessageKind.policyDirty)):
      result.add(
        clientWire[offset ..< offset + frameLen].decodeFrame(MessageKind.policyDirty)
      )
    offset += frameLen

proc projectionPlacementCounts(clientWire: seq[byte]): seq[uint32] =
  var offset = 0
  while offset < clientWire.len:
    doAssert clientWire.len - offset >= frameHeaderLen
    let payloadLen = int(clientWire.u32At(offset + 16))
    let frameLen = frameHeaderLen + payloadLen
    doAssert offset + frameLen <= clientWire.len
    if clientWire.u16At(offset + 6) == uint16(ord(MessageKind.projectionBegin)):
      result.add(clientWire.u32At(offset + frameHeaderLen + 36))
    offset += frameLen

suite "Hagia private policy model":
  test "view action identities have one bounded symbolic mapping":
    for slot in 1 .. 9:
      check slot.activateViewAction().raw() == uint64(10 + slot)
      check slot.moveToViewAction().raw() == uint64(19 + slot)
    expect PolicyStateError:
      discard 0.activateViewAction()
    expect PolicyStateError:
      discard 10.moveToViewAction()

  test "cross-output movement replaces both output projections atomically":
    var model = initPolicyModel()
    let first = model.addOutput(Rect(width: 800, height: 600))
    let second = model.addOutput(Rect(x: 800, width: 800, height: 600))
    let window = model.addWindow(first, focusableCapabilities(), SizeConstraints())
    model.setFocus(first, window)

    model.applyAction(first, PolicyAction.moveToNextOutput)
    check model.window(window).get().homeOutput == second
    let projected = model.projectScroller([first, second])
    require projected.len == 2
    check projected[0].output == first
    check projected[0].placements.len == 0
    check projected[1].output == second
    check projected[1].placements.len == 1
    check projected[1].placements[0].window == window
    model.validate()

  test "the nine-view profile reuses bounded tag slots across every output":
    var model = initPolicyModel()
    var outputs: seq[OutputId]
    for index in 0 ..< 16:
      let output =
        model.addOutput(Rect(x: int32(index) * 1000, width: 1000, height: 700))
      model.ensureViewCount(output, 9)
      outputs.add(output)

    for output in outputs:
      let data = model.output(output).get()
      check data.views.len == 9
      for index, view in data.views:
        check model.view(view).get().selectedTags == tagForSlot(uint32(index + 1))
    check model.nextTagSlot == 9
    model.validate()

  test "view actions switch visibility and move the focused window":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 800))
    model.ensureViewCount(output, 9)
    let window = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    model.setFocus(output, window)

    model.moveFocusedToViewSlot(output, 2)
    check model.eligibleWindows(output) == @[window]
    check model.output(output).get().focusedWindow == window
    model.activateViewSlot(output, 1)
    check model.eligibleWindows(output).len == 0
    model.activateViewSlot(output, 2)
    check model.eligibleWindows(output) == @[window]
    check model.output(output).get().focusedWindow == nullWindowId
    model.validate()

  test "tag views select ordered windows without changing their identities":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 800))
    let first = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())

    let secondTags = tagForSlot(2)
    model.setWindowTags(second, secondTags)
    check model.eligibleWindows(output) == @[first]

    let secondView = model.addView(output, secondTags)
    model.activateView(output, secondView)
    check model.eligibleWindows(output) == @[second]
    check model.window(first).get().id == first
    check model.window(second).get().id == second
    model.validate()

  test "scroller projection respects constraints and deterministic order":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(x: 10, y: 20, width: 1000, height: 700))
    let first = model.addWindow(
      output, focusableCapabilities(), SizeConstraints(minWidth: 700, minHeight: 100)
    )
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    model.setFocus(output, second)

    let projected = model.projectScroller([output])
    require projected.len == 1
    check projected[0].focus == second
    check projected[0].placements.len == 2
    check projected[0].placements[0].window == first
    check projected[0].placements[0].geometry ==
      Rect(x: 10, y: 20, width: 500, height: 700)
    check projected[0].placements[0].requestedWidth == 700
    check projected[0].placements[1].geometry ==
      Rect(x: 510, y: 20, width: 500, height: 700)

  test "automatic scroller columns preserve equal-width projection":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1200, height: 800))
    let first = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    model.setFocus(output, second)

    let projected = model.projectScroller([output])
    require projected.len == 1
    check projected[0].viewportOffset == 0
    check projected[0].placements.len == 2
    check projected[0].placements[0].window == first
    check projected[0].placements[0].geometry ==
      Rect(x: 0, y: 0, width: 600, height: 800)
    check projected[0].placements[1].window == second
    check projected[0].placements[1].geometry ==
      Rect(x: 600, y: 0, width: 600, height: 800)

  test "fixed-point columns center a focused overflow target":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1000, height: 700))
    let first = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    let third = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    for windowId in [first, second, third]:
      model.setColumnWidthScale(
        model.window(windowId).get().column, scaleFromRatio(1, 2)
      )
    model.setFocus(output, third)

    let projected = model.projectScroller([output])
    require projected.len == 1
    check projected[0].viewportOffset == 750
    check projected[0].placements[0].geometry.x == -750
    check projected[0].placements[1].geometry.x == -250
    check projected[0].placements[2].geometry ==
      Rect(x: 250, y: 0, width: 500, height: 700)
    check projected[0].focus == third

  test "scroller stacks column windows with deterministic fixed-point heights":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 1000, height: 1000))
    let first = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    let second = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    model.moveWindowToColumn(second, model.window(first).get().column)
    model.setWindowHeightScale(second, scaleFromRatio(3, 1))

    let projected = model.projectScroller([output], innerGap = 20)
    require projected.len == 1
    check projected[0].placements.len == 2
    check projected[0].placements[0].geometry ==
      Rect(x: 0, y: 0, width: 1000, height: 245)
    check projected[0].placements[1].geometry ==
      Rect(x: 0, y: 265, width: 1000, height: 735)
    model.validate()

  test "scroller saturates excessive fixed-point extents":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 100000, height: 700))
    let window = model.addWindow(output, focusableCapabilities(), SizeConstraints())
    model.setColumnWidthScale(model.window(window).get().column, Scale(high(uint32)))

    let projected = model.projectScroller([output])
    check projected[0].placements[0].geometry.width == high(int32)

  test "output removal migrates private views and windows":
    var model = initPolicyModel()
    let firstOutput = model.addOutput(Rect(width: 1000, height: 700))
    let secondOutput = model.addOutput(Rect(x: 1000, width: 1000, height: 700))
    let window =
      model.addWindow(secondOutput, focusableCapabilities(), SizeConstraints())

    discard model.removeOutput(secondOutput, firstOutput)
    check model.outputIds() == @[firstOutput]
    check model.window(window).get().homeOutput == firstOutput
    check model.window(window).get().preferredOutput == secondOutput
    check model.affinity(secondOutput).isSome

    model.restoreOutput(secondOutput, Rect(x: 1000, width: 1000, height: 700))
    check model.outputIds() == @[firstOutput, secondOutput]
    check model.window(window).get().homeOutput == secondOutput
    check model.affinity(secondOutput).isNone
    model.validate()

  test "output affinities evict the oldest record deterministically":
    var model = initPolicyModel()
    let fallback = model.addOutput(Rect(width: 1000, height: 700))
    var oldest = nullOutputId
    for index in 0 .. maxOutputAffinities:
      let output =
        model.addOutput(Rect(x: int32(index + 1) * 1000, width: 1000, height: 700))
      if index == 0:
        oldest = output
      discard model.removeOutput(output, fallback)
    check model.affinity(oldest).isNone
    check model.affinityOrder.len == maxOutputAffinities
    model.validate()

  test "output focus, grouping, presentation, and bounded history reduce privately":
    var model = initPolicyModel()
    let first = model.addOutput(Rect(width: 900, height: 600))
    let second = model.addOutput(Rect(x: 900, width: 900, height: 600))
    model.ensureViewCount(first, 9)
    model.ensureViewCount(second, 9)
    let one = model.addWindow(first, focusableCapabilities(), SizeConstraints())
    let two = model.addWindow(first, focusableCapabilities(), SizeConstraints())
    model.setFocus(first, one)
    model.setFocus(first, two)
    model.applyAction(first, PolicyAction.consumeNextColumn)
    check model.window(one).get().column == model.window(two).get().column
    model.applyAction(first, PolicyAction.expelFocusedWindow)
    check model.window(one).get().column != model.window(two).get().column
    model.applyAction(first, PolicyAction.toggleFullscreen)
    check model.window(two).get().fullscreen
    model.applyAction(first, PolicyAction.minimizeFocused)
    check model.window(two).get().minimized
    check model.output(first).get().focusedWindow == one
    model.applyAction(first, PolicyAction.restoreMinimized)
    check not model.window(two).get().minimized
    check model.output(first).get().focusedWindow == two
    model.applyAction(first, PolicyAction.focusNextOutput)
    check model.activeOutput == second
    check model.output(first).get().focusHistory.len <= maxFocusHistory
    model.validate()

  test "minimized restore history remains bounded independently of state":
    var model = initPolicyModel()
    let output = model.addOutput(Rect(width: 900, height: 600))
    for _ in 0 ..< maxMinimizedHistory + 6:
      let window = model.addWindow(output, focusableCapabilities(), SizeConstraints())
      model.setWindowPresentation(window, false, false, true)
    check model.minimizedOrder.len == maxMinimizedHistory
    model.validate()

suite "Sophia snapshot adapter":
  test "projection uses the Engine work rectangle":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      width: 1000,
      height: 700,
      workY: 40,
      workWidth: 1000,
      workHeight: 660,
    )
    let scene = snapshot(1, @[output], @[surface(1, 10)])
    var adapter = initPolicyAdapter()
    adapter.reconcile(scene)
    let projection = adapter.projection(
      scene,
      ProjectionRequest(
        connectionEpoch: 7,
        requestId: 9,
        sceneGeneration: 1,
        policyGeneration: 1,
        affectedOutputs: @[10'u64],
      ),
    )
    check projection.outputs[0].placements[0].y == 40
    check projection.outputs[0].placements[0].height == 660
    check projection.indicators.len == 9
    check projection.indicators[0].output == 10
    check projection.indicators[0].slot == 0
    check projection.indicators[0].action == 11
    check (projection.indicators[0].stateBits and 1) != 0
    check projection.indicators[0].labelLen == 1
    check projection.indicators[0].label[0] == byte('1')
    check projection.outputStatuses.len == 1
    check projection.outputStatuses[0].layoutLen == 8

  test "complete snapshots preserve logical ids and admit hidden surfaces":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 1000,
      height: 700,
    )
    var adapter = initPolicyAdapter()
    let firstSnapshot = snapshot(1, @[output], @[surface(1, 10), surface(2, 0)])
    adapter.reconcile(firstSnapshot)
    let firstId = adapter.logicalWindow(1, 1)
    let secondId = adapter.logicalWindow(2, 1)
    require firstId.isSome and secondId.isSome

    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 9,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
    )
    let projection = adapter.projection(firstSnapshot, request)
    require projection.outputs.len == 1
    check projection.outputs[0].output.output == 10
    check projection.outputs[0].placements.len == 2
    check projection.outputs[0].placements[0].width == 500
    check projection.outputs[0].placements[1].x == 500

    var nextOutput = output
    nextOutput.generation = 2
    nextOutput.focusIndex = 0
    nextOutput.focusGeneration = 0
    let nextSnapshot =
      snapshot(2, @[nextOutput], @[surface(1, 10, 2), surface(2, 10, 2)])
    adapter.reconcile(nextSnapshot)
    check adapter.logicalWindow(1, 1) == firstId
    check adapter.logicalWindow(2, 1) == secondId
    let logicalOutput = adapter.logicalOutput(10).get()
    check adapter.model().output(logicalOutput).get().focusedWindow == nullWindowId

  test "projection rejects an output outside the complete snapshot":
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let scene = snapshot(1, @[output], @[surface(1, 10)])
    var adapter = initPolicyAdapter()
    adapter.reconcile(scene)

    expect PolicyAdapterError:
      discard adapter.projection(
        scene,
        ProjectionRequest(
          connectionEpoch: 7,
          requestId: 9,
          sceneGeneration: 1,
          policyGeneration: 1,
          affectedOutputs: @[11'u64],
        ),
      )

  test "an exact output generation restores its logical affinity":
    let first = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let second =
      SnapshotOutput(output: 20, generation: 4, x: 800, width: 800, height: 600)
    var adapter = initPolicyAdapter()
    adapter.reconcile(snapshot(1, @[first, second], @[surface(1, 10), surface(2, 20)]))
    let logical = adapter.logicalOutput(20).get()

    adapter.reconcile(snapshot(2, @[first], @[surface(1, 10), surface(2, 10)]))
    check adapter.logicalOutput(20).isNone
    check adapter.model().affinity(logical).isSome

    adapter.reconcile(snapshot(3, @[first, second], @[surface(1, 10), surface(2, 20)]))
    check adapter.logicalOutput(20) == some(logical)
    check adapter.model().affinity(logical).isNone
    adapter.model().validate()

  test "a reused raw output id with a new generation gets a new logical id":
    let first = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let oldSecond =
      SnapshotOutput(output: 20, generation: 4, x: 800, width: 800, height: 600)
    var adapter = initPolicyAdapter()
    adapter.reconcile(
      snapshot(1, @[first, oldSecond], @[surface(1, 10), surface(2, 20)])
    )
    let oldLogical = adapter.logicalOutput(20).get()
    adapter.reconcile(snapshot(2, @[first], @[surface(1, 10), surface(2, 10)]))

    var newSecond = oldSecond
    newSecond.generation = 5
    let returnedScene =
      snapshot(3, @[first, newSecond], @[surface(1, 10), surface(2, 20)])
    adapter.reconcile(returnedScene)
    check adapter.logicalOutput(20).get() != oldLogical
    check adapter.model().affinity(oldLogical).isSome
    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 9,
      sceneGeneration: 3,
      policyGeneration: 1,
      affectedOutputs: @[10'u64, 20'u64],
    )
    let projected = adapter.projection(returnedScene, request)
    check projected.outputs[0].placements.len == 1
    check projected.outputs[1].placements.len == 1
    check projected.indicators.len == 18
    for indicator in projected.indicators:
      check indicator.action in 11'u64 .. 19'u64
    adapter.model().validate()

  test "a private checkpoint remains a candidate until complete reconciliation":
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let first = snapshot(1, @[output], @[surface(1, 10)])
    var adapter = initPolicyAdapter()
    adapter.reconcile(first)
    let logicalWindow = adapter.logicalWindow(1, 1)
    let payload = adapter.checkpointPayload()
    var restored = payload.restoreCheckpointPayload()
    restored.reconcile(snapshot(2, @[output], @[surface(1, 10, 2), surface(2, 10)]))
    check restored.logicalWindow(1, 1) == logicalWindow
    check restored.logicalWindow(2, 1).isSome
    expect PolicyAdapterError:
      discard ("BAD" & payload).restoreCheckpointPayload()

  test "a private checkpoint is atomically replaced and loaded from disk":
    let directory = createTempDir("hagia-checkpoint-", "")
    let path = directory / "policy.checkpoint"
    defer:
      if fileExists(path):
        removeFile(path)
      removeDir(directory)

    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    var adapter = initPolicyAdapter()
    adapter.reconcile(snapshot(1, @[output], @[surface(1, 10)]))
    let logicalWindow = adapter.logicalWindow(1, 1)

    savePolicyCheckpoint(path, adapter)
    check getFilePermissions(path) == {fpUserRead, fpUserWrite}
    let loaded = loadPolicyCheckpoint(path)
    require loaded.isSome
    check loaded.get().logicalWindow(1, 1) == logicalWindow

    writeFile(path, "not a checkpoint")
    expect PolicyCheckpointError:
      discard loadPolicyCheckpoint(path)

suite "Sophia policy session":
  test "fullscreen uses output bounds while ordinary scroller geometry uses work area":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      width: 900,
      height: 600,
      workY: 40,
      workWidth: 900,
      workHeight: 560,
      focusIndex: 1,
      focusGeneration: 1,
    )
    var scene = snapshot(1, @[output], @[surface(1, 10)])
    scene.bindings = @[SnapshotBinding(action: 37)]
    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.action, activationSerial: 1, action: 37
      ),
    )
    var session = initPolicySession()
    let projected = session.prepare(scene, request, 1)
    let placement = projected.outputs[0].placements[0]
    check projected.activeOutput == 10
    check placement.y == 0
    check placement.height == 600
    check (placement.presentationBits and 1) != 0

  test "one completed reduced pointer interaction becomes committed floating geometry":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 900,
      height: 600,
    )
    let scene = snapshot(1, @[output], @[surface(1, 10)])
    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.interaction,
        interactionPhase: InteractionPhase.finish,
        interactionKind: InteractionKind.resize,
        targetIndex: 1,
        targetGeneration: 1,
        x: 40,
        y: 30,
        width: 500,
        height: 400,
      ),
    )
    var session = initPolicySession()
    let projected = session.prepare(scene, request, 1)
    require projected.outputs.len == 1
    require projected.outputs[0].placements.len == 1
    let placement = projected.outputs[0].placements[0]
    check (placement.x, placement.y, placement.width, placement.height) ==
      (40'i32, 30'i32, 500'i32, 400'i32)
    check projected.outputs[0].output.focusIndex == 1

  test "repeated action tokens retain distinct committed activations":
    var output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 900,
      height: 600,
    )
    let firstScene =
      snapshot(1, @[output], @[surface(1, 10), surface(2, 10), surface(3, 10)])
    var session = initPolicySession()
    let firstRequest = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.action, activationSerial: 1, action: 1
      ),
    )
    let firstProjection = session.prepare(firstScene, firstRequest, 1)
    check firstProjection.outputs[0].output.focusIndex == 2
    session.settle(
      ProjectionOutcome(
        transaction: 1,
        connectionEpoch: 7,
        requestId: 1,
        sceneGeneration: 2,
        kind: ProjectionOutcomeKind.committed,
      )
    )

    output.focusIndex = 2
    let secondScene =
      snapshot(2, @[output], @[surface(1, 10, 2), surface(2, 10, 2), surface(3, 10, 2)])
    let secondRequest = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 2,
      sceneGeneration: 2,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.action, activationSerial: 2, action: 1
      ),
    )
    let secondProjection = session.prepare(secondScene, secondRequest, 2)
    check secondProjection.outputs[0].output.focusIndex == 3

  test "opaque session actions resolve profile slots after projection staging":
    let output = SnapshotOutput(
      output: 10,
      generation: 1,
      focusIndex: 1,
      focusGeneration: 1,
      width: 900,
      height: 600,
    )
    var scene = snapshot(1, @[output], @[surface(1, 10)])
    scene.bindings = @[SnapshotBinding(action: 31, sessionOperationSlot: 3)]
    scene.sessionOperations =
      @[SnapshotSessionOperation(operation: 700, slot: 3, targetBits: 1)]
    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.action, activationSerial: 19, action: 31
      ),
    )
    var session = initPolicySession()
    discard session.prepare(scene, request, 1)
    let operation = session.pendingOperation().get()
    check operation.requestId == 19
    check operation.operation == 700
    check operation.targetIndex == 1
    check operation.targetGeneration == 1

  test "an unavailable session-operation slot fails closed":
    let output = SnapshotOutput(output: 10, generation: 1, width: 900, height: 600)
    var scene = snapshot(1, @[output], @[surface(1, 10)])
    scene.bindings = @[SnapshotBinding(action: 29, sessionOperationSlot: 1)]
    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
      cause: ProjectionCause(
        kind: ProjectionCauseKind.action, activationSerial: 19, action: 29
      ),
    )
    var session = initPolicySession()
    expect PolicySessionError:
      discard session.prepare(scene, request, 1)

  test "a socket session settles several outcomes with monotonic transactions":
    var serverBytes: seq[byte]
    serverBytes.appendWelcome(9)
    serverBytes.appendWireCycle(9, 1, 11, 101, 201, 1, ProjectionOutcomeKind.committed)
    serverBytes.appendWireCycle(
      9, 2, 12, 102, 202, 2, ProjectionOutcomeKind.rejectedStale
    )
    serverBytes.appendWireCycle(
      9, 2, 13, 103, 203, 3, ProjectionOutcomeKind.disconnected
    )
    let clientWire = serverBytes.runWireSession()
    check clientWire.u16At(6) == uint16(ord(MessageKind.clientHello))
    check clientWire.proposalTransactions() == @[1'u64, 2'u64, 3'u64]

  test "a timed-out action cannot alter the next complete projection":
    var serverBytes: seq[byte]
    serverBytes.appendWelcome(9)
    serverBytes.appendWireCycle(9, 1, 11, 101, 201, 1, ProjectionOutcomeKind.committed)
    serverBytes.appendWireCycle(
      9, 2, 12, 102, 202, 2, ProjectionOutcomeKind.timedOut, 1, 3
    )
    serverBytes.appendWireCycle(
      9, 2, 13, 103, 203, 3, ProjectionOutcomeKind.disconnected
    )
    let clientWire = serverBytes.runWireSession()
    check clientWire.proposalTransactions() == @[1'u64, 2'u64, 3'u64]
    check clientWire.projectionPlacementCounts() == @[1'u32, 0'u32, 1'u32]

  test "a supervised reconnect negotiates a fresh epoch and transaction space":
    var firstServer: seq[byte]
    firstServer.appendWelcome(9)
    firstServer.appendWireCycle(
      9, 1, 11, 101, 201, 1, ProjectionOutcomeKind.disconnected
    )
    check firstServer.runWireSession().proposalTransactions() == @[1'u64]

    var replacementServer: seq[byte]
    replacementServer.appendWelcome(10)
    replacementServer.appendWireCycle(
      10, 2, 21, 102, 202, 1, ProjectionOutcomeKind.disconnected
    )
    check replacementServer.runWireSession().proposalTransactions() == @[1'u64]

  test "a reconciled private checkpoint requests one bounded fresh cycle":
    let directory = createTempDir("hagia-refresh-", "")
    defer:
      delEnv("HAGIA_POLICY_CHECKPOINT")
      if fileExists(directory / "policy.checkpoint"):
        removeFile(directory / "policy.checkpoint")
      removeDir(directory)
    let path = directory / "policy.checkpoint"
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    var adapter = initPolicyAdapter()
    adapter.reconcile(snapshot(1, @[output], @[surface(1, 10)]))
    path.savePolicyCheckpoint(adapter)
    putEnv("HAGIA_POLICY_CHECKPOINT", path)

    var serverBytes: seq[byte]
    serverBytes.appendWelcome(9)
    serverBytes.appendWireCycle(9, 1, 11, 101, 201, 1, ProjectionOutcomeKind.committed)
    serverBytes.appendWireCycle(
      9, 2, 12, 102, 202, 3, ProjectionOutcomeKind.disconnected, 2
    )
    let clientWire = serverBytes.runWireSession()
    check clientWire.proposalTransactions() == @[1'u64, 3'u64]
    let refreshes = clientWire.policyDirtyFrames()
    require refreshes.len == 1
    check refreshes[0].transaction == 2
    check refreshes[0].payload.u64At(0) == 9
    check refreshes[0].payload.u64At(8) == 2
    check refreshes[0].payload.u16At(16) == 1
    check refreshes[0].payload.u64At(20) == 10

  test "projection outcomes reject unknown status values":
    var payload: seq[byte]
    payload.addU64(7)
    payload.addU64(1)
    payload.addU64(2)
    payload.addU16(6)
    payload.addU16(0)
    expect PolicyClientError:
      discard Frame(
        kind: MessageKind.projectionOutcome, transaction: 1, payload: payload
      ).decodeProjectionOutcome()

  test "only a committed outcome promotes reconciled state":
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let firstSnapshot = snapshot(1, @[output], @[surface(1, 10)])
    let firstRequest = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
    )
    var session = initPolicySession()
    discard session.prepare(firstSnapshot, firstRequest, 1)
    session.settle(
      ProjectionOutcome(
        transaction: 1,
        connectionEpoch: 7,
        requestId: 1,
        sceneGeneration: 2,
        kind: ProjectionOutcomeKind.committed,
      )
    )
    let logical = session.committedAdapter().logicalWindow(1, 1)
    require logical.isSome
    check session.committedGeneration() == 2

    var changedOutput = output
    changedOutput.width = 1200
    let secondSnapshot =
      snapshot(2, @[changedOutput], @[surface(1, 10, 2), surface(2, 10)])
    let secondRequest = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 2,
      sceneGeneration: 2,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
    )
    discard session.prepare(secondSnapshot, secondRequest, 2)
    session.settle(
      ProjectionOutcome(
        transaction: 2,
        connectionEpoch: 7,
        requestId: 2,
        sceneGeneration: 2,
        kind: ProjectionOutcomeKind.rejectedStale,
      )
    )
    check session.committedAdapter().logicalWindow(2, 1).isNone
    check session.committedAdapter().logicalWindow(1, 1) == logical
    check session.committedAdapter().model().outputIds().len == 1
    check session
      .committedAdapter()
      .model()
      .output(session.committedAdapter().model().outputIds()[0])
      .get().bounds.width == 800

  test "every noncommitted outcome discards the pending candidate":
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let scene = snapshot(1, @[output], @[surface(1, 10)])
    var transaction = 1'u64
    for kind in [
      ProjectionOutcomeKind.rejectedStale, ProjectionOutcomeKind.rejectedInvalid,
      ProjectionOutcomeKind.timedOut, ProjectionOutcomeKind.disconnected,
    ]:
      var session = initPolicySession()
      let request = ProjectionRequest(
        connectionEpoch: 9,
        requestId: transaction,
        sceneGeneration: 1,
        policyGeneration: 1,
        affectedOutputs: @[10'u64],
      )
      discard session.prepare(scene, request, transaction)
      session.settle(
        ProjectionOutcome(
          transaction: transaction,
          connectionEpoch: 9,
          requestId: transaction,
          sceneGeneration: 1,
          kind: kind,
        )
      )
      check not session.hasPending()
      check session.committedAdapter().model().outputIds().len == 0
      inc transaction

  test "a mismatched outcome cannot consume the pending candidate":
    let output = SnapshotOutput(output: 10, generation: 1, width: 800, height: 600)
    let scene = snapshot(1, @[output], @[surface(1, 10)])
    let request = ProjectionRequest(
      connectionEpoch: 7,
      requestId: 1,
      sceneGeneration: 1,
      policyGeneration: 1,
      affectedOutputs: @[10'u64],
    )
    var session = initPolicySession()
    discard session.prepare(scene, request, 1)
    expect PolicySessionError:
      session.settle(
        ProjectionOutcome(
          transaction: 2,
          connectionEpoch: 7,
          requestId: 1,
          sceneGeneration: 2,
          kind: ProjectionOutcomeKind.committed,
        )
      )
    check session.hasPending()
    session.abort()
