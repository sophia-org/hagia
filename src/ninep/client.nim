import std/[monotimes, nativesockets, net, os, posix, tables, times]
import ../types/ninep
import ./codec

## One direct Unix stream, bounded tags and deadline-based I/O. It knows
## neither WM admission nor file meanings. Closing it retires all local tags.

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

proc writeFrame(client: NinepClient, data: seq[byte]) =
  let deadline = getMonoTime() + initDuration(milliseconds = client.timeoutMsec)
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
  for _ in 0 ..< ninepMaxPending + 2:
    result = client.nextTag
    client.nextTag =
      if result == ninepNoTag - 1:
        0
      else:
        result + 1
    if not client.pending.hasKey(result):
      return
  fail("9P tag allocator exhausted")

proc sendRequest*(client: NinepClient, request: NinepRequest): uint16 =
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
  result = client.reserveTag(request.kind == NinepRequestKind.flush)
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
  try:
    client.writeFrame(bytes)
  except CatchableError:
    client.close()
    raise

proc receiveReply*(client: NinepClient): NinepReply =
  if client.closed or client.pending.len == 0:
    fail("9P reply without an outstanding request")
  try:
    # One deadline covers header and body, including fragmented arrivals.
    let deadline = getMonoTime() + initDuration(milliseconds = client.timeoutMsec)
    var bytes = client.readBytes(4, deadline)
    let size = bytes.frameLength(client.msize)
    bytes.add(client.readBytes(size - 4, deadline))
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
  except CatchableError:
    client.close()
    raise

proc call*(client: NinepClient, request: NinepRequest): NinepReply =
  if client.pending.len != 0:
    fail("synchronous 9P call cannot consume another request's reply")
  discard client.sendRequest(request)
  result = client.receiveReply()
  if result.kind == NinepReplyKind.lerror:
    var error = newException(NinepRemoteError, "9P operation refused: " & $result.errno)
    error.errno = result.errno
    raise error

proc adoptNinepSocket*(
    socket: Socket, msize = ninepMaxMsize, timeoutMsec = 4_000
): NinepClient =
  ## Takes ownership of this socket even if negotiation fails. Connection and
  ## protected-peer admission belong to the caller, never to a file attach.
  result = NinepClient(socket: socket, msize: msize, timeoutMsec: timeoutMsec)
  try:
    if timeoutMsec <= 0 or timeoutMsec > 60_000:
      fail("invalid 9P I/O timeout")
    socket.getFd().setBlocking(false)
    discard result.call(NinepRequest(kind: NinepRequestKind.version, msize: msize))
  except CatchableError:
    result.close()
    raise
