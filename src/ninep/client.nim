import std/[monotimes, nativesockets, net, options, os, posix, tables, times]
import ../types/ninep
import ./codec

## One direct Unix stream, bounded tags and deadline-based I/O. It knows
## neither WM admission nor file meanings. Closing it retires all local tags.
## The role adapter owns fids: only a full Rwalk (including a zero-name clone)
## establishes newfid. A partial Rwalk returns the prefix without creating it.
## A caller expiry is an observation-time cutoff: even complete buffered data
## is refused after it. A sent operation may therefore have an unknown effect.
## Error strings do not identify which deadline won; callers retain their cap.

type
  NinepClientError* = object of CatchableError
  NinepRemoteError* = object of NinepClientError
    errno*: uint32

  NinepClient* = ref object
    socket: Socket
    msize: uint32
    timeoutMsec: int
    nextTag: uint16
    versioned: bool
    closed: bool
    pending: Table[uint16, NinepPending]

proc fail(message: string) {.noreturn.} =
  raise newException(NinepClientError, message)

proc close*(client: NinepClient) =
  if not client.closed:
    client.closed = true
    client.socket.close()
    client.pending.clear()
    client.versioned = false

proc negotiatedMsize*(client: NinepClient): uint32 =
  if client.closed or not client.versioned:
    fail("9P connection is not negotiated")
  client.msize

proc pendingCount*(client: NinepClient): int =
  client.pending.len

proc tagReserved(client: NinepClient, tag: uint16): bool =
  if client.pending.hasKey(tag):
    return true
  for request in client.pending.values:
    if request.kind == NinepRequestKind.flush and request.oldtag == tag:
      return true

proc waitSocket(client: NinepClient, events: cshort, deadline: MonoTime) =
  while true:
    let remaining = (deadline - getMonoTime()).inMilliseconds
    if remaining <= 0:
      fail("9P I/O deadline expired")
    var descriptor = TPollfd(fd: cint(client.socket.getFd()), events: events)
    let ready = posix.poll(addr descriptor, Tnfds(1), cint(remaining))
    if ready > 0:
      # recv/send reports EOF or the specific failure after HUP/ERR as well.
      return
    if ready == 0:
      fail("9P I/O deadline expired")
    if osLastError() != OSErrorCode(EINTR):
      raiseOSError(osLastError())

proc boundedDeadline(deadline: MonoTime, expires: Option[MonoTime]): MonoTime =
  if expires.isSome and expires.get() < deadline:
    expires.get()
  else:
    deadline

proc requireUnexpired(expires: Option[MonoTime]) =
  if expires.isSome and getMonoTime() >= expires.get():
    fail("9P caller deadline expired")

proc writeFrame(client: NinepClient, data: seq[byte], expires: Option[MonoTime]) =
  let deadline = boundedDeadline(
    getMonoTime() + initDuration(milliseconds = client.timeoutMsec), expires
  )
  var offset = 0
  while offset < data.len:
    client.waitSocket(POLLOUT, deadline)
    let sent = posix.send(
      client.socket.getFd(), unsafeAddr data[offset], data.len - offset, MSG_NOSIGNAL
    )
    if sent > 0:
      offset += sent
    elif sent == 0:
      fail("9P socket closed during write")
    else:
      let error = osLastError()
      if error != OSErrorCode(EINTR) and error != OSErrorCode(EAGAIN) and
          error != OSErrorCode(EWOULDBLOCK):
        raiseOSError(error)

proc readBytes(client: NinepClient, count: int, deadline: MonoTime): seq[byte] =
  result = newSeq[byte](count)
  var offset = 0
  while offset < count:
    client.waitSocket(POLLIN, deadline)
    let received =
      posix.recv(client.socket.getFd(), addr result[offset], count - offset, 0)
    if received > 0:
      offset += received
    elif received == 0:
      fail("9P socket closed during read")
    else:
      let error = osLastError()
      if error != OSErrorCode(EINTR) and error != OSErrorCode(EAGAIN) and
          error != OSErrorCode(EWOULDBLOCK):
        raiseOSError(error)

