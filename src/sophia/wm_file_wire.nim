import std/[monotimes, net, options, times]
import
  ../types/[
    handoff, ninep, session, wm_file_arrays, wm_file_bodies, wm_file_wire, wm_files,
    wm_presentation, wm_v1,
  ]
import ../ninep/client
import ./[policy_transport, policy_wire, wm_file_arrays, wm_file_bodies, wm_files]

## The WM file role as a policy wire, over one supplied socket. It keeps fids,
## event and submission counters, one bounded event assembly, at most one held
## event and bounded receipts; PolicySession, the profile reducer and Sophia's
## driver keep every phase. Refusals keep the legacy client's words where the
## meaning is the same. fileWire always configures: it requires configuration
## and policy_dirty, so it serves `runPolicySession(configure = true)` and the
## activated path, never the unconfigured proof loop.
##
## Deadlines are absolute and never renewed: one from constructor entry for
## admission, one per candidate from before its encoding through its
## acknowledged Submitted, one per wait before policy traffic, one per event
## from its first byte to its last, and one per object read from its open.
## Waiting for an event's first byte in
## policy traffic is uncapped, as the legacy read is. Expiry closes the
## connection; the effect of a request already written is unknown, never a
## rollback.

type FileWireOwner = ref object
  client: NinepClient
  state: WmFileWireState

const apiText = "sophia-wm-files version=1 output_transport=current_ipc\n"

proc capAfter(millis: int): Option[MonoTime] =
  some(getMonoTime() + initDuration(milliseconds = millis))

proc earlier(first, second: Option[MonoTime]): Option[MonoTime] =
  if first.isNone:
    second
  elif second.isNone or first.get() < second.get():
    first
  else:
    second

proc remainingMillis(cap: Option[MonoTime], most: int): int =
  ## At least one millisecond, so a capped poll never spins; the client closes
  ## on the cap itself.
  if cap.isNone:
    return most
  clamp(int((cap.get() - getMonoTime()).inMilliseconds), 1, most)

proc transferBytes(owner: FileWireOwner): int =
  int(owner.client.negotiatedMsize()) - wmFileIoOverhead

proc eventKind(record: openArray[byte]): WmFileKind =
  fileKind(record.readU16(6))

proc eventSequence(record: openArray[byte]): uint64 =
  record.readU64(24)

proc waitCap(owner: FileWireOwner): Option[MonoTime] =
  if owner.state.profileWaits:
    capAfter(wmFileProfileWaitMillis)
  else:
    none(MonoTime)

proc assembled(state: WmFileWireState): bool =
  state.assembly.len >= wmFileHeaderBytes and
    state.assembly.len == int(state.assembly.readU32(0))

proc readCap(owner: FileWireOwner, cap: Option[MonoTime]): Option[MonoTime] =
  ## A started event bounds every wait while it is incomplete; a complete one
  ## waits for its consumer unbounded by it.
  if owner.state.assembled():
    cap
  else:
    earlier(cap, owner.state.assemblyExpires)

proc absorbEvent(owner: FileWireOwner, reply: NinepReply) =
  owner.state.eventTag = none(uint16)
  if reply.kind != NinepReplyKind.read:
    fail("Sophia refused the WM event read")
  if reply.data.len == 0 or reply.data.len > int(owner.state.eventRequested):
    fail("WM event read returned an invalid length")
  # Observed when the fragment is taken, not when it was sent.
  if owner.state.assemblyExpires.isSome and
      getMonoTime() >= owner.state.assemblyExpires.get():
    fail("WM event assembly deadline expired")
  if owner.state.assembly.len == 0:
    owner.state.assemblyExpires = capAfter(owner.state.assemblyMillis)
  owner.state.eventOffset += uint64(reply.data.len)
  owner.state.assembly.add(reply.data)
  if owner.state.assembly.len >= wmFileHeaderBytes:
    let total = owner.state.assembly.readU32(0)
    if total < uint32(wmFileHeaderBytes) or total > uint32(wmFileMaxBytes):
      fail("WM event length is out of bounds")
  if owner.state.assembled():
    owner.state.assemblyExpires = none(MonoTime)

