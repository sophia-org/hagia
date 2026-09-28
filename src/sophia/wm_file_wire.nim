## Hagia policy callbacks over one C SDK session. The SDK owns all protocol
## bytes, fids, event assembly, submission custody, acks and snapshot pins.
import std/monotimes
import std/net
import std/nativesockets
import std/options
import std/posix
import ../types/desktop_sdk
import ../types/sdk_candidate
import ../types/handoff
import ../types/session
import ../types/wm_presentation
import ../types/wm_v1
import ./desktop_sdk
import ./sdk_candidate
import ./sdk_cycle
import ./sdk_rows
import ./sdk_snapshot
import ./policy_signals
import ./policy_transport
import ./policy_wire

type FileWireOwner = ref object
  socket: Socket
  session: ptr Ws
  storage: pointer
  epoch, selected: uint64
  profileWaits: bool
  pendingRequest: Option[ProjectionRequest]
  receipts: seq[PresentationReceipt]

proc nowMillis(): uint64 =
  uint64(getMonoTime().ticks div 1_000_000)

proc close(owner: FileWireOwner) =
  if owner.session != nil:
    wsClose(owner.session)
    dealloc(owner.session)
    owner.session = nil
  if owner.storage != nil:
    dealloc(owner.storage)
    owner.storage = nil
  if owner.socket != nil:
    owner.socket.close()
    owner.socket = nil

template closing(owner: FileWireOwner, body: untyped): untyped =
  try:
    body
  except CatchableError:
    owner.close()
    raise

