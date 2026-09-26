import std/[monotimes, net, options, posix, strutils, times, unittest]
import types/ninep
import ninep/[client, codec]

## Bytes below are written from the .L field tables, not a Sophia encoder.
## These are client boundary controls; real-server conformance is separate.

proc bytes(text: string): seq[byte] =
  for value in text:
    result.add(byte(value))

proc hex(text: string): seq[byte] =
  for value in text.splitWhitespace():
    result.add(byte(parseHexInt(value)))

proc sendBytes(socket: Socket, data: openArray[byte]) =
  var text = newString(data.len)
  for index, value in data:
    text[index] = char(value)
  socket.send(text)

proc sockets(): tuple[server, peer: Socket] =
  var descriptors: array[2, cint]
  doAssert posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, descriptors) == 0
  result.server = newSocket(
    SocketHandle(descriptors[0]),
    Domain.AF_UNIX,
    SockType.SOCK_STREAM,
    Protocol.IPPROTO_IP,
    false,
  )
  result.peer = newSocket(
    SocketHandle(descriptors[1]),
    Domain.AF_UNIX,
    SockType.SOCK_STREAM,
    Protocol.IPPROTO_IP,
    false,
  )

proc readyClient(server, peer: Socket, timeoutMsec = 500): NinepClient =
  server.sendBytes(
    hex("15 00 00 00 65 ff ff 00 10 00 00 08 00 39 50 32 30 30 30 2e 4c")
  )
  result = peer.adoptNinepSocket(timeoutMsec = timeoutMsec)
  check server.recv(21, 500).bytes() ==
    hex("15 00 00 00 64 ff ff 00 00 01 00 08 00 39 50 32 30 30 30 2e 4c")
  check result.negotiatedMsize() == 4096