proc requestEvent(owner: FileWireOwner, cap: Option[MonoTime]) =
  ## Keeps one events read outstanding while the current record is incomplete,
  ## asking for no byte beyond it: its header first, then its declared rest.
  if owner.state.eventTag.isSome or owner.state.assembled():
    return
  let wanted =
    if owner.state.assembly.len < wmFileHeaderBytes:
      wmFileHeaderBytes - owner.state.assembly.len
    else:
      int(owner.state.assembly.readU32(0)) - owner.state.assembly.len
  owner.state.eventRequested = uint32(min(wanted, owner.transferBytes()))
  owner.state.eventTag = some(
    owner.client.sendRequest(
      NinepRequest(
        kind: NinepRequestKind.read,
        fid: wmFileEventsFid,
        readOffset: owner.state.eventOffset,
        readCount: owner.state.eventRequested,
      ),
      owner.readCap(cap),
    )
  )

proc takeEvent(owner: FileWireOwner): seq[byte] =
  result = move(owner.state.assembly)
  owner.state.assembly = @[]
  owner.state.assemblyExpires = none(MonoTime)
  let header = result.decodeRecord(WmFileClass.eventRecord)
  if header.connectionEpoch != owner.state.connectionEpoch:
    fail("WM event belongs to another epoch")
  if header.sequence != owner.state.lastSequence + 1:
    fail("WM event sequence has a gap or replay")
  owner.state.lastSequence = header.sequence

proc rpc(
    owner: FileWireOwner, request: NinepRequest, cap: Option[MonoTime]
): NinepReply =
  ## One control request beside at most the one events read. A read reply that
  ## lands meanwhile only extends the assembly; it is not reissued here.
  let tag = owner.client.sendRequest(request, owner.readCap(cap))
  while true:
    let reply = owner.client.receiveReply(owner.readCap(cap))
    if owner.state.eventTag == some(reply.tag):
      owner.absorbEvent(reply)
      # A started record keeps moving; a complete one waits for its consumer.
      owner.requestEvent(cap)
      continue
    if reply.tag != tag:
      fail("9P reply for an unknown WM request")
    if reply.kind == NinepReplyKind.lerror:
      var error =
        newException(NinepRemoteError, "9P operation refused: " & $reply.errno)
      error.errno = reply.errno
      raise error
    return reply

proc pollEvent(
    owner: FileWireOwner, waitMsec: int, cap: Option[MonoTime]
): Option[seq[byte]] =
  ## Waits up to `waitMsec` for event progress, taking every fragment that
  ## arrives in that time. Only a complete record is returned.
  let until = getMonoTime() + initDuration(milliseconds = waitMsec)
  while not owner.state.assembled():
    owner.requestEvent(cap)
    let bounded = owner.readCap(cap)
    let left = until - getMonoTime()
    let wait =
      if left <= DurationZero:
        0
      else:
        int((left.inMicroseconds + 999) div 1000)
    # A spent wait still takes what has already arrived.
    let poll =
      if wait == 0:
        0
      else:
        remainingMillis(bounded, wait)
    let reply = owner.client.tryReceiveReply(poll, bounded)
    if reply.isNone:
      # A poll can end early by rounding; the pace is the whole wait.
      if getMonoTime() < until:
        continue
      return none(seq[byte])
    if owner.state.eventTag != some(reply.get().tag):
      fail("unexpected 9P reply while waiting for WM events")
    owner.absorbEvent(reply.get())
  some(owner.takeEvent())

