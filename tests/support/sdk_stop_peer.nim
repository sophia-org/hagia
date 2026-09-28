import std/os
# Links the pinned SDK sources the test engine calls into.
import sophia/desktop_sdk

const supportDir = currentSourcePath().parentDir
{.passC: "-I" & supportDir.}
{.compile: supportDir / "sdk_stop_peer.c".}

type
  StopScript* {.pure.} = enum
    mute
    idle
    ambiguous
    commitThen

  StopStage* {.pure.} = enum
    waiting
    connected
    idleRead
    unsettled

  StopPeerState* {.
    importc: "struct hagia_sdk_stop_peer", header: "sdk_stop_peer.h", bycopy
  .} = object
    script*, stage*, configurations*, projections*, closed*: cuint
    status*: cint

  StopPeerTask* = object
    listener*: cint
    state*: ptr StopPeerState

proc serve(
  listener: cint, state: ptr StopPeerState
) {.
  importc: "hagia_sdk_stop_peer", header: "sdk_stop_peer.h", cdecl, gcsafe, raises: []
.}

proc serveStopPeer*(task: StopPeerTask) {.thread.} =
  serve(task.listener, task.state)

proc stage*(state: ptr StopPeerState): StopStage =
  StopStage(atomicLoadN(addr state.stage, ATOMIC_SEQ_CST))
