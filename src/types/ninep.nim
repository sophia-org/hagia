## Independent base 9P2000.L layouts. No Sophia policy identity lives here.

const
  ninepHeaderBytes* = 7
  ninepMinMsize* = 4096'u32
  ninepMaxMsize* = 65536'u32
  ninepMaxWalk* = 16
  ninepMaxPending* = 32
  ninepNoTag* = high(uint16)
  ninepNoFid* = high(uint32)
  ninepVersion* = "9P2000.L"

type
  NinepRequestKind* {.pure.} = enum
    invalid = 0
    lopen = 12
    getattr = 24
    version = 100
    attach = 104
    flush = 108
    walk = 110
    read = 116
    write = 118
    clunk = 120

  NinepReplyKind* {.pure.} = enum
    invalid = 0
    lerror = 7
    lopen = 13
    getattr = 25
    version = 101
    attach = 105
    flush = 109
    walk = 111
    read = 117
    write = 119
    clunk = 121

  NinepQid* = object
    kind*: uint8
    version*: uint32
    path*: uint64

  NinepAttributes* = object
    valid*: uint64
    qid*: NinepQid
    mode*, uid*, gid*: uint32
    nlink*, rdev*, size*, blockSize*, blocks*: uint64
    atimeSec*, atimeNsec*, mtimeSec*, mtimeNsec*: uint64
    ctimeSec*, ctimeNsec*, btimeSec*, btimeNsec*: uint64
    generation*, dataVersion*: uint64

  NinepRequest* = object
    fid*: uint32
    case kind*: NinepRequestKind
    of NinepRequestKind.version:
      msize*: uint32
    of NinepRequestKind.attach:
      uname*, aname*: string
    of NinepRequestKind.walk:
      newfid*: uint32
      names*: seq[string]
    of NinepRequestKind.lopen:
      flags*: uint32
    of NinepRequestKind.getattr:
      attributeMask*: uint64
    of NinepRequestKind.read:
      readOffset*: uint64
      readCount*: uint32
    of NinepRequestKind.write:
      writeOffset*: uint64
      data*: seq[byte]
    of NinepRequestKind.flush:
      oldtag*: uint16
    of NinepRequestKind.clunk, NinepRequestKind.invalid:
      discard

  NinepReply* = object
    tag*: uint16
    case kind*: NinepReplyKind
    of NinepReplyKind.lerror:
      errno*: uint32
    of NinepReplyKind.version:
      msize*: uint32
      version*: string
    of NinepReplyKind.attach:
      attached*: NinepQid
    of NinepReplyKind.walk:
      walked*: seq[NinepQid]
    of NinepReplyKind.lopen:
      opened*: NinepQid
      iounit*: uint32
    of NinepReplyKind.getattr:
      attributes*: NinepAttributes
    of NinepReplyKind.read:
      data*: seq[byte]
    of NinepReplyKind.write:
      count*: uint32
    of NinepReplyKind.flush, NinepReplyKind.clunk, NinepReplyKind.invalid:
      discard

  NinepPending* = object
    kind*: NinepRequestKind
    bound*: uint32
    oldtag*: uint16