proc ackThrough(owner: FileWireOwner, sequence: uint64, cap: Option[MonoTime]) =
  ## Cumulative and transport-only; a held event keeps its bytes regardless.
  if sequence <= owner.state.ackedThrough:
    return
  let bytes = WmFileAck(
    connectionEpoch: owner.state.connectionEpoch, sequence: sequence
  ).encodeAck()
  let reply = owner.rpc(
    NinepRequest(
      kind: NinepRequestKind.write, fid: wmFileAckFid, writeOffset: 0, data: bytes
    ),
    cap,
  )
  if reply.count != uint32(bytes.len):
    fail("short WM acknowledgement write")
  owner.state.ackedThrough = sequence

proc bufferReceipt(owner: FileWireOwner, record: seq[byte], cap: Option[MonoTime]) =
  if owner.state.receipts.len >= maxPendingPresentationReceipts:
    fail("pending presentation receipts exceed the bound")
  owner.state.receipts.add(
    record.decodePresentationReceipt(owner.state.connectionEpoch, owner.state.selected).receipt
  )
  owner.ackThrough(record.eventSequence(), cap)

proc settleAside(owner: FileWireOwner, record: seq[byte], cap: Option[MonoTime]) =
  ## An event met during candidate custody. Receipts keep draining behind a
  ## held event; the first other event waits for its consumer, and a second
  ## one fails closed rather than replace it.
  case record.eventKind()
  of WmFileKind.presentationReceipt:
    owner.bufferReceipt(record, cap)
  of WmFileKind.submitted:
    fail("Sophia's Submitted names no candidate in custody")
  else:
    if owner.state.held.isSome:
      fail("a second WM event arrived during candidate custody")
    owner.state.held = some(record)

proc nextEvent(owner: FileWireOwner, cap: Option[MonoTime]): seq[byte] =
  ## The next event in journal order that is not a receipt. Receipts on the
  ## way are buffered for the loop's shared application point and
  ## acknowledged; the consumer acknowledges what it takes.
  if owner.state.held.isSome:
    result = owner.state.held.get()
    owner.state.held = none(seq[byte])
    return
  while true:
    let record = owner.pollEvent(wmFileIdlePollMillis, cap)
    if record.isNone:
      continue
    if record.get().eventKind() == WmFileKind.presentationReceipt:
      owner.bufferReceipt(record.get(), cap)
      continue
    return record.get()

proc expectKind(record: openArray[byte], kind: WmFileKind) =
  if record.eventKind() != kind:
    fail("unexpected policy message kind")

proc openFile(
    owner: FileWireOwner,
    fid: uint32,
    name: string,
    flags: uint32,
    cap: Option[MonoTime],
) =
  let walked = owner.rpc(
    NinepRequest(
      kind: NinepRequestKind.walk, fid: wmFileRootFid, newfid: fid, names: @[name]
    ),
    cap,
  )
  if walked.walked.len != 1:
    fail("Sophia's WM file root has no " & name)
  discard
    owner.rpc(NinepRequest(kind: NinepRequestKind.lopen, fid: fid, flags: flags), cap)

proc clunk(owner: FileWireOwner, fid: uint32, cap: Option[MonoTime]) =
  discard owner.rpc(NinepRequest(kind: NinepRequestKind.clunk, fid: fid), cap)

proc objectAttributes(owner: FileWireOwner, cap: Option[MonoTime]): NinepAttributes =
  result = owner.rpc(
    NinepRequest(
      kind: NinepRequestKind.getattr, fid: wmFileSnapshotFid, attributeMask: 0x303
    ),
    cap,
  ).attributes
  if (result.valid and 0x303) != 0x303 or result.size == 0 or
      result.size > uint64(wmFileMaxBytes):
    fail("WM object attributes are incomplete or out of bounds")

