import std/[monotimes, net, options, os, times]
import types/[ninep, wm_files]
import ninep/client
import sophia/wm_files

## Test-only file custody for the independent, prebuilt Session peer. No
## endpoint authentication or production WM loop is supplied by this fixture.

type WmFileTestPeer* = ref object
  client: NinepClient
  epoch*: uint64
  selected*: uint64
  eventOffset: uint64
  sequence: uint64
  buffered: seq[byte]

proc requirePeer*(condition: bool, message: string) =
  if not condition:
    raise newException(IOError, message)

proc close*(peer: WmFileTestPeer) =
  peer.client.close()

proc openFile(peer: WmFileTestPeer, fid: uint32, name: string, flags: uint32) =
  let walked = peer.client.call(
    NinepRequest(kind: NinepRequestKind.walk, fid: 1, newfid: fid, names: @[name])
  )
  requirePeer(walked.walked.len == 1, "incomplete walk to " & name)
  discard
    peer.client.call(NinepRequest(kind: NinepRequestKind.lopen, fid: fid, flags: flags))

proc clunk(peer: WmFileTestPeer, fid: uint32) =
  discard peer.client.call(NinepRequest(kind: NinepRequestKind.clunk, fid: fid))

proc write(peer: WmFileTestPeer, fid: uint32, offset: uint64, data: seq[byte]) =
  let response = peer.client.call(
    NinepRequest(
      kind: NinepRequestKind.write, fid: fid, writeOffset: offset, data: data
    )
  )
  requirePeer(response.count == uint32(data.len), "short file write")

proc connectFilePeer*(path: string): WmFileTestPeer =
  let socket =
    newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP, false)
  try:
    socket.connectUnix(path)
  except CatchableError:
    socket.close()
    raise
  result = WmFileTestPeer(client: socket.adoptNinepSocket(msize = 4096))
  try:
    let root =
      result.client.call(NinepRequest(kind: NinepRequestKind.attach, fid: 1)).attached
    requirePeer(
      root.kind == 0x80 and root.path != 0, "attach did not return a directory"
    )
    result.openFile(3, "events", 0)
    result.openFile(4, "submit", 1)
    result.openFile(5, "ack", 1)
  except CatchableError:
    result.close()
    raise

proc readObject*(peer: WmFileTestPeer, name: string): seq[byte] =
  peer.openFile(2, name, 0)
  defer:
    peer.clunk(2)
  let attributes = peer.client.call(
    NinepRequest(kind: NinepRequestKind.getattr, fid: 2, attributeMask: 0x303)
  ).attributes
  requirePeer((attributes.valid and 0x303) == 0x303, "incomplete object attributes")
  requirePeer(
    attributes.size > 0 and attributes.size <= uint64(wmFileMaxBytes),
    "object size bound",
  )
  while uint64(result.len) < attributes.size:
    let bytes = peer.client.call(
      NinepRequest(
        kind: NinepRequestKind.read,
        fid: 2,
        readOffset: uint64(result.len),
        readCount: 37,
      )
    ).data
    requirePeer(
      bytes.len > 0 and uint64(bytes.len) <= attributes.size - uint64(result.len),
      "object EOF/size mismatch",
    )
    result.add(bytes)
  let after = peer.client.call(
    NinepRequest(kind: NinepRequestKind.getattr, fid: 2, attributeMask: 0x303)
  ).attributes
  requirePeer(
    after.qid == attributes.qid and after.size == attributes.size,
    "open object changed identity",
  )

proc nextEvent*(peer: WmFileTestPeer, expected: WmFileKind): seq[byte] =
  # A fixture deadline escapes to the top-level close, which cancels its
  # outstanding read tag. This one-shot peer never resumes a timed-out frame.
  let deadline = getMonoTime() + initDuration(seconds = 12)
  while true:
    if peer.buffered.len >= 4:
      let count = peer.buffered.readU32(0)
      requirePeer(
        count >= uint32(wmFileHeaderBytes) and count <= uint32(wmFileMaxBytes),
        "event length bound",
      )
      if peer.buffered.len >= int(count):
        result = peer.buffered[0 ..< int(count)]
        peer.buffered = peer.buffered[int(count) ..< peer.buffered.len]
        let header = result.decodeRecord(WmFileClass.eventRecord)
        header.requireKind(expected)
        requirePeer(header.connectionEpoch == peer.epoch, "event epoch mismatch")
        requirePeer(
          header.sequence == peer.sequence + 1, "event sequence gap or replay"
        )
        peer.sequence = header.sequence
        return
    requirePeer(getMonoTime() < deadline, "complete event deadline")
    # Force a split inside the 32-byte file header even for small events.
    let count = min(23, wmFileMaxBytes - peer.buffered.len)
    requirePeer(count > 0, "event assembly exceeded bound")
    let tag = peer.client.sendRequest(
      NinepRequest(
        kind: NinepRequestKind.read,
        fid: 3,
        readOffset: peer.eventOffset,
        readCount: uint32(count),
      )
    )
    var response: Option[NinepReply]
    while response.isNone:
      requirePeer(getMonoTime() < deadline, "event readiness deadline")
      response = peer.client.tryReceiveReply(100)
    let reply = response.get()
    requirePeer(
      reply.tag == tag and reply.kind == NinepReplyKind.read, "event read refused"
    )
    requirePeer(reply.data.len > 0, "event stream returned empty instead of waiting")
    peer.eventOffset += uint64(reply.data.len)
    peer.buffered.add(reply.data)

proc ack*(peer: WmFileTestPeer, bytes: seq[byte]) =
  let header = bytes.decodeRecord(WmFileClass.eventRecord)
  peer.write(
    5, 0, WmFileAck(connectionEpoch: peer.epoch, sequence: header.sequence).encodeAck()
  )

proc submit*(peer: WmFileTestPeer, bytes: seq[byte]) =
  let header = bytes.decodeRecord(WmFileClass.candidateRecord)
  requirePeer(header.connectionEpoch == peer.epoch, "candidate epoch mismatch")
  peer.openFile(6, "transaction", 2)
  var offset = 0
  while offset < bytes.len:
    # Every candidate spans writes, including its file header.
    let finish = min(offset + 17, bytes.len)
    peer.write(6, uint64(offset), bytes[offset ..< finish])
    offset = finish
  let submit = WmFileSubmit(
    connectionEpoch: peer.epoch,
    submissionId: header.submissionId,
    candidateBytes: uint32(bytes.len),
  ).encodeSubmit()
  let deadline = getMonoTime() + initDuration(seconds = 4)
  while true:
    try:
      peer.write(4, 0, submit)
      return
    except NinepRemoteError as error:
      if error.errno != 11:
        raise
      requirePeer(getMonoTime() < deadline, "submit permission deadline")
      # Refused custody is retryable; a bounded test peer backs off instead of
      # busy-looping while the driver transfers its next receive permit.
      sleep(10)

proc releaseCandidate*(peer: WmFileTestPeer, submitted: seq[byte]) =
  peer.ack(submitted)
  peer.clunk(6)

proc candidateHeader*(
    peer: WmFileTestPeer, kind: WmFileKind, id: uint64
): WmFileHeader =
  WmFileHeader(kind: kind, connectionEpoch: peer.epoch, submissionId: id)
