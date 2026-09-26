import std/[monotimes, options, os, posix, times]
import sophia/wm_files

## A bounded scripted 9P peer for the file wire's flow tests. Control requests
## must arrive in script order and get the prescribed reply. The one events
## read is parked and answered from the bytes steps have released so far, at
## the requested offset. There is no journal, permit or admission state here:
## this is flow and refusal evidence for Hagia's client, not conformance, and
## the real Sophia peer remains required.

const
  tversion* = 100'u8
  tattach* = 104'u8
  twalk* = 110'u8
  tlopen* = 12'u8
  tgetattr* = 24'u8
  tread* = 116'u8
  twrite* = 118'u8
  tclunk* = 120'u8
  peerMsize* = 65536'u32
  eventsFid = 3'u32
  peerIdleMillis = 20_000

type
  PeerEvent* = object
    bytes*: seq[byte]
    ## Most bytes one read gets; zero means as many as it asks for.
    perRead*: int
    ## Wait before each fragment, and once more before the first.
    delayMs*, leadMs*: int

  PeerStep* = object
    kind*: uint8
    fid*: uint32
    ## Reply body; a write with none answers the count it received.
    reply*: seq[byte]
    refusal*: uint32
    ## Released to the events stream after the reply.
    events*: seq[PeerEvent]
    ## Released before the reply, which waits `delayMs` while the parked
    ## events read keeps being served.
    early*: seq[PeerEvent]
    delayMs*: int

  PeerScript* = object
    fd*: cint
    steps*: seq[PeerStep]

  Seen* = object
    kind*: uint8
    tag*: uint16
    fid*, flags*, count*: uint32
    offset*, mask*: uint64
    names*: seq[string]
    data*: seq[byte]

  PeerLog* = object
    seen*: seq[Seen]
    stepsDone*, eventReads*: int
    failure*: string

var peerResults*: Channel[PeerLog]

proc qid*(kind: uint8, path: uint64): seq[byte] =
  result.add(kind)
  result.addU32(0)
  result.addU64(path)

proc str(value: string): seq[byte] =
  result.addU16(uint16(value.len))
  for character in value:
    result.add(byte(character))

proc versionStep*(): PeerStep =
  var body: seq[byte]
  body.addU32(peerMsize)
  body.add(str("9P2000.L"))
  PeerStep(kind: tversion, reply: body)

proc attachStep*(): PeerStep =
  PeerStep(kind: tattach, fid: 1, reply: qid(0x80, 1))

proc walkStep*(path: uint64): PeerStep =
  var body: seq[byte]
  body.addU16(1)
  body.add(qid(0, path))
  PeerStep(kind: twalk, fid: 1, reply: body)

proc openStep*(fid: uint32, path: uint64): PeerStep =
  var body = qid(0, path)
  body.addU32(0)
  PeerStep(kind: tlopen, fid: fid, reply: body)

proc attributes(size, path: uint64): seq[byte] =
  result.addU64(0x3fff)
  result.add(qid(0, path))
  for _ in 0 ..< 3:
    result.addU32(0)
  result.addU64(1)
  result.addU64(0)
  result.addU64(size)
  for _ in 0 ..< 12:
    result.addU64(0)

proc objectSteps*(bytes: seq[byte], path: uint64): seq[PeerStep] =
  ## Walk, open, stat, one read, stat and clunk of an object on fid 2.
  var data: seq[byte]
  data.addU32(uint32(bytes.len))
  data.add(bytes)
  @[
    walkStep(path),
    openStep(2, path),
    PeerStep(kind: tgetattr, fid: 2, reply: attributes(uint64(bytes.len), path)),
    PeerStep(kind: tread, fid: 2, reply: data),
    PeerStep(kind: tgetattr, fid: 2, reply: attributes(uint64(bytes.len), path)),
    PeerStep(kind: tclunk, fid: 2),
  ]