suite "caller deadlines across 9P operations":
  test "expired caller budget emits no request and closes all custody":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    expect NinepClientError:
      discard client.call(
        NinepRequest(kind: NinepRequestKind.clunk, fid: 1), some(getMonoTime())
      )
    check client.pendingCount() == 0
    check server.recv(1, 500).len == 0

  test "caller budget caps synchronous first-byte wait":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 3000)
    let start = getMonoTime()
    expect NinepClientError:
      discard client.call(
        NinepRequest(kind: NinepRequestKind.clunk, fid: 1),
        some(start + initDuration(milliseconds = 75)),
      )
    check (getMonoTime() - start).inMilliseconds < 1500
    check client.pendingCount() == 0

  test "caller budget caps assembly after a prefix was consumed":
    for prefix in ["0c 00 00", "0c 00 00 00 75 01 00 01 00 00 00"]:
      let (server, peer) = sockets()
      defer:
        server.close()
      let client = readyClient(server, peer, timeoutMsec = 3000)
      discard client.sendRequest(
        NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
      )
      server.sendBytes(prefix.hex())
      let start = getMonoTime()
      expect NinepClientError:
        discard client.tryReceiveReply(
          expires = some(start + initDuration(milliseconds = 75))
        )
      check (getMonoTime() - start).inMilliseconds < 1500
      check client.pendingCount() == 0
      expect NinepClientError:
        discard client.negotiatedMsize()

  test "an idle pending read closes when repeated polling reaches the same cap":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 3000)
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    let start = getMonoTime()
    let expires = some(start + initDuration(milliseconds = 75))
    expect NinepClientError:
      while true:
        check client.tryReceiveReply(waitMsec = 500, expires = expires).isNone()
    check (getMonoTime() - start).inMilliseconds < 1500
    check client.pendingCount() == 0

  test "version adoption cannot renew the caller budget":
    let (server, peer) = sockets()
    defer:
      server.close()
    let start = getMonoTime()
    expect NinepClientError:
      discard peer.adoptNinepSocket(
        timeoutMsec = 3000, expires = some(start + initDuration(milliseconds = 75))
      )
    check (getMonoTime() - start).inMilliseconds < 1500
    check server.recv(21, 500).len == 21
    check server.recv(1, 500).len == 0

  test "expiry wins over a complete reply already buffered on the socket":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    server.sendBytes(hex("0c 00 00 00 75 01 00 01 00 00 00 41"))
    expect NinepClientError:
      discard client.tryReceiveReply(expires = some(getMonoTime()))
    check client.pendingCount() == 0
    expect NinepClientError:
      discard client.negotiatedMsize()

  test "a later caller budget never extends the per-frame timeout":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 50)
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    server.sendBytes(hex("0c 00 00"))
    let start = getMonoTime()
    expect NinepClientError:
      discard client.receiveReply(some(start + initDuration(seconds = 3)))
    check (getMonoTime() - start).inMilliseconds < 1500
    check client.pendingCount() == 0

  test "one caller deadline survives a successful earlier RPC":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 3000)
    let expires = some(getMonoTime() + initDuration(milliseconds = 100))
    server.sendBytes(hex("07 00 00 00 79 01 00"))
    check client.call(NinepRequest(kind: NinepRequestKind.clunk, fid: 1), expires).kind ==
      NinepReplyKind.clunk
    check server.recv(11, 500).len == 11
    # Spend the same operation budget outside socket I/O; the next call may
    # not restart it merely because the prior reply completed successfully.
    while getMonoTime() < expires.get():
      discard posix.usleep(1000)
    expect NinepClientError:
      discard client.call(NinepRequest(kind: NinepRequestKind.clunk, fid: 2), expires)
    check server.recv(1, 500).len == 0
    check client.pendingCount() == 0

  test "caller budget caps blocked writes on an unread socket":
    let (server, peer) = sockets()
    defer:
      server.close()
    var sendBuffer: cint = 1024
    require posix.setsockopt(
      peer.getFd(), SOL_SOCKET, SO_SNDBUF, addr sendBuffer, SockLen(sizeof(sendBuffer))
    ) == 0
    let client = readyClient(server, peer, timeoutMsec = 3000)
    let start = getMonoTime()
    let expires = some(start + initDuration(milliseconds = 75))
    var refused = false
    for _ in 0 ..< ninepMaxPending:
      try:
        discard client.sendRequest(
          NinepRequest(kind: NinepRequestKind.write, fid: 2, data: newSeq[byte](4073)),
          expires,
        )
      except NinepClientError:
        refused = true
        break
    check refused
    check (getMonoTime() - start).inMilliseconds < 1500
    check client.pendingCount() == 0
    var received = 0
    while true:
      let chunk = server.recv(4096, 500)
      if chunk.len == 0:
        break
      received += chunk.len
      require received <= ninepMaxPending * 4096
    check received > 0

  test "polling before caller expiry retains one live read":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let expires = some(getMonoTime() + initDuration(seconds = 2))
    let tag = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1), expires
    )
    check client.tryReceiveReply(expires = expires).isNone()
    check client.pendingCount() == 1
    server.sendBytes(hex("0c 00 00 00 75 01 00 01 00 00 00 41"))
    let reply = client.tryReceiveReply(expires = expires)
    require reply.isSome()
    check reply.get().tag == tag and reply.get().data == @[0x41'u8]
    check client.pendingCount() == 0

suite "independent base 9P2000.L codec":
  test "version and attach match independently specified byte layouts":
    check NinepRequest(kind: NinepRequestKind.version, msize: 4096).encodeRequest(
      ninepNoTag, ninepMaxMsize
    ) == hex("15 00 00 00 64 ff ff 00 10 00 00 08 00 39 50 32 30 30 30 2e 4c")
    check NinepRequest(kind: NinepRequestKind.attach, fid: 1).encodeRequest(
      2, ninepMaxMsize
    ) == hex("17 00 00 00 68 02 00 01 00 00 00 ff ff ff ff 00 00 00 00 ff ff ff ff")

  test "walk, open, read, write, clunk, flush and getattr field offsets":
    check NinepRequest(kind: NinepRequestKind.walk, fid: 1, newfid: 2, names: @["x"]).encodeRequest(
      3, 4096
    ) == hex("14 00 00 00 6e 03 00 01 00 00 00 02 00 00 00 01 00 01 00 78")
    check NinepRequest(kind: NinepRequestKind.lopen, fid: 2, flags: 2).encodeRequest(
      4, 4096
    ) == hex("0f 00 00 00 0c 04 00 02 00 00 00 02 00 00 00")
    check NinepRequest(kind: NinepRequestKind.read, fid: 2, readOffset: 3, readCount: 4).encodeRequest(
      5, 4096
    ) == hex("17 00 00 00 74 05 00 02 00 00 00 03 00 00 00 00 00 00 00 04 00 00 00")
    check NinepRequest(
      kind: NinepRequestKind.write, fid: 2, writeOffset: 3, data: @[4'u8]
    ).encodeRequest(6, 4096) ==
      hex("18 00 00 00 76 06 00 02 00 00 00 03 00 00 00 00 00 00 00 01 00 00 00 04")
    check NinepRequest(kind: NinepRequestKind.clunk, fid: 2).encodeRequest(7, 4096) ==
      hex("0b 00 00 00 78 07 00 02 00 00 00")
    check NinepRequest(kind: NinepRequestKind.flush, oldtag: 7).encodeRequest(8, 4096) ==
      hex("09 00 00 00 6c 08 00 07 00")
    check NinepRequest(kind: NinepRequestKind.getattr, fid: 2, attributeMask: 0xff).encodeRequest(
      9, 4096
    ) == hex("13 00 00 00 18 09 00 02 00 00 00 ff 00 00 00 00 00 00 00")

  test "truncated and excessive frames refuse before any count allocation":
    for malformed in ["06 00 00 00", "01 10 00 00", "ff ff ff ff", "07 00"]:
      expect NinepCodecError:
        discard malformed.hex().frameLength(4096)
    for malformed in [
      "07 00 00 00 75 01 00", # missing read count
      "0b 00 00 00 75 01 00 ff ff ff ff", # impossible count
      "0b 00 00 00 07 01 00 00 00 00 00", # error is success
      "09 00 00 00 6f 01 00 11 00", # >16 walk results
      "07 00 00 00 79 01 00 00", # bytes after complete frame
      "08 00 00 00 79 01 00 00", # bytes inside clunk reply
      "07 00 00 00 ff 01 00", # unknown reply
    ]:
      expect NinepCodecError:
        discard malformed.hex().decodeReply(4096)

  test "local requests enforce lengths and special identities without truncating":
    expect NinepCodecError:
      discard NinepRequest(
        kind: NinepRequestKind.attach, fid: 1, uname: repeat("x", 65536)
      ).encodeRequest(1, ninepMaxMsize)
    expect NinepCodecError:
      discard NinepRequest(
        kind: NinepRequestKind.walk, fid: 1, newfid: 2, names: newSeq[string](17)
      ).encodeRequest(1, 4096)
    for component in ["", "a/b", "x\0y"]:
      expect NinepCodecError:
        discard NinepRequest(
          kind: NinepRequestKind.walk, fid: 1, newfid: 2, names: @[component]
        ).encodeRequest(1, 4096)
    expect NinepCodecError:
      discard NinepRequest(kind: NinepRequestKind.clunk, fid: ninepNoFid).encodeRequest(
        1, 4096
      )
    expect NinepCodecError:
      discard NinepRequest(kind: NinepRequestKind.clunk, fid: 1).encodeRequest(
        ninepNoTag, 4096
      )
    expect NinepCodecError:
      discard NinepRequest(
        kind: NinepRequestKind.write, fid: 1, data: newSeq[byte](4074)
      ).encodeRequest(1, 4096)

  test "attributes preserve qid and full width size":
    var frame = hex("a0 00 00 00 19 01 00")
    frame.add(newSeq[byte](153))
    frame[7] = 0xff
    frame[15] = 0x80
    frame[20] = 0x42
    frame[56] = 0x78
    frame[63] = 0x12
    let attributes = frame.decodeReply(4096).attributes
    check attributes.valid == 255
    check attributes.qid.kind == 0x80
    check attributes.qid.path == 0x42
    check attributes.size == 0x1200000000000078'u64

suite "bounded direct 9P client":
  test "negotiates base protocol and accepts out of order tags":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let one = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    let two = client.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 3))
    check one == 1 and two == 2
    server.sendBytes(hex("07 00 00 00 79 02 00 0c 00 00 00 75 01 00 01 00 00 00 41"))
    check client.receiveReply().tag == two
    let reply = client.receiveReply()
    check reply.tag == one and reply.data == @[0x41'u8]
    check client.pendingCount() == 0

  test "flush retires a blocked read and late original replies fail closed":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let old = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    discard client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: old))
    server.sendBytes(hex("07 00 00 00 6d 02 00"))
    check client.receiveReply().kind == NinepReplyKind.flush
    check client.pendingCount() == 0
    discard client.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 2))
    server.sendBytes(hex("0c 00 00 00 75 01 00 01 00 00 00 41"))
    expect NinepClientError:
      discard client.receiveReply()
    check client.pendingCount() == 0
    expect NinepClientError:
      discard client.negotiatedMsize()

  test "original reply before Rflush is delivered once":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let old = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    discard client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: old))
    server.sendBytes(hex("0c 00 00 00 75 01 00 01 00 00 00 41 07 00 00 00 6d 02 00"))
    check client.receiveReply().data == @[0x41'u8]
    check client.receiveReply().kind == NinepReplyKind.flush
    check client.pendingCount() == 0

  test "a full ordinary request window preserves a flush slot":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    for _ in 0 ..< ninepMaxPending:
      discard client.sendRequest(
        NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
      )
    expect NinepClientError:
      discard client.sendRequest(
        NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
      )
    let flushTag =
      client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: 1))
    check flushTag == 33
    check client.pendingCount() == ninepMaxPending + 1
    server.sendBytes(hex("07 00 00 00 6d 21 00"))
    discard client.receiveReply()
    check client.pendingCount() == ninepMaxPending - 1

  test "wrong tag, kind and count retire connection custody":
    for response in [
      "07 00 00 00 79 0a 00", # unknown tag
      "07 00 00 00 79 01 00", # wrong kind
      "0d 00 00 00 75 01 00 02 00 00 00 41 42", # over requested count
    ]:
      let (server, peer) = sockets()
      defer:
        server.close()
      let client = readyClient(server, peer)
      defer:
        client.close()
      discard client.sendRequest(
        NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
      )
      server.sendBytes(response.hex())
      expect NinepClientError:
        discard client.receiveReply()
      check client.pendingCount() == 0

  test "remote refusal is typed and does not close a healthy connection":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    server.sendBytes(hex("0b 00 00 00 07 01 00 74 00 00 00"))
    try:
      discard client.call(NinepRequest(kind: NinepRequestKind.clunk, fid: 2))
      check false
    except NinepRemoteError as error:
      check error.errno == 116
    check client.pendingCount() == 0
    check client.negotiatedMsize() == 4096

  test "incomplete body has a finite deadline and clears pending tags":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 50)
    defer:
      client.close()
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    server.sendBytes(hex("0c 00 00 00 75 01 00"))
    let start = getMonoTime()
    expect NinepClientError:
      discard client.receiveReply()
    check (getMonoTime() - start).inMilliseconds < 1000
    check client.pendingCount() == 0

  test "an unread socket bounds writes and tears down partial-frame custody":
    let (server, peer) = sockets()
    defer:
      server.close()
    var sendBuffer: cint = 1024
    require posix.setsockopt(
      peer.getFd(), SOL_SOCKET, SO_SNDBUF, addr sendBuffer, SockLen(sizeof(sendBuffer))
    ) == 0
    let client = readyClient(server, peer, timeoutMsec = 50)
    defer:
      client.close()
    let start = getMonoTime()
    var timedOut = false
    for _ in 0 ..< ninepMaxPending:
      try:
        discard client.sendRequest(
          NinepRequest(kind: NinepRequestKind.write, fid: 2, data: newSeq[byte](4073))
        )
      except NinepClientError:
        timedOut = true
        break
    check timedOut
    check (getMonoTime() - start).inMilliseconds < 1000
    check client.pendingCount() == 0
    expect NinepClientError:
      discard client.negotiatedMsize()

  test "unsupported version and message-size inflation cannot negotiate":
    for response in [
      "14 00 00 00 65 ff ff 00 10 00 00 07 00 75 6e 6b 6e 6f 77 6e",
      "15 00 00 00 65 ff ff 01 00 01 00 08 00 39 50 32 30 30 30 2e 4c",
      "15 00 00 00 65 ff ff ff 0f 00 00 08 00 39 50 32 30 30 30 2e 4c",
    ]:
      let (server, peer) = sockets()
      defer:
        server.close()
      server.sendBytes(response.hex())
      expect NinepClientError:
        discard peer.adoptNinepSocket(timeoutMsec = 500)

  test "failed renegotiation cannot retain the earlier negotiated session":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    discard
      client.sendRequest(NinepRequest(kind: NinepRequestKind.version, msize: 4096))
    expect NinepClientError:
      discard client.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 1))
    server.sendBytes(hex("0b 00 00 00 07 ff ff 16 00 00 00"))
    check client.receiveReply().kind == NinepReplyKind.lerror
    expect NinepClientError:
      discard client.negotiatedMsize()
    expect NinepClientError:
      discard client.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 1))
    server.sendBytes(
      hex("15 00 00 00 65 ff ff 00 10 00 00 08 00 39 50 32 30 30 30 2e 4c")
    )
    discard client.call(NinepRequest(kind: NinepRequestKind.version, msize: 4096))
    check client.negotiatedMsize() == 4096

  test "a flushed tag stays reserved through allocator wrap after its reply":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let old = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    let flushing =
      client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: old))
    require server.recv(32, 500).len == 32
    server.sendBytes(hex("0c 00 00 00 75 01 00 01 00 00 00 41"))
    require client.receiveReply().tag == old
    # Traverse the real tag namespace; no test hook changes allocator state.
    for _ in 0 ..< int(ninepNoTag) - 2:
      let tag = client.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 2))
      require server.recv(11, 500).len == 11
      server.sendBytes(@[7'u8, 0, 0, 0, 121, byte(tag and 255), byte(tag shr 8)])
      require client.receiveReply().tag == tag
    let next = client.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 2))
    require next != old and next != flushing
    require server.recv(11, 500).len == 11
    server.sendBytes(hex("07 00 00 00 6d 02 00"))
    server.sendBytes(@[7'u8, 0, 0, 0, 121, byte(next and 255), byte(next shr 8)])
    check client.receiveReply().tag == flushing
    check client.receiveReply().tag == next
    check client.pendingCount() == 0

  test "idle event waits preserve custody beyond the frame deadline":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 20)
    defer:
      client.close()
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    check client.tryReceiveReply(waitMsec = 50).isNone()
    check client.pendingCount() == 1
    check client.negotiatedMsize() == 4096
    server.sendBytes(hex("0c 00 00 00 75 01 00 01 00 00 00 41"))
    let reply = client.tryReceiveReply()
    require reply.isSome()
    check reply.get().data == @[0x41'u8]
    check client.pendingCount() == 0

  test "readable EOF is disconnect rather than idle":
    let (server, peer) = sockets()
    let client = readyClient(server, peer)
    defer:
      client.close()
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    discard server.recv(23, 500)
    server.close()
    expect NinepClientError:
      discard client.tryReceiveReply(waitMsec = 50)
    check client.pendingCount() == 0

  test "try receive owns a partial header until the assembly deadline":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer, timeoutMsec = 50)
    defer:
      client.close()
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    server.sendBytes(hex("0c 00 00"))
    let start = getMonoTime()
    expect NinepClientError:
      discard client.tryReceiveReply()
    check (getMonoTime() - start).inMilliseconds < 1000
    check client.pendingCount() == 0

  test "try receive completes one reply from a delayed frame suffix":
    let (server, peer) = sockets()
    let client = readyClient(server, peer, timeoutMsec = 500)
    discard client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    require server.recv(23, 500).len == 23
    server.sendBytes(hex("0c 00 00"))
    let child = posix.fork()
    require child >= 0
    if child == 0:
      client.close()
      # Deliberately fragment the reply while the parent holds its prefix.
      discard posix.usleep(20_000)
      server.sendBytes(hex("00 75 01 00 01 00 00 00 41"))
      server.close()
      posix.exitnow(0)
    server.close()
    defer:
      client.close()
    let reply = client.tryReceiveReply()
    require reply.isSome()
    check reply.get().data == @[0x41'u8]
    check client.pendingCount() == 0
    var status: cint
    check posix.waitpid(child, status, 0) == child
    check status == 0

  test "empty walk succeeds only for a zero-name clone":
    for names in [newSeq[string](), @["child"]]:
      let (server, peer) = sockets()
      defer:
        server.close()
      let client = readyClient(server, peer)
      defer:
        client.close()
      discard client.sendRequest(
        NinepRequest(kind: NinepRequestKind.walk, fid: 1, newfid: 2, names: names)
      )
      server.sendBytes(hex("09 00 00 00 6f 01 00 00 00"))
      if names.len == 0:
        check client.receiveReply().walked.len == 0
      else:
        expect NinepClientError:
          discard client.receiveReply()
      check client.pendingCount() == 0

  test "flush of flush and version during flush refuse without losing requests":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let old = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    let flushing =
      client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: old))
    expect NinepClientError:
      discard
        client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: flushing))
    expect NinepClientError:
      discard
        client.sendRequest(NinepRequest(kind: NinepRequestKind.version, msize: 4096))
    check client.pendingCount() == 2
    server.sendBytes(hex("07 00 00 00 6d 02 00"))
    check client.receiveReply().kind == NinepReplyKind.flush
    check client.pendingCount() == 0

  test "a partial walk reports its prefix without claiming newfid custody":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    discard client.sendRequest(
      NinepRequest(
        kind: NinepRequestKind.walk, fid: 1, newfid: 2, names: @["dir", "absent"]
      )
    )
    server.sendBytes(
      hex("16 00 00 00 6f 01 00 01 00 80 00 00 00 00 03 00 00 00 00 00 00 00")
    )
    let reply = client.receiveReply()
    check reply.walked.len == 1
    check reply.walked[0].path == 3
    check client.pendingCount() == 0

  test "flush cannot be answered with a remote error":
    let (server, peer) = sockets()
    defer:
      server.close()
    let client = readyClient(server, peer)
    defer:
      client.close()
    let old = client.sendRequest(
      NinepRequest(kind: NinepRequestKind.read, fid: 2, readCount: 1)
    )
    discard client.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: old))
    server.sendBytes(hex("0b 00 00 00 07 02 00 05 00 00 00"))
    expect NinepClientError:
      discard client.receiveReply()
    check client.pendingCount() == 0
    expect NinepClientError:
      discard client.negotiatedMsize()
