import std/[net, posix, strutils, unittest]

import config/profile
import types/config_values
import sophia/policy_client
import sophia/[profile_handoff, wm_v1]
import types/handoff
import types/wm_v1

type ClientThreadArgs = object
  fd: SocketHandle
  candidate: AuthorityCandidate
  disposition: ptr StartupProfileHandoffDisposition

proc runClient(args: ClientThreadArgs) {.thread.} =
  let socket =
    newSocket(args.fd, Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP, false)
  try:
    args.disposition[] = socket.runStartupProfileHandoff(args.candidate)
  except CatchableError:
    args.disposition[] = StartupProfileHandoffDisposition.rejected
  finally:
    socket.close()

proc receiveTestFrame(socket: Socket): Frame =
  proc exact(length: int): string =
    while result.len < length:
      let part = socket.recv(length - result.len, 1_000)
      if part.len == 0:
        raise newException(IOError, "test frame is truncated")
      result.add(part)

  var bytes: seq[byte]
  let header = exact(frameHeaderLen)
  for value in header:
    bytes.add(byte(value))
  let payloadLen = int(bytes.u32At(16))
  let payload = exact(payloadLen)
  for value in payload:
    bytes.add(byte(value))
  bytes.decodeFrame()

proc sendTestFrame(socket: Socket, frame: Frame) =
  let bytes = frame.encodeFrame()
  var data = newString(bytes.len)
  for index, value in bytes:
    data[index] = char(value)
  socket.send(data)

proc welcome(epoch: uint64, configuration = false): Frame =
  result.kind = MessageKind.serverWelcome
  result.payload.addU16(3)
  result.payload.addU16(0)
  # bindings, actions, multi_output, pointer_interactions, indicators,
  # profile_activation, launch_placement.
  var capabilities =
    (1'u64 shl 0) or (1'u64 shl 1) or (1'u64 shl 2) or (1'u64 shl 3) or (1'u64 shl 8) or
    (1'u64 shl 9) or (1'u64 shl 10)
  if configuration:
    capabilities =
      capabilities or (1'u64 shl 4) or (1'u64 shl 5) or (1'u64 shl 6) or (1'u64 shl 7)
  result.payload.addU64(capabilities)
  result.payload.addU64(epoch)
  result.payload.addU16(uint16(maxOutputs))
  result.payload.addU16(uint16(maxBindings))
  result.payload.addU32(uint32(maxSurfaces))
  result.payload.addU32(uint32(maxPayloadLen))

proc candidate(generation: uint64, digestByte: string): AuthorityCandidate =
  AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: generation,
    digest: repeat(digestByte, profileDigestLen),
  )

proc identity(epoch, generation: uint64, digest: byte): ProfileIdentity =
  result.connectionEpoch = epoch
  result.profileGeneration = generation
  for index in 0 ..< profileDigestLen:
    result.profileDigest[index] = digest

proc command(transaction: uint64, identity: ProfileIdentity): ProfileCommand =
  ProfileCommand(transaction: transaction, identity: identity)

proc reduce(
    model: ProfileHandoffModel,
    kind: ProfileHandoffMsgKind,
    transaction: uint64,
    identity: ProfileIdentity,
): ProfileHandoffUpdate =
  model.reduceProfileHandoff(
    ProfileHandoffMsg(kind: kind, command: command(transaction, identity))
  )