proc writeStep*(fid: uint32, events: seq[PeerEvent] = @[], refusal = 0'u32): PeerStep =
  PeerStep(kind: twrite, fid: fid, refusal: refusal, events: events)

proc clunkStep*(fid: uint32): PeerStep =
  PeerStep(kind: tclunk, fid: fid)

proc released*(bytes: varargs[seq[byte]]): seq[PeerEvent] =
  for record in bytes:
    result.add(PeerEvent(bytes: record))

proc sendAll(fd: cint, bytes: seq[byte]) =
  var sent = 0
  while sent < bytes.len:
    let count = posix.send(
      SocketHandle(fd), unsafeAddr bytes[sent], bytes.len - sent, MSG_NOSIGNAL
    )
    if count <= 0:
      if errno in [EPIPE, ECONNRESET]:
        raise newException(EOFError, "client closed")
      raise newException(IOError, "peer write failed")
    sent += count

proc receiveExactly(fd: cint, count: int): seq[byte] =
  ## Empty at EOF before any byte; an idle peer gives up rather than hang.
  result = newSeq[byte](count)
  var offset = 0
  while offset < count:
    var descriptor = TPollfd(fd: fd, events: POLLIN)
    if posix.poll(addr descriptor, Tnfds(1), cint(peerIdleMillis)) <= 0:
      raise newException(IOError, "peer idle deadline")
    let received = posix.recv(SocketHandle(fd), addr result[offset], count - offset, 0)
    if received == 0:
      if offset == 0:
        return @[]
      raise newException(IOError, "peer EOF inside a request")
    if received < 0:
      if errno == ECONNRESET and offset == 0:
        return @[]
      raise newException(IOError, "peer read failed")
    offset += received

proc reply(fd: cint, kind: uint8, tag: uint16, body: seq[byte]) =
  var frame: seq[byte]
  frame.addU32(uint32(7 + body.len))
  frame.add(kind)
  frame.addU16(tag)
  frame.add(body)
  fd.sendAll(frame)

proc parse(frame: seq[byte]): Seen =
  result.kind = frame[4]
  result.tag = frame.readU16(5)
  var at = 7
  proc text(frame: seq[byte], at: var int): string =
    let length = int(frame.readU16(at))
    at += 2
    for index in 0 ..< length:
      result.add(char(frame[at + index]))
    at += length

  case result.kind
  of tversion:
    discard
  of tattach, tlopen, tgetattr, tread, twrite, tclunk, twalk:
    result.fid = frame.readU32(at)
    at += 4
    case result.kind
    of tlopen:
      result.flags = frame.readU32(at)
    of tgetattr:
      result.mask = frame.readU64(at)
    of tread:
      result.offset = frame.readU64(at)
      result.count = frame.readU32(at + 8)
    of twrite:
      result.offset = frame.readU64(at)
      result.count = frame.readU32(at + 8)
      result.data = frame[at + 12 ..< frame.len]
    of twalk:
      at += 4
      let names = int(frame.readU16(at))
      at += 2
      for _ in 0 ..< names:
        result.names.add(frame.text(at))
    else:
      discard
  else:
    raise newException(IOError, "peer got an unscripted request type " & $result.kind)

proc readable(fd: cint, millis: int): bool =
  var descriptor = TPollfd(fd: fd, events: POLLIN)
  posix.poll(addr descriptor, Tnfds(1), cint(max(0, millis))) > 0

proc answer(fd: cint, seen: Seen, expected: PeerStep) =
  if expected.refusal != 0:
    var body: seq[byte]
    body.addU32(expected.refusal)
    fd.reply(7, seen.tag, body)
  elif seen.kind == twrite and expected.reply.len == 0:
    var body: seq[byte]
    body.addU32(uint32(seen.data.len))
    fd.reply(twrite + 1, seen.tag, body)
  else:
    fd.reply(seen.kind + 1, seen.tag, expected.reply)

proc serve*(script: PeerScript) {.thread.} =
  var log: PeerLog
  var parked: Option[Seen]
  var pending: Option[(Seen, PeerStep, MonoTime)]
  var stream: seq[PeerEvent]
  var position = 0
  var delivered = 0'u64
  var step = 0
  try:
    while true:
      if parked.isSome and stream.len > 0:
        let event = stream[0]
        if position == 0 and event.leadMs > 0:
          sleep(event.leadMs)
        if event.delayMs > 0:
          sleep(event.delayMs)
        var count = min(int(parked.get().count), event.bytes.len - position)
        if event.perRead > 0:
          count = min(count, event.perRead)
        var body: seq[byte]
        body.addU32(uint32(count))
        body.add(event.bytes[position ..< position + count])
        script.fd.reply(tread + 1, parked.get().tag, body)
        position += count
        delivered += uint64(count)
        if position == event.bytes.len:
          stream.delete(0)
          position = 0
        parked = none(Seen)
        inc log.eventReads
        continue
      if pending.isSome:
        let (seen, expected, due) = pending.get()
        let wait = int((due - getMonoTime()).inMilliseconds)
        if wait <= 0 or not script.fd.readable(wait):
          script.fd.answer(seen, expected)
          stream.add(expected.events)
          pending = none((Seen, PeerStep, MonoTime))
          continue
      let prefix = script.fd.receiveExactly(4)
      if prefix.len == 0:
        break
      var frame = prefix
      frame.add(script.fd.receiveExactly(int(prefix.readU32(0)) - 4))
      let seen = frame.parse()
      log.seen.add(seen)
      if seen.kind == tread and seen.fid == eventsFid:
        if parked.isSome:
          raise newException(IOError, "a second events read while one is parked")
        if seen.offset != delivered:
          raise newException(IOError, "events read at the wrong offset")
        parked = some(seen)
        continue
      if step >= script.steps.len:
        raise newException(
          IOError, "unscripted request " & $seen.kind & " on fid " & $seen.fid
        )
      let expected = script.steps[step]
      inc step
      if expected.kind != seen.kind or expected.fid != seen.fid:
        raise newException(
          IOError,
          "step " & $(step - 1) & " expected " & $expected.kind & " on fid " &
            $expected.fid & ", got " & $seen.kind & " on fid " & $seen.fid,
        )
      if pending.isSome:
        raise newException(IOError, "a second control request while one is pending")
      stream.add(expected.early)
      pending = some(
        (seen, expected, getMonoTime() + initDuration(milliseconds = expected.delayMs))
      )
  except EOFError:
    # The client closed while a reply was on its way; that is its choice.
    discard
  except CatchableError as error:
    log.failure = error.msg
  log.stepsDone = step
  discard posix.close(script.fd)
  peerResults.send(log)
