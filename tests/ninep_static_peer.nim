import std/[net, os]
import types/ninep
import ninep/client

## Independent client for Sophia t247's static test export. No WM or native
## acceptance is implied; the executable fails if any expected operation drifts.

proc require(condition: bool, message: string) =
  if not condition:
    raise newException(IOError, message)

proc walk(client: NinepClient, fid: uint32, names: seq[string]) =
  let response = client.call(
    NinepRequest(kind: NinepRequestKind.walk, fid: 1, newfid: fid, names: names)
  )
  require(response.walked.len == names.len, "static export walk was incomplete")

proc open(client: NinepClient, fid: uint32, flags = 0'u32) =
  discard
    client.call(NinepRequest(kind: NinepRequestKind.lopen, fid: fid, flags: flags))

proc clunk(client: NinepClient, fid: uint32) =
  discard client.call(NinepRequest(kind: NinepRequestKind.clunk, fid: fid))

proc refused(client: NinepClient, request: NinepRequest, errno: uint32) =
  try:
    discard client.call(request)
  except NinepRemoteError as error:
    require(error.errno == errno, "unexpected refusal errno: " & $error.errno)
    return
  raise newException(IOError, "static export accepted an operation expected to refuse")

proc run(path: string) =
  let socket =
    newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP, false)
  try:
    socket.connectUnix(path)
  except CatchableError:
    socket.close()
    raise
  let peer = socket.adoptNinepSocket(msize = 4096)
  defer:
    peer.close()
  require(peer.negotiatedMsize() == 4096, "wrong negotiated message size")
  let root = peer.call(NinepRequest(kind: NinepRequestKind.attach, fid: 1)).attached
  require(root.kind == 0x80 and root.path != 0, "attach did not return a directory qid")
  let parent = peer.call(
    NinepRequest(kind: NinepRequestKind.walk, fid: 1, newfid: 2, names: @[".."])
  )
  require(
    parent.walked.len == 1 and parent.walked[0] == root, "walk escaped attach root"
  )
  peer.clunk(2)

  peer.walk(2, @["info"])
  peer.open(2)
  let attrs = peer.call(
    NinepRequest(kind: NinepRequestKind.getattr, fid: 2, attributeMask: 0x303)
  ).attributes
  require(
    (attrs.valid and 0x303) == 0x303 and attrs.size == 70000, "wrong static attributes"
  )
  var offset = 0'u64
  while offset < attrs.size:
    let response = peer.call(
      NinepRequest(
        kind: NinepRequestKind.read, fid: 2, readOffset: offset, readCount: 997
      )
    )
    require(response.data.len > 0, "premature EOF in fragmented static read")
    for index, value in response.data:
      require(
        value == byte((offset + uint64(index)) mod 251), "static read bytes differ"
      )
    offset += uint64(response.data.len)
  require(offset == attrs.size, "static read exceeded advertised length")
  require(
    peer.call(
      NinepRequest(
        kind: NinepRequestKind.read, fid: 2, readOffset: offset, readCount: 1
      )
    ).data.len == 0,
    "expected EOF",
  )
  peer.clunk(2)

  peer.walk(3, @["dir", "leaf"])
  peer.open(3)
  require(
    peer.call(NinepRequest(kind: NinepRequestKind.read, fid: 3, readCount: 4)).data ==
      @[0'u8, 1, 2, 3],
    "wrong leaf contents",
  )
  peer.clunk(3)
  peer.refused(
    NinepRequest(kind: NinepRequestKind.walk, fid: 1, newfid: 4, names: @["hidden"]), 13
  )
  peer.walk(4, @["info"])
  peer.refused(NinepRequest(kind: NinepRequestKind.lopen, fid: 4, flags: 1), 13)
  peer.clunk(4)
  peer.walk(4, @["sink"])
  peer.refused(NinepRequest(kind: NinepRequestKind.lopen, fid: 4), 13)
  peer.open(4, 1)
  require(
    peer.call(NinepRequest(kind: NinepRequestKind.write, fid: 4, data: @[1'u8, 2, 3])).count ==
      3,
    "wrong accepted byte count",
  )
  peer.clunk(4)

  peer.walk(5, @["events"])
  peer.open(5)
  let old =
    peer.sendRequest(NinepRequest(kind: NinepRequestKind.read, fid: 5, readCount: 1))
  let flushing =
    peer.sendRequest(NinepRequest(kind: NinepRequestKind.flush, oldtag: old))
  let flushed = peer.receiveReply()
  require(
    flushed.kind == NinepReplyKind.flush and flushed.tag == flushing,
    "blocked read was not flushed",
  )
  require(peer.pendingCount() == 0, "flush leaked local request custody")
  let reading =
    peer.sendRequest(NinepRequest(kind: NinepRequestKind.read, fid: 5, readCount: 1))
  let clunking = peer.sendRequest(NinepRequest(kind: NinepRequestKind.clunk, fid: 5))
  let ended = peer.receiveReply()
  require(
    ended.tag == reading and ended.kind == NinepReplyKind.lerror and ended.errno == 9,
    "clunk did not settle the blocked read",
  )
  let clunked = peer.receiveReply()
  require(
    clunked.tag == clunking and clunked.kind == NinepReplyKind.clunk,
    "clunk reply did not follow read settlement",
  )
  require(peer.pendingCount() == 0, "clunk leaked local request custody")
  peer.clunk(1)

if paramCount() != 1:
  quit("usage: ninep_static_peer <socket>", 2)
try:
  run(paramStr(1))
  echo "hagia_9p_static_peer schema=1 status=pass msize=4096 read_bytes=70000 flush=true clunk=true"
except CatchableError as error:
  quit("hagia_9p_static_peer status=failed reason=" & error.msg, 1)
