import ./wm_translation
import ./wm_tab_groups
import ./wm_presentation
from ./policy_snapshot import applyOutputPolicyKey
import std/[net, options]

import ../config/policy_candidate
import ../types/[config_values, handoff, session, wm_v1, wm_presentation]
import
  ./[policy_codec, policy_loop, policy_semantics, policy_transport, policy_wire, wm_v1]

export PolicyClientError, policy_codec

type PolicyClient = ref object
  socket: Socket
  connectionEpoch: uint64
  capabilities: uint64
  # Limits Sophia selected for this connection. They are bounded by this
  # client's own constants at negotiation, but the negotiated value governs:
  # a server may advertise less than the protocol maximum.
  maxChunkBytes: int
  nextTransaction: uint64
  readTimeoutMsec: int
  presentationReceipts: seq[PresentationReceipt]

proc receiveRawFrame(client: PolicyClient): Frame =
  let header = client.socket.receiveExact(frameHeaderLen, client.readTimeoutMsec)
  let payloadLen = int(header.u32At(16))
  if payloadLen > maxPayloadLen:
    fail("policy frame payload is excessive")
  let payload = client.socket.receiveExact(payloadLen, client.readTimeoutMsec)
  var bytes = header
  bytes.add(payload)
  bytes.decodeFrame()

proc receiveFrame(client: PolicyClient): Frame =
  while true:
    result = client.receiveRawFrame()
    if result.kind != MessageKind.presentationOutcome:
      return
    if client.presentationReceipts.len >= maxPendingPresentationReceipts:
      fail("pending presentation receipts exceed the bound")
    client.presentationReceipts.add(
      result.decodePresentationReceipt(client.connectionEpoch, client.capabilities)
    )

proc receiveFrame(client: PolicyClient, kind: MessageKind): Frame =
  result = client.receiveFrame()
  if result.kind != kind:
    fail("unexpected policy message kind")

const chunkHeaderLen = 16

proc sendFrame(client: PolicyClient, frame: Frame) =
  # A chunk's record bytes are bounded by the limit Sophia selected, not by the
  # protocol maximum this client happens to compile with. The two are equal
  # today, which is exactly why the check has to name the negotiated value.
  if frame.kind == MessageKind.projectionChunk and client.maxChunkBytes > 0 and
      frame.payload.len - chunkHeaderLen > client.maxChunkBytes:
    fail("policy projection chunk exceeds the negotiated limit")
  client.socket.send(frame.encodeFrame().toBinaryString())

proc requestsPointerFocus(candidate: AuthorityCandidate): bool =
  ## Negotiation happens before the candidate is validated for real, and an
  ## invalid profile must still reach the stage that rejects it by name rather
  ## than dying at connect. One that will not parse asks for nothing; the
  ## rejection it has coming arrives moments later, from the path that owns it.
  try:
    candidate.policyCandidateSettings().focusFollowsMouse
  except CatchableError:
    false