proc reserveTag(client: NinepClient, control: bool): uint16 =
  # A full ordinary-request window must still admit one cancellation.
  let capacity = ninepMaxPending + (if control: 1 else: 0)
  if client.pending.len >= capacity:
    fail("9P outstanding request bound reached")
  # Each live flush can reserve its original tag as well as its own tag.
  for _ in 0 ..< 2 * (ninepMaxPending + 1) + 1:
    result = client.nextTag
    client.nextTag =
      if result == ninepNoTag - 1:
        0
      else:
        result + 1
    if not client.tagReserved(result):
      return
  fail("9P tag allocator exhausted")

proc sendRequest*(
    client: NinepClient, request: NinepRequest, expires = none(MonoTime)
): uint16 =
  ## An optional caller deadline caps this operation without replacing the
  ## frame timeout. Reuse the same deadline across a multi-request transfer.
  ## Expiry closes the connection and all tags; it cannot undo an earlier
  ## request's effect, including a write whose acknowledgement was lost.
  if client.closed:
    fail("9P connection is closed")
  if not client.versioned and request.kind != NinepRequestKind.version:
    fail("9P request before version negotiation")
  if request.kind == NinepRequestKind.version and client.pending.len != 0:
    fail("9P version with outstanding requests")
  if request.kind == NinepRequestKind.flush and not client.pending.hasKey(
    request.oldtag
  ):
    fail("9P flush does not name an outstanding request")
  if request.kind == NinepRequestKind.flush and
      client.pending[request.oldtag].kind == NinepRequestKind.flush:
    fail("this 9P client does not flush a flush")
  result =
    if request.kind == NinepRequestKind.version:
      ninepNoTag
    else:
      client.reserveTag(request.kind == NinepRequestKind.flush)
  let bytes = request.encodeRequest(result, client.msize)
  var pending = NinepPending(kind: request.kind)
  case request.kind
  of NinepRequestKind.version:
    pending.bound = request.msize
  of NinepRequestKind.walk:
    pending.bound = uint32(request.names.len)
  of NinepRequestKind.read:
    pending.bound = request.readCount
  of NinepRequestKind.write:
    pending.bound = uint32(request.data.len)
  of NinepRequestKind.flush:
    pending.oldtag = request.oldtag
  else:
    discard
  client.pending[result] = pending
  if request.kind == NinepRequestKind.version:
    # Version tears down the server session even when negotiation refuses.
    client.versioned = false
  try:
    requireUnexpired(expires)
    client.writeFrame(bytes, expires)
    requireUnexpired(expires)
  except CatchableError:
    client.close()
    raise

