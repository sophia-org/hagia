import ../types/ninep

## Base .L framing, independent of Sophia's codec and of the old WM envelope.
## The specification is https://github.com/chaos/diod/blob/master/protocol.md.

type NinepCodecError* = object of CatchableError

proc malformed(message: string) {.noreturn.} =
  raise newException(NinepCodecError, message)

proc requireBytes(data: openArray[byte], offset, count: int) =
  if offset < 0 or count < 0 or offset > data.len or count > data.len - offset:
    malformed("truncated 9P field")

proc readU16(data: openArray[byte], offset: var int): uint16 =
  data.requireBytes(offset, 2)
  result = uint16(data[offset]) or (uint16(data[offset + 1]) shl 8)
  offset += 2

proc readU32(data: openArray[byte], offset: var int): uint32 =
  data.requireBytes(offset, 4)
  for index in 0 ..< 4:
    result = result or (uint32(data[offset + index]) shl (index * 8))
  offset += 4

proc readU64(data: openArray[byte], offset: var int): uint64 =
  data.requireBytes(offset, 8)
  for index in 0 ..< 8:
    result = result or (uint64(data[offset + index]) shl (index * 8))
  offset += 8

proc addU16(data: var seq[byte], value: uint16) =
  for index in 0 ..< 2:
    data.add(byte((value shr (index * 8)) and 0xff))

proc addU32(data: var seq[byte], value: uint32) =
  for index in 0 ..< 4:
    data.add(byte((value shr (index * 8)) and 0xff))

proc addU64(data: var seq[byte], value: uint64) =
  for index in 0 ..< 8:
    data.add(byte((value shr (index * 8)) and 0xff))

proc addString(data: var seq[byte], value: string) =
  if value.len > int(high(uint16)):
    malformed("9P string exceeds u16 length")
  data.addU16(uint16(value.len))
  for character in value:
    data.add(byte(character))

proc readString(data: openArray[byte], offset: var int): string =
  let count = int(data.readU16(offset))
  data.requireBytes(offset, count)
  result = newString(count)
  for index in 0 ..< count:
    result[index] = char(data[offset + index])
  offset += count

proc readQid(data: openArray[byte], offset: var int): NinepQid =
  data.requireBytes(offset, 13)
  result.kind = data[offset]
  inc offset
  result.version = data.readU32(offset)
  result.path = data.readU64(offset)

proc checkMsize(msize: uint32) =
  if msize < ninepMinMsize or msize > ninepMaxMsize:
    malformed("9P message limit outside supported range")

proc frameLength*(prefix: openArray[byte], msize: uint32): int =
  msize.checkMsize()
  var offset = 0
  let size = prefix.readU32(offset)
  if size < uint32(ninepHeaderBytes) or size > msize:
    malformed("9P frame length outside negotiated bound")
  int(size)

proc encodeRequest*(request: NinepRequest, tag: uint16, msize: uint32): seq[byte] =
  msize.checkMsize()
  if tag == ninepNoTag and request.kind != NinepRequestKind.version:
    malformed("NOTAG is reserved for version")
  if request.kind notin {NinepRequestKind.version, NinepRequestKind.flush} and
      request.fid == ninepNoFid:
    malformed("NOFID is not an operation fid")
  result = newSeq[byte](4)
  result.add(byte(ord(request.kind)))
  result.addU16(tag)
  case request.kind
  of NinepRequestKind.invalid:
    malformed("invalid 9P request kind")
  of NinepRequestKind.version:
    request.msize.checkMsize()
    result.addU32(request.msize)
    result.addString(ninepVersion)
  of NinepRequestKind.attach:
    result.addU32(request.fid)
    result.addU32(ninepNoFid)
    result.addString(request.uname)
    result.addString(request.aname)
    result.addU32(high(uint32)) # Names grant nothing; do not claim a numeric UID.
  of NinepRequestKind.walk:
    if request.newfid == ninepNoFid or request.names.len > ninepMaxWalk:
      malformed("invalid walk fid or name count")
    result.addU32(request.fid)
    result.addU32(request.newfid)
    result.addU16(uint16(request.names.len))
    for name in request.names:
      if name.len == 0 or '/' in name or '\0' in name:
        malformed("invalid walk component")
      result.addString(name)
  of NinepRequestKind.lopen:
    result.addU32(request.fid)
    result.addU32(request.flags)
  of NinepRequestKind.getattr:
    result.addU32(request.fid)
    result.addU64(request.attributeMask)
  of NinepRequestKind.read:
    if request.readCount > msize - 11:
      malformed("read exceeds negotiated reply size")
    result.addU32(request.fid)
    result.addU64(request.readOffset)
    result.addU32(request.readCount)
  of NinepRequestKind.write:
    if request.data.len > int(msize) - 23:
      malformed("write exceeds negotiated frame size")
    result.addU32(request.fid)
    result.addU64(request.writeOffset)
    result.addU32(uint32(request.data.len))
    result.add(request.data)
  of NinepRequestKind.clunk:
    result.addU32(request.fid)
  of NinepRequestKind.flush:
    result.addU16(request.oldtag)
  if result.len > int(msize):
    malformed("encoded request exceeds negotiated frame size")
  for index in 0 ..< 4:
    result[index] = byte((uint32(result.len) shr (index * 8)) and 0xff)