proc negotiatePolicy(
    socket: Socket,
    requestConfiguration: bool,
    requestProfileActivation = false,
    requestPointerFocus = false,
): PolicyClient =
  result = PolicyClient(
    socket: socket,
    nextTransaction: 1,
    readTimeoutMsec: (if requestProfileActivation: 4_000 else: -1),
  )
  var payload: seq[byte]
  payload.addU16(3)
  payload.addU16(3)
  # Request only behavior implemented by this client. The independent codec
  # still checks every experimental revision-3 message in the shared corpus.
  var optional =
    if requestConfiguration:
      capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
        capabilitySessionOperations
    else:
      0'u64
  if requestProfileActivation:
    optional = optional or capabilityProfileActivation
  # Asked for only when the profile turns focus-follows-mouse on. A server told
  # nothing sends nothing, so the default costs no cycle at all rather than one
  # per pointer crossing that the reducer would discard.
  if requestPointerFocus:
    optional = optional or capabilityPointerFocus
  payload.addU64(
    capabilityBindings or capabilityActions or capabilityMultiOutput or
      capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement or
      optional or capabilityTabGroups or capabilityTranslationGroups or
      capabilityOutputActions or capabilityOutputPolicyKeys or capabilityLaunchOrigin or
      capabilityOutputLaunchContext or capabilitySurfaceInstances or
      capabilityPresentationActions
  )
  result.sendFrame(Frame(kind: MessageKind.clientHello, payload: payload))
  let welcome = result.receiveFrame(MessageKind.serverWelcome)
  if welcome.payload.u16At(0) != 3:
    fail("Sophia selected an unsupported policy revision")
  result.capabilities = welcome.payload.u64At(4)
  const requiredCapabilities =
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement
  if (result.capabilities and requiredCapabilities) != requiredCapabilities:
    fail("Sophia omitted a required policy capability")
  # Before the generic optional mask, which would otherwise answer a missing
  # pointer-focus bit with a message about native configuration.
  if requestPointerFocus and (result.capabilities and capabilityPointerFocus) == 0:
    fail("Sophia omitted pointer focus, which this profile's focus-follows-mouse needs")
  if requestConfiguration and (result.capabilities and optional) != optional:
    fail("Sophia omitted native policy configuration")
  if requestProfileActivation and
      (result.capabilities and capabilityProfileActivation) == 0:
    fail("Sophia omitted desktop profile activation")
  result.connectionEpoch = welcome.payload.u64At(12)
  if result.connectionEpoch == 0 or welcome.payload.u16At(20) == 0 or
      welcome.payload.u16At(20) > uint16(maxOutputs) or welcome.payload.u32At(24) == 0 or
      welcome.payload.u32At(24) > uint32(maxSurfaces) or
      welcome.payload.u16At(22) > uint16(maxBindings) or welcome.payload.u32At(28) == 0 or
      welcome.payload.u32At(28) > uint32(maxPayloadLen):
    fail("Sophia advertised invalid policy limits")
  result.maxChunkBytes = int(welcome.payload.u32At(28))
  injectConfiguredFault("negotiated")

proc connectPolicy(
    path: string,
    requestConfiguration: bool,
    requestProfileActivation = false,
    requestPointerFocus = false,
): PolicyClient =
  path.connectWhenReady().negotiatePolicy(
    requestConfiguration, requestProfileActivation, requestPointerFocus
  )