proc step(owner: FileWireOwner, deadline = 0'u64) =
  if owner.session == nil:
    fail("WM SDK session is closed")
  requireRunning()
  let now = nowMillis()
  if deadline != 0 and now >= deadline:
    fail("WM policy wait deadline expired")
  var wait = wsTimeout(owner.session, now)
  if wait < 0 or wait > 1000:
    wait = 1000
  if deadline != 0:
    wait = min(wait, cint(min(deadline - now, 1000)))
  var descriptors = [
    TPollfd(fd: wsPollFd(owner.session), events: wsPollEvents(owner.session)),
    TPollfd(fd: stopWakeFd(), events: POLLIN),
  ]
  if posix.poll(addr descriptors[0], Tnfds(2), wait) < 0 and errno != EINTR:
    fail("WM SDK poll failed")
  requireRunning()
  let status = wsDispatch(owner.session, descriptors[0].revents, 65536, nowMillis())
  if status != 0:
    fail(
      "WM SDK dispatch failed: " & $status & " remote=" & $wsRemoteError(owner.session)
    )

proc waitDeadline(owner: FileWireOwner): uint64 =
  if owner.profileWaits:
    nowMillis() + 4000
  else:
    0

proc consume(owner: FileWireOwner) =
  sdkCheck(wsConsume(owner.session))

proc drainReceipts(owner: FileWireOwner) =
  var record: WfRecord
  while wsEvent(owner.session, addr record) == 0 and record.header.kind == 25:
    if owner.receipts.len >= maxPendingPresentationReceipts:
      fail("pending presentation receipts exceed the bound")
    let v = record.value.presentationReceipt
    owner.receipts.add(
      PresentationReceipt(
        connectionEpoch: owner.epoch,
        publicationGeneration: v.publicationGeneration,
        output: v.output,
        outputGeneration: v.outputGeneration,
        presentationEpoch: v.presentationEpoch,
        outcome: PresentationOutcomeKind(v.outcome),
      )
    )
    owner.consume()

proc nextEvent(owner: FileWireOwner, deadline: uint64): WfRecord =
  while true:
    owner.drainReceipts()
    let status = wsEvent(owner.session, addr result)
    if status == 0:
      return
    if status != 1:
      sdkCheck(status)
    owner.step(deadline)

proc expect(record: WfRecord, kind: uint16) =
  if record.header.kind != kind:
    fail("unexpected policy message kind")

proc submit(owner: FileWireOwner, value: var WfRecord) =
  requireRunning()
  let deadline = nowMillis() + 4000
  var ticket: uint64
  while true:
    let status = wsSubmit(owner.session, addr value, deadline, addr ticket)
    if status == 0:
      break
    if status != 2:
      sdkCheck(status)
    owner.drainReceipts()
    owner.step(deadline)
  while true:
    var custody: WsCustody
    var wireError: uint32
    sdkCheck(wsOutcome(owner.session, ticket, addr custody, addr wireError))
    case custody
    of WsCustody.submitted:
      return
    # Submitted transfers custody, never policy acceptance.
    of WsCustody.admittedLocal, WsCustody.issued:
      discard
    else:
      fail("WM candidate lost custody: " & $custody & " remote=" & $wireError)
    owner.drainReceipts()
    owner.step(deadline)

proc submit(owner: FileWireOwner, candidate: var SdkCandidate) =
  candidate.bindRows()
  owner.submit(candidate.record)

proc profileKind(kind: uint16): Option[ProfileHandoffMsgKind] =
  case kind
  of 18:
    some(ProfileHandoffMsgKind.prepare)
  of 19:
    some(ProfileHandoffMsgKind.activate)
  of 20:
    some(ProfileHandoffMsgKind.rollback)
  else:
    none(ProfileHandoffMsgKind)

proc wire(owner: FileWireOwner): PolicyWire =
  proc receiveProfileCommand(
      expected: set[ProfileHandoffMsgKind]
  ): Option[ProfileHandoffMsg] =
    owner.closing:
      let record = owner.nextEvent(owner.waitDeadline())
      let kind = profileKind(record.header.kind)
      if kind.isNone or kind.get() notin expected:
        return none(ProfileHandoffMsg)
      let v = record.value.profile
      result = some(
        ProfileHandoffMsg(
          kind: kind.get(),
          command: ProfileCommand(
            transaction: v.transaction,
            identity: ProfileIdentity(
              connectionEpoch: owner.epoch,
              profileGeneration: v.generation,
              profileDigest: v.digest,
            ),
          ),
        )
      )
      owner.consume()

  proc completeProfile(kind: ProfileHandoffMsgKind, completion: ProfileCompletion) =
    owner.closing:
      if completion.identity.connectionEpoch != owner.epoch:
        fail("profile belongs to another epoch")
      var r: WfRecord
      case kind
      of ProfileHandoffMsgKind.prepare:
        r.header.kind = 257
      of ProfileHandoffMsgKind.activate:
        r.header.kind = 258
      of ProfileHandoffMsgKind.rollback:
        r.header.kind = 259
      r.value.profile = WfProfile(
        transaction: completion.transaction,
        generation: completion.identity.profileGeneration,
        digest: completion.identity.profileDigest,
        outcome: uint16(completion.outcome),
      )
      owner.submit(r)

  proc enterPolicyTraffic() =
    owner.profileWaits = false

  proc allocate(): uint64 =
    owner.closing:
      sdkCheck(wsNextTransaction(owner.session, addr result))

  proc install(configuration: PolicyConfiguration): PolicyConfigurationOutcome =
    owner.closing:
      if configuration.connectionEpoch != owner.epoch:
        fail("configuration belongs to another epoch")
      var candidate = configuration.configurationCandidate()
      owner.submit(candidate)
      let r = owner.nextEvent(owner.waitDeadline())
      r.expect(21)
      let v = r.value.configurationOutcome
      result = PolicyConfigurationOutcome(
        transaction: v.transaction,
        connectionEpoch: owner.epoch,
        generation: v.generation,
        kind: ProjectionOutcomeKind(v.outcome),
      )
      owner.consume()

  proc snapshot(): PolicySnapshot =
    owner.closing:
      let r = owner.nextEvent(owner.waitDeadline())
      r.expect(22)
      let request = r.policyRequest()
      # The SDK binds the current Cycle before its borrowed event is consumed.
      let deadline = nowMillis() + 12000
      sdkCheck(wsSnapshot(owner.session, deadline))
      owner.consume()
      var published: WfRecord
      while true:
        let status = wsSnapshotResult(owner.session, addr published)
        if status == 0:
          break
        if status != 1:
          sdkCheck(status)
        owner.drainReceipts()
        owner.step(deadline)
      result = published.policySnapshot(owner.epoch)
      sdkCheck(wsSnapshotRelease(owner.session))
      owner.pendingRequest = some(request)

  proc request(): ProjectionRequest =
    owner.closing:
      if owner.pendingRequest.isNone:
        fail("policy request without its Cycle")
      result = owner.pendingRequest.get()
      owner.pendingRequest = none(ProjectionRequest)

  proc project(
      request: ProjectionRequest, transaction: uint64, projection: PolicyProjection
  ): ProjectionCompletion =
    owner.closing:
      if request.connectionEpoch != owner.epoch:
        fail("projection belongs to another epoch")
      var candidate =
        projectionCandidate(request, transaction, projection, owner.selected)
      owner.submit(candidate)
      injectConfiguredFault("projection_submitted")
      let r = owner.nextEvent(owner.waitDeadline())
      r.expect(23)
      let v = r.value.projectionOutcome
      if v.transaction != transaction or v.requestId != request.requestId:
        fail("Sophia returned a mismatched policy outcome")
      result = ProjectionCompletion(
        outcome: ProjectionOutcome(
          transaction: v.transaction,
          connectionEpoch: owner.epoch,
          requestId: v.requestId,
          sceneGeneration: v.sceneGeneration,
          kind: ProjectionOutcomeKind(v.outcome),
        ),
        expectSessionOperation: some(v.expectSessionOperation != 0),
      )
      owner.consume()

  proc operate(intent: SessionOperationIntent): ProjectionOutcomeKind =
    owner.closing:
      let transaction = allocate()
      var r: WfRecord
      r.header.kind = 263
      r.value.sessionOperation = WfSessionOperation(
        transaction: transaction,
        requestId: intent.requestId,
        operation: intent.operation,
        target:
          WfSurface(index: intent.targetIndex, generation: intent.targetGeneration),
      )
      owner.submit(r)
      injectConfiguredFault("operation_submitted")
      let reply = owner.nextEvent(owner.waitDeadline())
      reply.expect(24)
      let v = reply.value.sessionOperationOutcome
      if v.transaction != transaction or v.requestId != intent.requestId:
        fail("Sophia returned an invalid session-operation outcome")
      result = ProjectionOutcomeKind(v.outcome)
      owner.consume()
      injectConfiguredFault("operation_outcome_received")

  proc dirty(value: PolicyDirty) =
    owner.closing:
      if value.affectedOutputs.len < 1 or value.affectedOutputs.len > 16:
        fail("policy dirty output scope is invalid")
      var r: WfRecord
      r.header.kind = 261
      r.value.dirty.generation = value.policyGeneration
      r.value.dirty.outputCount = uint16(value.affectedOutputs.len)
      for i, output in value.affectedOutputs:
        r.value.dirty.outputs[i] = output
      owner.submit(r)

  proc receipts(): seq[PresentationReceipt] =
    owner.closing:
      # One nonblocking service pass also admits receipts between cycles.
      # Never wait for a future event from a presentation observer.
      if owner.session == nil:
        fail("WM SDK session is closed")
      sdkCheck(wsDispatch(owner.session, 0, 65536, nowMillis()))
      owner.drainReceipts()
      result = move(owner.receipts)
      owner.receipts = @[]

  proc close() =
    owner.close()

  PolicyWire(
    connectionEpoch: owner.epoch,
    capabilities: owner.selected,
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

proc fileWire*(
    socket: Socket,
    requestProfileActivation = false,
    requestPointerFocus = false,
    requestOutputAssignments = false,
): PolicyWire =
  let owner = FileWireOwner(socket: socket, profileWaits: requestProfileActivation)
  owner.closing:
    var config = WsConfig(msize: 8192, bootstrapDeadlineMs: nowMillis() + 12000)
    config.offer.required =
      capabilityBindings or capabilityActions or capabilityMultiOutput or
      capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement or
      capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
      capabilitySessionOperations
    if requestPointerFocus:
      config.offer.required = config.offer.required or capabilityPointerFocus
    if requestProfileActivation:
      config.offer.required = config.offer.required or capabilityProfileActivation
    if requestOutputAssignments:
      config.offer.required =
        config.offer.required or capabilityOutputActions or capabilityOutputPolicyKeys
    config.offer.optional =
      (
        capabilityTabGroups or capabilityTranslationGroups or capabilityOutputActions or
        capabilityOutputPolicyKeys or capabilityLaunchOrigin or
        capabilityOutputLaunchContext or capabilitySurfaceInstances or
        capabilityPresentationActions
      ) and not config.offer.required
    socket.getFd().setBlocking(false)
    owner.session = cast[ptr Ws](alloc0(int(wsStateBytes())))
    let bytes = wsStorageBytes(config.msize)
    owner.storage = alloc0(int(bytes))
    sdkCheck(
      wsOpenFd(
        owner.session,
        cint(socket.getFd()),
        addr config,
        owner.storage,
        bytes,
        nowMillis(),
      )
    )
    while wsState(owner.session) == 0:
      owner.step(config.bootstrapDeadlineMs)
    if wsState(owner.session) != 1:
      fail("WM SDK negotiation failed")
    owner.epoch = wsEpoch(owner.session)
    owner.selected = wsCapabilities(owner.session)
    injectConfiguredFault("negotiated")
    result = owner.wire()