suite "Hagia profile authority handoff":
  test "exact prepare and activate promote only the loaded candidate":
    let identity = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff(9)
    check loaded.phase == ProfileHandoffPhase.loaded

    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, identity)
    check prepared.model.phase == ProfileHandoffPhase.prepared
    check prepared.completion.outcome == ProfileOutcomeKind.accepted
    check prepared.model.preparedIdentity == identity

    let active = prepared.model.reduce(ProfileHandoffMsgKind.activate, 2, identity)
    check active.model.phase == ProfileHandoffPhase.active
    check active.completion.outcome == ProfileOutcomeKind.accepted
    check active.model.activeIdentity == identity

  test "file and wire identity mismatch is rejected without mutation":
    let loaded = candidate(7, "5a").initProfileHandoff(9)
    for wrong in [identity(8, 7, 0x5a), identity(9, 8, 0x5a), identity(9, 7, 0xa5)]:
      let update = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, wrong)
      check update.model == loaded
      check update.completion.outcome == ProfileOutcomeKind.rejectedIdentity

  test "phase and epoch mismatches fail closed":
    let exact = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff(9)
    let premature = loaded.reduce(ProfileHandoffMsgKind.activate, 1, exact)
    check premature.model == loaded
    check premature.completion.outcome == ProfileOutcomeKind.rejectedState

    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 2, exact).model
    let wrongEpoch =
      prepared.reduce(ProfileHandoffMsgKind.activate, 3, identity(10, 7, 0x5a))
    check wrongEpoch.model == prepared
    check wrongEpoch.completion.outcome == ProfileOutcomeKind.rejectedIdentity

  test "exact retries are idempotent and preserve the latest transaction":
    let exact = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff(9)
    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, exact).model
    let retried = prepared.reduce(ProfileHandoffMsgKind.prepare, 2, exact)
    check retried.model == prepared
    check retried.completion.transaction == 2
    check retried.completion.outcome == ProfileOutcomeKind.accepted

  test "rollback discards prepared or active candidate state":
    let exact = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff(9)
    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, exact).model
    let rolledBack = prepared.reduce(ProfileHandoffMsgKind.rollback, 2, exact)
    check rolledBack.model.phase == ProfileHandoffPhase.rolledBack
    check rolledBack.model.preparedIdentity == ProfileIdentity()
    check rolledBack.completion.outcome == ProfileOutcomeKind.accepted

    let retry = rolledBack.model.reduce(ProfileHandoffMsgKind.rollback, 3, exact)
    check retry.model == rolledBack.model
    check retry.completion.outcome == ProfileOutcomeKind.accepted

  test "invalid local candidate and command identities are terminal errors":
    expect ProfileHandoffError:
      discard AuthorityCandidate(
        authority: ProfileAuthority.session,
        generation: 1,
        digest: repeat("11", profileDigestLen),
      ).initProfileHandoff(9)
    expect ProfileHandoffError:
      discard candidate(1, "11").initProfileHandoff(0)
    let loaded = candidate(7, "5a").initProfileHandoff(9)
    expect ProfileHandoffError:
      discard loaded.reduce(ProfileHandoffMsgKind.prepare, 0, identity(9, 7, 0x5a))

  test "private socket handshake activates only after exact acknowledgements":
    var descriptors: array[0 .. 1, cint]
    require posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, descriptors) == 0
    let server = newSocket(
      SocketHandle(descriptors[0]),
      Domain.AF_UNIX,
      SockType.SOCK_STREAM,
      Protocol.IPPROTO_IP,
      false,
    )
    defer:
      server.close()
    var disposition = StartupProfileHandoffDisposition.rejected
    var thread: Thread[ClientThreadArgs]
    createThread(
      thread,
      runClient,
      ClientThreadArgs(
        fd: SocketHandle(descriptors[1]),
        candidate: candidate(7, "5a"),
        disposition: addr disposition,
      ),
    )

    let hello = server.receiveTestFrame()
    check hello.kind == MessageKind.clientHello
    check (hello.payload.u64At(4) and (1'u64 shl 9)) != 0
    server.sendTestFrame(welcome(9))
    let exact = identity(9, 7, 0x5a)
    server.sendTestFrame(MessageKind.profilePrepare.profileCommandFrame(1, exact))
    let prepared = server.receiveTestFrame().decodeProfileCompletion()
    check prepared.transaction == 1
    check prepared.identity == exact
    check prepared.outcome == ProfileOutcomeKind.accepted

    server.sendTestFrame(MessageKind.profileActivate.profileCommandFrame(2, exact))
    let active = server.receiveTestFrame().decodeProfileCompletion()
    check active.transaction == 2
    check active.identity == exact
    check active.outcome == ProfileOutcomeKind.accepted
    joinThread(thread)
    check disposition == StartupProfileHandoffDisposition.activated

  test "stale connection epoch cannot cross the activation barrier":
    var descriptors: array[0 .. 1, cint]
    require posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, descriptors) == 0
    let server = newSocket(
      SocketHandle(descriptors[0]),
      Domain.AF_UNIX,
      SockType.SOCK_STREAM,
      Protocol.IPPROTO_IP,
      false,
    )
    defer:
      server.close()
    var disposition = StartupProfileHandoffDisposition.activated
    var thread: Thread[ClientThreadArgs]
    createThread(
      thread,
      runClient,
      ClientThreadArgs(
        fd: SocketHandle(descriptors[1]),
        candidate: candidate(7, "5a"),
        disposition: addr disposition,
      ),
    )

    discard server.receiveTestFrame()
    server.sendTestFrame(welcome(9))
    server.sendTestFrame(
      MessageKind.profilePrepare.profileCommandFrame(1, identity(8, 7, 0x5a))
    )
    let rejected = server.receiveTestFrame().decodeProfileCompletion()
    check rejected.outcome == ProfileOutcomeKind.rejectedIdentity
    discard posix.shutdown(SocketHandle(descriptors[0]), posix.SHUT_WR)
    joinThread(thread)
    check disposition == StartupProfileHandoffDisposition.rejected

  test "normal configuration follows Active on the same connection":
    var descriptors: array[0 .. 1, cint]
    require posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, descriptors) == 0
    let client = newSocket(
      SocketHandle(descriptors[0]),
      Domain.AF_UNIX,
      SockType.SOCK_STREAM,
      Protocol.IPPROTO_IP,
      false,
    )
    let server = newSocket(
      SocketHandle(descriptors[1]),
      Domain.AF_UNIX,
      SockType.SOCK_STREAM,
      Protocol.IPPROTO_IP,
      false,
    )
    defer:
      server.close()
    server.sendTestFrame(welcome(9, true))
    let exact = identity(9, 7, 0x5a)
    server.sendTestFrame(MessageKind.profilePrepare.profileCommandFrame(1, exact))
    server.sendTestFrame(MessageKind.profileActivate.profileCommandFrame(2, exact))
    discard posix.shutdown(SocketHandle(descriptors[1]), posix.SHUT_WR)
    expect PolicyClientError:
      client.runProfileActivatedPolicySessionOnSocket(candidate(7, "5a"))

    let hello = server.receiveTestFrame()
    check hello.kind == MessageKind.clientHello
    check server.receiveTestFrame().decodeProfileCompletion().outcome ==
      ProfileOutcomeKind.accepted
    check server.receiveTestFrame().decodeProfileCompletion().outcome ==
      ProfileOutcomeKind.accepted
    let configuration = server.receiveTestFrame()
    check configuration.kind == MessageKind.policyConfiguration
    check configuration.transaction == 1
    check configuration.payload.u64At(0) == 9

  test "invalid policy values cannot acknowledge Prepare or Active":
    var descriptors: array[0 .. 1, cint]
    require posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, descriptors) == 0
    let client = newSocket(
      SocketHandle(descriptors[0]),
      Domain.AF_UNIX,
      SockType.SOCK_STREAM,
      Protocol.IPPROTO_IP,
      false,
    )
    let server = newSocket(
      SocketHandle(descriptors[1]),
      Domain.AF_UNIX,
      SockType.SOCK_STREAM,
      Protocol.IPPROTO_IP,
      false,
    )
    defer:
      server.close()
    server.sendTestFrame(welcome(9, true))
    let exact = identity(9, 7, 0x5a)
    server.sendTestFrame(MessageKind.profilePrepare.profileCommandFrame(1, exact))
    server.sendTestFrame(MessageKind.profileActivate.profileCommandFrame(2, exact))
    discard posix.shutdown(SocketHandle(descriptors[1]), posix.SHUT_WR)
    var invalid = candidate(7, "5a")
    # This value passes the KDL loader; policy-model construction rejects it.
    invalid.values.add(ProfileValue(key: "policy.outer-gap", encoded: "outer-gap 513"))
    expect DesktopProfileError:
      client.runProfileActivatedPolicySessionOnSocket(invalid)
    check server.receiveTestFrame().kind == MessageKind.clientHello
    # The only outgoing frame was negotiation, never a profile acknowledgement.
    # Closing with unread commands may report reset rather than orderly EOF.
    try:
      check server.recv(1, 1000).len == 0
    except OSError:
      discard