proc receiveSnapshot(client: PolicyClient): PolicySnapshot =
  let begin = client.receiveFrame(MessageKind.snapshotBegin)
  let connectionEpoch = begin.payload.u64At(0)
  let generation = begin.payload.u64At(8)
  let activeOutput = begin.payload.u64At(16)
  let chunkCount = int(begin.payload.u16At(24))
  let declaredOutputs = int(begin.payload.u16At(26))
  let declaredSurfaces = int(begin.payload.u32At(28))
  let declaredActions = int(begin.payload.u16At(32))
  let declaredSessionOperations = int(begin.payload.u16At(34))
  if connectionEpoch != client.connectionEpoch or generation == 0 or chunkCount == 0 or
      activeOutput == 0 or declaredOutputs == 0 or declaredOutputs > maxOutputs or
      declaredSurfaces > maxSurfaces or declaredActions > maxBindings or
      declaredSessionOperations > maxBindings:
    fail("policy snapshot header is invalid")
  var outputs: seq[SnapshotOutput]
  var surfaces: seq[SnapshotSurface]
  var actions: seq[SnapshotAction]
  var sessionOperations: seq[SnapshotSessionOperation]
  var classifications: seq[SnapshotSurfaceClassification]
  var launchOrigins: seq[LaunchOriginRecord]
  for ordinal in 0 ..< chunkCount:
    let chunk = client.receiveFrame(MessageKind.snapshotChunk)
    if chunk.transaction != begin.transaction or
        chunk.payload.u64At(0) != client.connectionEpoch or
        int(chunk.payload.u16At(8)) != ordinal:
      fail("policy snapshot chunk identity is invalid")
    let recordKind = chunk.payload.u16At(10)
    let itemCount = int(chunk.payload.u32At(12))
    if itemCount == 0:
      fail("empty policy snapshot chunk")
    case recordKind
    of 1:
      if chunk.payload.len != 16 + itemCount * snapshotOutputSize or
          outputs.len + itemCount > declaredOutputs:
        fail("policy output chunk count is invalid")
      for index in 0 ..< itemCount:
        outputs.add(
          chunk.payload.recordBytes(index, snapshotOutputSize).decodeSnapshotOutput()
        )
    of 2:
      if chunk.payload.len != 16 + itemCount * snapshotSurfaceSize or
          surfaces.len + itemCount > declaredSurfaces:
        fail("policy surface chunk count is invalid")
      for index in 0 ..< itemCount:
        surfaces.add(
          chunk.payload.recordBytes(index, snapshotSurfaceSize).decodeSnapshotSurface()
        )
    of 3:
      if chunk.payload.len != 16 + itemCount * snapshotActionSize or
          actions.len + itemCount > declaredActions:
        fail("policy action chunk count is invalid")
      for index in 0 ..< itemCount:
        actions.add(
          chunk.payload.recordBytes(index, snapshotActionSize).decodeSnapshotAction()
        )
    of 4:
      if chunk.payload.len != 16 + itemCount * snapshotSessionOperationSize or
          sessionOperations.len + itemCount > declaredSessionOperations:
        fail("policy session-operation chunk count is invalid")
      for index in 0 ..< itemCount:
        sessionOperations.add(
          chunk.payload
            .recordBytes(index, snapshotSessionOperationSize)
            .decodeSnapshotSessionOperation()
        )
    else:
      fail("unknown policy snapshot record kind")
  # Frozen begin/end counts cover only ordinary chunks. A negotiated extension
  # is appended after that prefix with dense ordinals, then SnapshotEnd closes
  # the transfer without changing either frozen message layout.
  var nextOrdinal = chunkCount
  var finish = client.receiveFrame()
  while finish.kind == MessageKind.snapshotChunk:
    let recordKind = finish.payload.u16At(10)
    let admitted =
      (
        recordKind == snapshotSurfaceClassificationRecordKind and
        (client.capabilities and capabilityLaunchPlacement) != 0
      ) or (
        recordKind == snapshotLaunchOriginRecordKind and
        (client.capabilities and capabilityLaunchOrigin) != 0
      ) or (
        recordKind == snapshotOutputPolicyKeyRecordKind and
        (client.capabilities and capabilityOutputPolicyKeys) != 0
      )
    if not admitted or finish.transaction != begin.transaction or
        finish.payload.u64At(0) != client.connectionEpoch or
        int(finish.payload.u16At(8)) != nextOrdinal:
      fail("policy snapshot extension identity is invalid")
    let itemCount = int(finish.payload.u32At(12))
    if recordKind == snapshotOutputPolicyKeyRecordKind:
      if itemCount == 0 or itemCount > maxOutputs or
          finish.payload.len != 16 + itemCount * 24:
        fail("output policy key count is invalid")
      for index in 0 ..< itemCount:
        let at = 16 + index * 24
        let output = finish.payload.u64At(at)
        let generation = finish.payload.u64At(at + 8)
        let key = finish.payload.u64At(at + 16)
        outputs.applyOutputPolicyKey(output, generation, key)
    elif recordKind == snapshotSurfaceClassificationRecordKind:
      if itemCount == 0 or
          finish.payload.len != 16 + itemCount * snapshotSurfaceClassificationSize or
          classifications.len + itemCount > maxSurfaces:
        fail("policy surface-classification chunk count is invalid")
      for index in 0 ..< itemCount:
        classifications.add(
          finish.payload
            .recordBytes(index, snapshotSurfaceClassificationSize)
            .decodeSnapshotSurfaceClassification()
        )
    else:
      if itemCount == 0 or finish.payload.len != 16 + itemCount * launchOriginRecordSize or
          launchOrigins.len + itemCount > maxLaunchOriginRecords:
        fail("policy launch origin chunk count is invalid")
      for index in 0 ..< itemCount:
        launchOrigins.add(
          finish.payload
            .recordBytes(index, launchOriginRecordSize)
            .decodeLaunchOriginRecord()
        )
    inc nextOrdinal
    finish = client.receiveFrame()
  if finish.kind != MessageKind.snapshotEnd:
    fail("policy snapshot extension was not followed by its end")
  if finish.transaction != begin.transaction or
      finish.payload.u64At(0) != client.connectionEpoch or
      finish.payload.u64At(8) != generation or
      finish.payload.u16At(16) != uint16(chunkCount) or outputs.len != declaredOutputs or
      surfaces.len != declaredSurfaces or actions.len != declaredActions or
      sessionOperations.len != declaredSessionOperations:
    fail("policy snapshot did not settle exactly")
  result = PolicySnapshot(
    generation: generation,
    activeOutput: activeOutput,
    outputs: outputs,
    surfaces: surfaces,
    actions: actions,
    sessionOperations: sessionOperations,
    classifications: classifications,
    launchOrigins: launchOrigins,
  )
  result.validateSnapshot()