proc replyKind(raw: byte): NinepReplyKind =
  case raw
  of 7:
    NinepReplyKind.lerror
  of 13:
    NinepReplyKind.lopen
  of 25:
    NinepReplyKind.getattr
  of 101:
    NinepReplyKind.version
  of 105:
    NinepReplyKind.attach
  of 109:
    NinepReplyKind.flush
  of 111:
    NinepReplyKind.walk
  of 117:
    NinepReplyKind.read
  of 119:
    NinepReplyKind.write
  of 121:
    NinepReplyKind.clunk
  else:
    malformed("unsupported 9P reply kind")

proc readAttributes(data: openArray[byte], offset: var int): NinepAttributes =
  result.valid = data.readU64(offset)
  result.qid = data.readQid(offset)
  result.mode = data.readU32(offset)
  result.uid = data.readU32(offset)
  result.gid = data.readU32(offset)
  result.nlink = data.readU64(offset)
  result.rdev = data.readU64(offset)
  result.size = data.readU64(offset)
  result.blockSize = data.readU64(offset)
  result.blocks = data.readU64(offset)
  result.atimeSec = data.readU64(offset)
  result.atimeNsec = data.readU64(offset)
  result.mtimeSec = data.readU64(offset)
  result.mtimeNsec = data.readU64(offset)
  result.ctimeSec = data.readU64(offset)
  result.ctimeNsec = data.readU64(offset)
  result.btimeSec = data.readU64(offset)
  result.btimeNsec = data.readU64(offset)
  result.generation = data.readU64(offset)
  result.dataVersion = data.readU64(offset)

proc decodeReply*(data: openArray[byte], msize: uint32): NinepReply =
  let size = data.frameLength(msize)
  if data.len != size:
    malformed("9P frame is truncated or has trailing bytes")
  var offset = 5
  let tag = data.readU16(offset)
  result = NinepReply(kind: data[4].replyKind(), tag: tag)
  case result.kind
  of NinepReplyKind.invalid:
    malformed("invalid 9P reply kind")
  of NinepReplyKind.version:
    result.msize = data.readU32(offset)
    result.version = data.readString(offset)
  of NinepReplyKind.lerror:
    result.errno = data.readU32(offset)
    if result.errno == 0:
      malformed("Rlerror cannot report success")
  of NinepReplyKind.attach:
    result.attached = data.readQid(offset)
  of NinepReplyKind.walk:
    let count = int(data.readU16(offset))
    if count > ninepMaxWalk:
      malformed("Rwalk exceeds maximum name count")
    data.requireBytes(offset, count * 13)
    for _ in 0 ..< count:
      result.walked.add(data.readQid(offset))
  of NinepReplyKind.lopen:
    result.opened = data.readQid(offset)
    result.iounit = data.readU32(offset)
  of NinepReplyKind.getattr:
    result.attributes = data.readAttributes(offset)
  of NinepReplyKind.read:
    let count = data.readU32(offset)
    if uint64(count) > uint64(data.len - offset):
      malformed("Rread count exceeds frame")
    result.data = newSeq[byte](int(count))
    for index in 0 ..< int(count):
      result.data[index] = data[offset + index]
    offset += int(count)
  of NinepReplyKind.write:
    result.count = data.readU32(offset)
  of NinepReplyKind.flush, NinepReplyKind.clunk:
    discard
  if offset != data.len:
    malformed("9P reply contains trailing bytes")

proc matchesRequest*(reply: NinepReply, request: NinepPending): bool =
  ## Correlate replies before exposing bytes to the WM file adapter.
  if reply.kind == NinepReplyKind.lerror:
    return request.kind != NinepRequestKind.flush
  if ord(reply.kind) != ord(request.kind) + 1:
    return false
  case request.kind
  of NinepRequestKind.version:
    reply.version == ninepVersion and reply.msize >= ninepMinMsize and
      reply.msize <= request.bound
  of NinepRequestKind.walk:
    reply.walked.len <= int(request.bound) and
      (request.bound == 0 or reply.walked.len > 0)
  of NinepRequestKind.read:
    reply.data.len <= int(request.bound)
  of NinepRequestKind.write:
    reply.count <= request.bound
  else:
    true