proc readObject(
    owner: FileWireOwner, name: string, enclosing: Option[MonoTime]
): seq[byte] =
  ## One whole immutable object, pinned by its open fid for the read, within
  ## one assembly bound from entry that no reply renews.
  let cap = earlier(enclosing, capAfter(owner.state.assemblyMillis))
  owner.openFile(wmFileSnapshotFid, name, 0, cap)
  let before = owner.objectAttributes(cap)
  while uint64(result.len) < before.size:
    let remaining = before.size - uint64(result.len)
    let data = owner.rpc(
      NinepRequest(
        kind: NinepRequestKind.read,
        fid: wmFileSnapshotFid,
        readOffset: uint64(result.len),
        readCount: uint32(min(uint64(owner.transferBytes()), remaining)),
      ),
      cap,
    ).data
    if data.len == 0 or uint64(data.len) > remaining:
      fail("WM object ended before its size")
    result.add(data)
  let after = owner.objectAttributes(cap)
  if after.qid != before.qid or after.size != before.size:
    fail("WM object changed while it was read")
  owner.clunk(wmFileSnapshotFid, cap)

proc submitCandidate(
    owner: FileWireOwner,
    kind: WmFileKind,
    encode: proc(header: WmFileHeader): seq[byte] {.gcsafe.},
    enclosing: Option[MonoTime],
) =
  ## Stages, submits and takes custody of one candidate under one cap, fixed
  ## before encoding. A refused submit transferred nothing: it is retried with
  ## the same ID and bytes after servicing events, at once when a receipt made
  ## journal room and after a paced wait when nothing arrived.
  let cap = earlier(enclosing, capAfter(int(wmFileSendTimeoutMillis)))
  let id = owner.state.nextSubmissionId
  if id == 0 or id == high(uint64):
    fail("WM submission identity space is exhausted")
  let bytes = encode(
    WmFileHeader(
      kind: kind, connectionEpoch: owner.state.connectionEpoch, submissionId: id
    )
  )
  if getMonoTime() >= cap.get():
    fail("WM candidate deadline expired")
  owner.openFile(wmFileTransactionFid, "transaction", 2, cap)
  var offset = 0
  while offset < bytes.len:
    let finish = min(offset + owner.transferBytes(), bytes.len)
    let written = owner.rpc(
      NinepRequest(
        kind: NinepRequestKind.write,
        fid: wmFileTransactionFid,
        writeOffset: uint64(offset),
        data: bytes[offset ..< finish],
      ),
      cap,
    )
    if written.count != uint32(finish - offset):
      fail("short WM candidate write")
    offset = finish
  let submit = WmFileSubmit(
    connectionEpoch: owner.state.connectionEpoch,
    submissionId: id,
    candidateBytes: uint32(bytes.len),
  ).encodeSubmit()
  while true:
    try:
      let written = owner.rpc(
        NinepRequest(
          kind: NinepRequestKind.write,
          fid: wmFileSubmitFid,
          writeOffset: 0,
          data: submit,
        ),
        cap,
      )
      if written.count != uint32(submit.len):
        fail("short WM submit write")
      break
    except NinepRemoteError as error:
      if error.errno != wmFileRetryErrno:
        raise
    let record = owner.pollEvent(wmFileRetryPaceMillis, cap)
    if record.isSome:
      owner.settleAside(record.get(), cap)
  owner.state.nextSubmissionId = id + 1
  while true:
    let record = owner.pollEvent(wmFileIdlePollMillis, cap)
    if record.isNone:
      continue
    if record.get().eventKind() != WmFileKind.submitted:
      owner.settleAside(record.get(), cap)
      continue
    let custody = record.get().decodeSubmitted(owner.state.connectionEpoch)
    if custody.acceptedSubmissionId != id or custody.candidateKind != kind:
      fail("Sophia's Submitted names another candidate")
    owner.ackThrough(record.get().eventSequence(), cap)
    break
  owner.clunk(wmFileTransactionFid, cap)