proc firstByte(
    client: NinepClient, waitMsec: int, expires: Option[MonoTime]
): Option[byte] =
  requireUnexpired(expires)
  let deadline =
    boundedDeadline(getMonoTime() + initDuration(milliseconds = waitMsec), expires)
  while true:
    let remaining = max(0'i64, (deadline - getMonoTime()).inMilliseconds)
    var descriptor = TPollfd(fd: cint(client.socket.getFd()), events: POLLIN)
    let ready = posix.poll(addr descriptor, Tnfds(1), cint(remaining))
    if ready == 0:
      requireUnexpired(expires)
      return none(byte)
    if ready > 0:
      var value: byte
      let received = posix.recv(client.socket.getFd(), addr value, 1, 0)
      if received == 1:
        requireUnexpired(expires)
        return some(value)
      if received == 0:
        fail("9P socket closed before reply")
      let error = osLastError()
      if error != OSErrorCode(EINTR) and error != OSErrorCode(EAGAIN) and
          error != OSErrorCode(EWOULDBLOCK):
        raiseOSError(error)
    elif osLastError() != OSErrorCode(EINTR):
      raiseOSError(osLastError())
    if getMonoTime() >= deadline:
      requireUnexpired(expires)
      return none(byte)

proc finishReply(
    client: NinepClient, first: byte, expires: Option[MonoTime]
): NinepReply =
  # First-byte receipt starts one assembly deadline for the remaining header
  # and body. Partial frames never return to the caller as idle.
  let deadline = boundedDeadline(
    getMonoTime() + initDuration(milliseconds = client.timeoutMsec), expires
  )
  var bytes = @[first]
  bytes.add(client.readBytes(3, deadline))
  let size = bytes.frameLength(client.msize)
  bytes.add(client.readBytes(size - 4, deadline))
  requireUnexpired(expires)
  result = bytes.decodeReply(client.msize)
  if not client.pending.hasKey(result.tag):
    fail("9P reply names an unknown tag")
  let pending = client.pending[result.tag]
  if not result.matchesRequest(pending):
    fail("9P reply does not match its request")
  client.pending.del(result.tag)
  case result.kind
  of NinepReplyKind.version:
    client.msize = result.msize
    client.versioned = true
  of NinepReplyKind.flush:
    # Any original reply precedes Rflush. An absent reply is now cancelled;
    # a later response with that old tag is a connection protocol error.
    client.pending.del(pending.oldtag)
  else:
    discard

proc receiveReply*(client: NinepClient, expires = none(MonoTime)): NinepReply =
  ## First-byte wait and assembly each have timeoutMsec: this call can take
  ## up to twice that bound. Event loops use tryReceiveReply for idle waiting.
  ## When supplied, one caller deadline caps both waits and is never renewed.
  if client.closed or client.pending.len == 0:
    fail("9P reply without an outstanding request")
  try:
    let first = client.firstByte(client.timeoutMsec, expires)
    if first.isNone():
      fail("9P first-byte deadline expired")
    result = client.finishReply(first.get(), expires)
  except CatchableError:
    client.close()
    raise

proc call*(
    client: NinepClient, request: NinepRequest, expires = none(MonoTime)
): NinepReply =
  if client.pending.len != 0:
    fail("synchronous 9P call cannot consume another request's reply")
  discard client.sendRequest(request, expires)
  result = client.receiveReply(expires)
  if result.kind == NinepReplyKind.lerror:
    var error = newException(NinepRemoteError, "9P operation refused: " & $result.errno)
    error.errno = result.errno
    raise error

proc tryReceiveReply*(
    client: NinepClient, waitMsec = 0, expires = none(MonoTime)
): Option[NinepReply] =
  ## None consumes no bytes and leaves every request live. EOF closes even
  ## before the first byte; any received prefix must finish or fail closed.
  ## This is not an idle disconnect probe: it requires an outstanding request
  ## such as the WM event read.
  ## Idle polls retain custody before expires; reaching it closes the stream,
  ## including when only part of a reply has arrived.
  ## Millisecond polling can return None just before expiry; it checks that the
  ## cap has not elapsed after polling, and the next call keeps the same cap.
  if client.closed or client.pending.len == 0:
    fail("9P readiness without an outstanding request")
  if waitMsec < 0 or waitMsec > 60_000:
    fail("invalid 9P readiness timeout")
  try:
    let first = client.firstByte(waitMsec, expires)
    if first.isNone():
      return none(NinepReply)
    return some(client.finishReply(first.get(), expires))
  except CatchableError:
    client.close()
    raise

proc adoptNinepSocket*(
    socket: Socket, msize = ninepMaxMsize, timeoutMsec = 4_000, expires = none(MonoTime)
): NinepClient =
  ## Takes ownership of this socket even if negotiation fails. Connection and
  ## protected-peer admission belong to the caller, never to a file attach.
  result =
    NinepClient(socket: socket, msize: msize, timeoutMsec: timeoutMsec, nextTag: 1)
  try:
    if timeoutMsec <= 0 or timeoutMsec > 60_000:
      fail("invalid 9P I/O timeout")
    socket.getFd().setBlocking(false)
    discard
      result.call(NinepRequest(kind: NinepRequestKind.version, msize: msize), expires)
  except CatchableError:
    result.close()
    raise