proc receiveProjectionRequest(client: PolicyClient): ProjectionRequest =
  result = client.receiveFrame().decodeProjectionRequest(
      client.connectionEpoch, client.capabilities
    )

proc allocateTransaction(client: PolicyClient): uint64 =
  result = client.nextTransaction
  inc client.nextTransaction
  if result == 0 or client.nextTransaction == 0:
    fail("policy transaction identity space is exhausted")

proc installConfiguration(
    client: PolicyClient, configuration: PolicyConfiguration
): PolicyConfigurationOutcome =
  # The legacy frame carries colours with an opaque alpha byte.
  var payload: seq[byte]
  payload.addU64(configuration.connectionEpoch)
  payload.addU64(configuration.generation)
  payload.addU16(uint16(configuration.actions.len))
  payload.addU16(configuration.styleBits)
  payload.addU32(configuration.focusWidth)
  payload.addU32(0xff000000'u32 or configuration.focusRgb)
  payload.addU32(configuration.frameWidth)
  payload.addU32(0xff000000'u32 or configuration.frameFocusedRgb)
  payload.addU32(0xff000000'u32 or configuration.frameUnfocusedRgb)
  for action in configuration.actions:
    payload.addAction(action)
  client.sendFrame(
    Frame(
      kind: MessageKind.policyConfiguration,
      transaction: configuration.transaction,
      payload: payload,
    )
  )
  let outcome = client.receiveFrame(MessageKind.policyConfigurationOutcome)
  let kind = projectionOutcomeFromCode(outcome.payload.u16At(16))
  if kind.isNone:
    fail("Sophia rejected Hagia's policy configuration")
  PolicyConfigurationOutcome(
    transaction: outcome.transaction,
    connectionEpoch: outcome.payload.u64At(0),
    generation: outcome.payload.u64At(8),
    kind: kind.get(),
  )

proc sendProjection(
    client: PolicyClient,
    request: ProjectionRequest,
    transaction: uint64,
    projection: PolicyProjection,
): ProjectionOutcome =
  var outputBytes: seq[byte]
  var placementBytes: seq[byte]
  var indicatorBytes: seq[byte]
  var statusBytes: seq[byte]
  var placementCount = 0
  for output in projection.outputs:
    outputBytes.add(output.output.encodeProjectionOutput())
    for placement in output.placements:
      placementBytes.add(placement.encodeProjectionPlacement())
      inc placementCount
  for indicator in projection.indicators:
    indicatorBytes.add(indicator.encodeProjectionIndicator())
  for status in projection.outputStatuses:
    statusBytes.add(status.encodeProjectionOutputStatus())

  if projection.outputs.len != request.affectedOutputs.len:
    fail("projection output count does not match the request")
  let chunkCount =
    1 + (if placementCount == 0: 0 else: 1) +
    (if projection.indicators.len == 0: 0 else: 1) +
    (if projection.outputStatuses.len == 0: 0 else: 1)
  var beginPayload: seq[byte]
  beginPayload.addU64(client.connectionEpoch)
  beginPayload.addU64(request.requestId)
  beginPayload.addU64(request.sceneGeneration)
  beginPayload.addU64(projection.activeOutput)
  beginPayload.addU16(uint16(chunkCount))
  beginPayload.addU16(uint16(projection.outputs.len))
  beginPayload.addU32(uint32(placementCount))
  beginPayload.addU16(uint16(projection.indicators.len))
  beginPayload.addU16(uint16(projection.outputStatuses.len))
  client.sendFrame(
    Frame(
      kind: MessageKind.projectionBegin, transaction: transaction, payload: beginPayload
    )
  )

  var outputPayload: seq[byte]
  outputPayload.addU64(client.connectionEpoch)
  outputPayload.addU16(0)
  outputPayload.addU16(1)
  outputPayload.addU32(uint32(projection.outputs.len))
  outputPayload.add(outputBytes)
  client.sendFrame(
    Frame(
      kind: MessageKind.projectionChunk,
      transaction: transaction,
      payload: outputPayload,
    )
  )
  if placementCount > 0:
    var placementPayload: seq[byte]
    placementPayload.addU64(client.connectionEpoch)
    placementPayload.addU16(1)
    placementPayload.addU16(2)
    placementPayload.addU32(uint32(placementCount))
    placementPayload.add(placementBytes)
    client.sendFrame(
      Frame(
        kind: MessageKind.projectionChunk,
        transaction: transaction,
        payload: placementPayload,
      )
    )
  var nextOrdinal = if placementCount > 0: 2'u16 else: 1'u16
  if projection.indicators.len > 0:
    var payload: seq[byte]
    payload.addU64(client.connectionEpoch)
    payload.addU16(nextOrdinal)
    payload.addU16(3)
    payload.addU32(uint32(projection.indicators.len))
    payload.add(indicatorBytes)
    client.sendFrame(
      Frame(
        kind: MessageKind.projectionChunk, transaction: transaction, payload: payload
      )
    )
    inc nextOrdinal
  if projection.outputStatuses.len > 0:
    var payload: seq[byte]
    payload.addU64(client.connectionEpoch)
    payload.addU16(nextOrdinal)
    payload.addU16(4)
    payload.addU32(uint32(projection.outputStatuses.len))
    payload.add(statusBytes)
    client.sendFrame(
      Frame(
        kind: MessageKind.projectionChunk, transaction: transaction, payload: payload
      )
    )

  var extensionOrdinal = uint16(chunkCount)
  if projection.tabGroups.len > 0:
    if (client.capabilities and capabilityTabGroups) == 0:
      fail("Sophia did not negotiate tab groups")
    if projection.tabGroups.len > maxTabGroups:
      fail("too many tab groups")
    var groups, members: seq[byte]
    var memberCount = 0
    for group in projection.tabGroups:
      groups.add(group.encodeTabGroup())
      for member in group.members:
        members.add(group.encodeTabMember(member))
        inc memberCount
    if memberCount > maxTabMembers:
      fail("too many tab members")
    var ordinal = extensionOrdinal
    for (kind, size, data) in [
      (projectionTabGroupRecordKind, projectionTabGroupSize, groups),
      (projectionTabMemberRecordKind, projectionTabMemberSize, members),
    ]:
      let limit = (client.maxChunkBytes div size) * size
      if limit == 0:
        fail("negotiated tab chunk limit is too small")
      var start = 0
      while start < data.len:
        let finish = min(start + limit, data.len)
        var payload: seq[byte]
        payload.addU64(client.connectionEpoch)
        payload.addU16(ordinal)
        payload.addU16(kind)
        payload.addU32(uint32((finish - start) div size))
        payload.add(data[start ..< finish])
        client.sendFrame(
          Frame(
            kind: MessageKind.projectionChunk,
            transaction: transaction,
            payload: payload,
          )
        )
        inc ordinal
        start = finish
    extensionOrdinal = ordinal

  if (client.capabilities and capabilityTranslationGroups) != 0:
    if projection.translationGroups.len > maxOutputs:
      fail("too many translation groups")
    var groups, members: seq[byte]
    for group in projection.translationGroups:
      if group.group == 0 or group.members.len == 0:
        fail("empty translation group")
      groups.add(group.encodeTranslationGroup())
      for member in group.members:
        members.add(group.encodeTranslationMember(member))
    if members.len div projectionTranslationMemberSize > maxSurfaces:
      fail("too many translation members")
    for (kind, size, data) in [
      (projectionTranslationGroupRecordKind, projectionTranslationGroupSize, groups),
      (projectionTranslationMemberRecordKind, projectionTranslationMemberSize, members),
    ]:
      let limit = (client.maxChunkBytes div size) * size
      if limit == 0:
        fail("negotiated translation chunk limit is too small")
      var start = 0
      while start < data.len:
        let finish = min(start + limit, data.len)
        var payload: seq[byte]
        payload.addU64(client.connectionEpoch)
        payload.addU16(extensionOrdinal)
        payload.addU16(kind)
        payload.addU32(uint32((finish - start) div size))
        payload.add(data[start ..< finish])
        client.sendFrame(
          Frame(
            kind: MessageKind.projectionChunk,
            transaction: transaction,
            payload: payload,
          )
        )
        inc extensionOrdinal
        start = finish

  # Launch contexts. Published on every projection; Sophia only trusts the ones
  # that belong to a cycle it committed.
  if (client.capabilities and capabilityLaunchOrigin) != 0 and
      projection.launchContexts.len > 0:
    if projection.launchContexts.len > maxLaunchOriginRecords:
      fail("too many launch contexts")
    var data: seq[byte]
    for record in projection.launchContexts:
      data.add(record.encodeLaunchOriginRecord())
    let limit =
      (client.maxChunkBytes div launchOriginRecordSize) * launchOriginRecordSize
    if limit == 0:
      fail("negotiated launch context chunk limit is too small")
    var start = 0
    while start < data.len:
      let finish = min(start + limit, data.len)
      var payload: seq[byte]
      payload.addU64(client.connectionEpoch)
      payload.addU16(extensionOrdinal)
      payload.addU16(projectionLaunchContextRecordKind)
      payload.addU32(uint32((finish - start) div launchOriginRecordSize))
      payload.add(data[start ..< finish])
      client.sendFrame(
        Frame(
          kind: MessageKind.projectionChunk, transaction: transaction, payload: payload
        )
      )
      inc extensionOrdinal
      start = finish

  if (client.capabilities and capabilityOutputLaunchContext) != 0:
    if projection.outputLaunchContexts.len > maxOutputs:
      fail("too many output launch contexts")
    # Each bounded record is its own extension chunk; honor small negotiated
    # limits without changing the frozen counted prefix.
    if client.maxChunkBytes < outputLaunchContextSize:
      fail("output launch context chunk limit too small")
    for record in projection.outputLaunchContexts:
      var payload: seq[byte]
      payload.addU64(client.connectionEpoch)
      payload.addU16(extensionOrdinal)
      payload.addU16(projectionOutputLaunchContextRecordKind)
      payload.addU32(1)
      payload.add(record.encodeOutputLaunchContext())
      client.sendFrame(
        Frame(
          kind: MessageKind.projectionChunk, transaction: transaction, payload: payload
        )
      )
      inc extensionOrdinal

  if projection.presentation.isSome:
    let required = capabilitySurfaceInstances or capabilityPresentationActions
    if (client.capabilities and required) != required:
      fail("Sophia did not negotiate WM presentation")
    let records = projection.presentation.get().encodePresentation()
    for index, data in records:
      let size = presentationRecordSizes[index]
      let limit = (client.maxChunkBytes div size) * size
      if limit == 0:
        fail("presentation chunk limit is too small")
      var start = 0
      while start < data.len:
        let finish = min(start + limit, data.len)
        var payload: seq[byte]
        payload.addU64(client.connectionEpoch)
        payload.addU16(extensionOrdinal)
        payload.addU16(presentationRecordKinds[index])
        payload.addU32(uint32((finish - start) div size))
        payload.add(data[start ..< finish])
        client.sendFrame(
          Frame(
            kind: MessageKind.projectionChunk,
            transaction: transaction,
            payload: payload,
          )
        )
        inc extensionOrdinal
        start = finish

  var endPayload: seq[byte]
  endPayload.addU64(client.connectionEpoch)
  endPayload.addU64(request.requestId)
  endPayload.addU64(request.sceneGeneration)
  endPayload.addU16(uint16(chunkCount))
  endPayload.addU16(0)
  client.sendFrame(
    Frame(
      kind: MessageKind.projectionEnd, transaction: transaction, payload: endPayload
    )
  )
  injectConfiguredFault("projection_submitted")
  let frame = client.receiveFrame(MessageKind.projectionOutcome)
  result = frame.decodeProjectionOutcome()
  if result.transaction != transaction or
      result.connectionEpoch != client.connectionEpoch or
      result.requestId != request.requestId or result.sceneGeneration == 0:
    fail("Sophia returned a mismatched policy outcome")

proc sendSessionOperation(
    client: PolicyClient, intent: SessionOperationIntent
): ProjectionOutcomeKind =
  var payload: seq[byte]
  payload.addU64(client.connectionEpoch)
  payload.addU64(intent.requestId)
  payload.addU64(intent.operation)
  payload.addU32(intent.targetIndex)
  payload.addU32(intent.targetGeneration)
  let transaction = client.allocateTransaction()
  client.sendFrame(
    Frame(
      kind: MessageKind.sessionOperationRequest,
      transaction: transaction,
      payload: payload,
    )
  )
  injectConfiguredFault("operation_submitted")
  let outcome = client.receiveFrame(MessageKind.sessionOperationOutcome)
  let raw = outcome.payload.u16At(16)
  if outcome.transaction != transaction or
      outcome.payload.u64At(0) != client.connectionEpoch or
      outcome.payload.u64At(8) != intent.requestId or raw < 1 or raw > 5:
    fail("Sophia returned an invalid session-operation outcome")
  injectConfiguredFault("operation_outcome_received")
  ProjectionOutcomeKind(raw)

proc requestDirty(client: PolicyClient, dirty: PolicyDirty) =
  var payload: seq[byte]
  payload.addU64(client.connectionEpoch)
  payload.addU64(dirty.policyGeneration)
  payload.addU16(uint16(dirty.affectedOutputs.len))
  payload.addU16(0)
  for output in dirty.affectedOutputs:
    payload.addU64(output)
  client.sendFrame(
    Frame(
      kind: MessageKind.policyDirty,
      transaction: client.allocateTransaction(),
      payload: payload,
    )
  )

proc frameWire(client: PolicyClient): PolicyWire =
  ## The current IPC as a policy wire: frames, their refusals, ordering and
  ## timeouts stay exactly as they were. It states no session-operation
  ## expectation, so none is reported.
  proc receiveProfileCommand(
      expected: set[ProfileHandoffMsgKind]
  ): Option[ProfileHandoffMsg] =
    let frame = client.receiveFrame()
    let kind =
      case frame.kind
      of MessageKind.profilePrepare:
        some(ProfileHandoffMsgKind.prepare)
      of MessageKind.profileActivate:
        some(ProfileHandoffMsgKind.activate)
      of MessageKind.profileRollback:
        some(ProfileHandoffMsgKind.rollback)
      else:
        none(ProfileHandoffMsgKind)
    if kind.isNone or kind.get() notin expected:
      return none(ProfileHandoffMsg)
    some(ProfileHandoffMsg(kind: kind.get(), command: frame.decodeProfileCommand()))

  proc completeProfile(kind: ProfileHandoffMsgKind, completion: ProfileCompletion) =
    let response =
      case kind
      of ProfileHandoffMsgKind.prepare: MessageKind.profilePrepared
      of ProfileHandoffMsgKind.activate: MessageKind.profileActive
      of ProfileHandoffMsgKind.rollback: MessageKind.profileRolledBack
    client.sendFrame(
      response.profileCompletionFrame(
        completion.transaction, completion.identity, completion.outcome
      )
    )

  proc enterPolicyTraffic() =
    client.readTimeoutMsec = -1

  proc allocate(): uint64 =
    client.allocateTransaction()

  proc install(configuration: PolicyConfiguration): PolicyConfigurationOutcome =
    client.installConfiguration(configuration)

  proc snapshot(): PolicySnapshot =
    client.receiveSnapshot()

  proc request(): ProjectionRequest =
    client.receiveProjectionRequest()

  proc project(
      request: ProjectionRequest, transaction: uint64, projection: PolicyProjection
  ): ProjectionCompletion =
    ProjectionCompletion(
      outcome: client.sendProjection(request, transaction, projection),
      expectSessionOperation: none(bool),
    )

  proc operate(intent: SessionOperationIntent): ProjectionOutcomeKind =
    client.sendSessionOperation(intent)

  proc dirty(value: PolicyDirty) =
    client.requestDirty(value)

  proc receipts(): seq[PresentationReceipt] =
    result = client.presentationReceipts
    client.presentationReceipts = @[]

  proc close() =
    client.socket.close()

  PolicyWire(
    connectionEpoch: client.connectionEpoch,
    capabilities: client.capabilities,
    receiveProfileCommand: receiveProfileCommand,
    completeProfile: completeProfile,
    enterPolicyTraffic: enterPolicyTraffic,
    allocateTransaction: allocate,
    installConfiguration: install,
    receiveSnapshot: snapshot,
    receiveRequest: request,
    submitProjection: project,
    submitSessionOperation: operate,
    requestDirty: dirty,
    takeReceipts: receipts,
    close: close,
  )

proc runStartupProfileHandoff*(
    socket: Socket, candidate: AuthorityCandidate
): StartupProfileHandoffDisposition =
  ## Startup-only proof entry point. It never enters the normal policy cycle.
  socket.negotiatePolicy(false, true).frameWire().activateProfileCandidate(candidate)

## Exercise a bounded sequence of complete public-policy cycles without Triad
## machinery. The shared revision-3 corpus uses one connection so output loss
## and generational return exercise the client's retained private identity.
proc runPolicyCycles*(path: string, cycleCount: int) =
  if cycleCount < 1 or cycleCount > 16:
    fail("policy proof cycle count is invalid")
  path.connectPolicy(false).frameWire().runPolicyCycles(cycleCount)

## Exercise the smallest complete public-policy cycle without Triad machinery.
proc runOnePolicyCycle*(path: string) =
  path.runPolicyCycles(1)

proc runPolicySession*(path: string) =
  path.connectPolicy(true).frameWire().runPolicySession(true)

proc runPolicySession*(path: string, candidate: AuthorityCandidate) =
  path
    .connectPolicy(true, false, candidate.requestsPointerFocus())
    .frameWire()
    .runPolicySession(true, some(candidate))

proc runProfileActivatedPolicySession*(path: string, candidate: AuthorityCandidate) =
  ## Reuses the authenticated connection only after exact Active settlement.
  path
    .connectPolicy(true, true, candidate.requestsPointerFocus())
    .frameWire()
    .runActivatedPolicy(candidate)

proc runPolicySessionOnSocket*(socket: Socket) =
  socket.negotiatePolicy(false).frameWire().runPolicySession(false)

proc runProfileActivatedPolicySessionOnSocket*(
    socket: Socket, candidate: AuthorityCandidate
) =
  ## Socket-injected conformance entry point with production-equivalent
  ## activation and configuration ordering.
  socket
    .negotiatePolicy(true, true, candidate.requestsPointerFocus())
    .frameWire()
    .runActivatedPolicy(candidate)