proc requireLegacyCapabilities(
    available: uint64,
    requestPointerFocus, requestProfileActivation, requestOutputAssignments: bool,
) =
  ## The legacy client's refusals, in its order.
  const base =
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement
  const configured =
    capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
    capabilitySessionOperations
  const outputs = capabilityOutputActions or capabilityOutputPolicyKeys
  if (available and base) != base:
    fail("Sophia omitted a required policy capability")
  if requestPointerFocus and (available and capabilityPointerFocus) == 0:
    fail("Sophia omitted pointer focus, which this profile's focus-follows-mouse needs")
  if (available and configured) != configured:
    fail("Sophia omitted native policy configuration")
  if requestProfileActivation and (available and capabilityProfileActivation) == 0:
    fail("Sophia omitted desktop profile activation")
  if requestOutputAssignments and (available and outputs) != outputs:
    fail("assigned workspaces require output_actions and output_policy_keys")

proc fileOffer(
    requestPointerFocus, requestProfileActivation, requestOutputAssignments: bool
): WmFileNegotiationOffer =
  ## Exactly the vocabulary this client implements: the legacy request, with
  ## what the legacy client refuses to run without made required.
  result.required =
    capabilityBindings or capabilityActions or capabilityMultiOutput or
    capabilityPointerInteractions or capabilityIndicators or capabilityLaunchPlacement or
    capabilityChrome or capabilityPolicyDirty or capabilityConfiguration or
    capabilitySessionOperations
  if requestPointerFocus:
    result.required = result.required or capabilityPointerFocus
  if requestProfileActivation:
    result.required = result.required or capabilityProfileActivation
  if requestOutputAssignments:
    result.required =
      result.required or capabilityOutputActions or capabilityOutputPolicyKeys
  result.optional =
    (
      capabilityTabGroups or capabilityTranslationGroups or capabilityOutputActions or
      capabilityOutputPolicyKeys or capabilityLaunchOrigin or
      capabilityOutputLaunchContext or capabilitySurfaceInstances or
      capabilityPresentationActions
    ) and not result.required

proc profileKind(kind: WmFileKind): Option[ProfileHandoffMsgKind] =
  case kind
  of WmFileKind.profilePrepare:
    some(ProfileHandoffMsgKind.prepare)
  of WmFileKind.profileActivate:
    some(ProfileHandoffMsgKind.activate)
  of WmFileKind.profileRollback:
    some(ProfileHandoffMsgKind.rollback)
  else:
    none(ProfileHandoffMsgKind)

template closing(owner: FileWireOwner, body: untyped): untyped =
  ## Any failure inside a wire operation closes the connection before it
  ## propagates, whoever called the operation.
  try:
    body
  except CatchableError:
    owner.client.close()
    raise

proc wire(owner: FileWireOwner): PolicyWire =
  proc receiveProfileCommand(
      expected: set[ProfileHandoffMsgKind]
  ): Option[ProfileHandoffMsg] =
    owner.closing:
      let cap = owner.waitCap()
      let record = owner.nextEvent(cap)
      let kind = record.eventKind().profileKind()
      if kind.isNone or kind.get() notin expected:
        # Neither decoded nor acknowledged; the loop refuses it in its phase's
        # own words.
        owner.state.held = some(record)
        return none(ProfileHandoffMsg)
      let command = record.decodeProfileCommand(
        kind.get(), owner.state.connectionEpoch, owner.state.selected
      )
      owner.ackThrough(record.eventSequence(), cap)
      result = some(ProfileHandoffMsg(kind: kind.get(), command: command))

  proc completeProfile(kind: ProfileHandoffMsgKind, completion: ProfileCompletion) =
    owner.closing:
      let selected = owner.state.selected
      owner.submitCandidate(
        kind.completionFileKind(),
        proc(header: WmFileHeader): seq[byte] =
          header.encodeProfileCompletion(completion, selected),
        owner.waitCap(),
      )

  proc enterPolicyTraffic() =
    owner.state.profileWaits = false

  proc allocate(): uint64 =
    owner.closing:
      result = owner.state.nextTransaction
      inc owner.state.nextTransaction
      if result == 0 or owner.state.nextTransaction == 0:
        fail("policy transaction identity space is exhausted")

  proc install(configuration: PolicyConfiguration): PolicyConfigurationOutcome =
    owner.closing:
      let selected = owner.state.selected
      owner.submitCandidate(
        WmFileKind.configuration,
        proc(header: WmFileHeader): seq[byte] =
          header.encodeFileConfiguration(configuration, selected),
        owner.waitCap(),
      )
      let cap = owner.waitCap()
      let record = owner.nextEvent(cap)
      record.expectKind(WmFileKind.configurationOutcome)
      let outcome =
        record.decodeConfigurationOutcome(owner.state.connectionEpoch, selected)
      owner.ackThrough(record.eventSequence(), cap)
      result = PolicyConfigurationOutcome(
        transaction: outcome.transaction,
        connectionEpoch: owner.state.connectionEpoch,
        generation: outcome.generation,
        kind: outcome.kind,
      )

  proc snapshot(): PolicySnapshot =
    owner.closing:
      let cap = owner.waitCap()
      let record = owner.nextEvent(cap)
      record.expectKind(WmFileKind.cycle)
      let cycle = record.decodeCycle(owner.state.connectionEpoch, owner.state.selected)
      let published = owner.readObject("snapshot", cap).decodeFileSnapshot(
          owner.state.connectionEpoch, owner.state.selected
        )
      # The Cycle names the exact scene it was prepared against.
      if published.transaction != cycle.snapshotTransaction or
          published.snapshot.generation != cycle.request.sceneGeneration:
        fail("snapshot/Cycle publication mismatch")
      owner.state.pendingRequest = some(cycle.request)
      owner.ackThrough(record.eventSequence(), cap)
      result = published.snapshot

  proc request(): ProjectionRequest =
    owner.closing:
      if owner.state.pendingRequest.isNone:
        fail("policy request without its Cycle")
      result = owner.state.pendingRequest.get()
      owner.state.pendingRequest = none(ProjectionRequest)

  proc project(
      request: ProjectionRequest, transaction: uint64, projection: PolicyProjection
  ): ProjectionCompletion =
    owner.closing:
      let selected = owner.state.selected
      owner.submitCandidate(
        WmFileKind.projection,
        proc(header: WmFileHeader): seq[byte] =
          header.encodeFileProjection(transaction, request, projection, selected),
        owner.waitCap(),
      )
      injectConfiguredFault("projection_submitted")
      let cap = owner.waitCap()
      let record = owner.nextEvent(cap)
      record.expectKind(WmFileKind.projectionOutcome)
      let value = record.decodeProjectionOutcome(owner.state.connectionEpoch, selected)
      if value.outcome.transaction != transaction or
          value.outcome.requestId != request.requestId:
        fail("Sophia returned a mismatched policy outcome")
      owner.ackThrough(record.eventSequence(), cap)
      result = ProjectionCompletion(
        outcome: value.outcome,
        expectSessionOperation: some(value.expectSessionOperation),
      )

  proc operate(intent: SessionOperationIntent): ProjectionOutcomeKind =
    owner.closing:
      let selected = owner.state.selected
      let transaction = allocate()
      owner.submitCandidate(
        WmFileKind.sessionOperation,
        proc(header: WmFileHeader): seq[byte] =
          header.encodeSessionOperation(
            WmFileSessionOperation(transaction: transaction, intent: intent), selected
          ),
        owner.waitCap(),
      )
      injectConfiguredFault("operation_submitted")
      let cap = owner.waitCap()
      let record = owner.nextEvent(cap)
      record.expectKind(WmFileKind.sessionOperationOutcome)
      let value =
        record.decodeSessionOperationOutcome(owner.state.connectionEpoch, selected)
      if value.transaction != transaction or value.requestId != intent.requestId:
        fail("Sophia returned an invalid session-operation outcome")
      owner.ackThrough(record.eventSequence(), cap)
      injectConfiguredFault("operation_outcome_received")
      result = value.kind

  proc dirty(value: PolicyDirty) =
    owner.closing:
      # Dirty carries no domain transaction and consumes none.
      let selected = owner.state.selected
      owner.submitCandidate(
        WmFileKind.dirty,
        proc(header: WmFileHeader): seq[byte] =
          header.encodeDirty(value, selected),
        owner.waitCap(),
      )

  proc receipts(): seq[PresentationReceipt] =
    result = move(owner.state.receipts)
    owner.state.receipts = @[]

  proc close() =
    owner.client.close()

  PolicyWire(
    connectionEpoch: owner.state.connectionEpoch,
    capabilities: owner.state.selected,
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
    assemblyMillis = int(wmFileAssemblyTimeoutMillis),
): PolicyWire =
  ## Admits one supplied socket as the WM file role: discovery, the offer and
  ## its selection, all within one deadline from entry. The socket is owned
  ## from here on, and closed on any refusal. `assemblyMillis` may only
  ## shorten the event and object assembly bound, for tests.
  let entry = getMonoTime()
  let overall = some(entry + initDuration(milliseconds = wmFileAdmissionMillis))
  let discovery =
    earlier(overall, some(entry + initDuration(milliseconds = wmFileDiscoveryMillis)))
  if assemblyMillis <= 0 or assemblyMillis > int(wmFileAssemblyTimeoutMillis):
    socket.close()
    fail("WM file assembly bound is invalid")
  let owner = FileWireOwner(client: socket.adoptNinepSocket(expires = discovery))
  try:
    owner.state.assemblyMillis = assemblyMillis
    let root = owner.rpc(
      NinepRequest(kind: NinepRequestKind.attach, fid: wmFileRootFid), discovery
    ).attached
    if root.kind != 0x80 or root.path == 0:
      fail("Sophia's WM file root is not a directory")
    let api = owner.readObject("api", discovery)
    var text = newString(api.len)
    for index, value in api:
      text[index] = char(value)
    if text != apiText:
      fail("Sophia's WM file API is not version 1 with current output IPC")
    let limitsBytes = owner.readObject("limits", discovery)
    let epoch = limitsBytes.decodeRecord(WmFileClass.objectRecord).connectionEpoch
    let limits = limitsBytes.decodeLimits(epoch)
    owner.state.connectionEpoch = epoch
    owner.openFile(wmFileEventsFid, "events", 0, discovery)
    owner.openFile(wmFileSubmitFid, "submit", 1, discovery)
    owner.openFile(wmFileAckFid, "ack", 1, discovery)
    if limits.profileRequired and not requestProfileActivation:
      fail("Sophia requires desktop profile activation")
    limits.capabilityCeiling.requireLegacyCapabilities(
      requestPointerFocus, requestProfileActivation, requestOutputAssignments
    )
    let offer =
      fileOffer(requestPointerFocus, requestProfileActivation, requestOutputAssignments)
    owner.state.nextSubmissionId = 1
    owner.state.nextTransaction = 1
    owner.submitCandidate(
      WmFileKind.negotiate,
      proc(header: WmFileHeader): seq[byte] =
        header.encodeNegotiate(offer),
      overall,
    )
    let record = owner.nextEvent(overall)
    record.expectKind(WmFileKind.negotiated)
    let selected = record.decodeNegotiated(epoch)
    if (selected and offer.required) != offer.required or
        (selected and not (offer.required or offer.optional)) != 0 or
        (selected and not limits.capabilityCeiling) != 0:
      fail("Sophia selected capabilities outside Hagia's offer or its ceiling")
    owner.ackThrough(record.eventSequence(), overall)
    owner.state.selected = selected
    owner.state.profileWaits = requestProfileActivation
    injectConfiguredFault("negotiated")
  except CatchableError:
    owner.client.close()
    raise
  owner.wire()
