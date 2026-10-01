import std/[net, os, posix]

const supportDir = currentSourcePath().parentDir
{.passC: "-I" & supportDir.}
{.compile: supportDir / "sdk_admission_peer.c".}

type
  PeerResult* {.
    importc: "struct hagia_sdk_peer_result", header: "sdk_admission_peer.h", bycopy
  .} = object
    required*, optional*: uint64
    offers*, configurations*: cuint
    status*: cint

  PeerTask* = object
    fd*: cint
    ceiling*, selected*: uint64
    profileRequired*: cuint
    api*: cstring ## nil serves the pinned SDK's current `api` bytes.
    listener*: bool
    result*: ptr PeerResult

proc serve(
  fd: cint,
  ceiling, selected: uint64,
  profileRequired: cuint,
  api: cstring,
  result: ptr PeerResult,
) {.
  importc: "hagia_sdk_admission_peer",
  header: "sdk_admission_peer.h",
  cdecl,
  gcsafe,
  raises: []
.}

proc servePeer*(task: PeerTask) {.thread.} =
  var fd = task.fd
  if task.listener:
    var descriptor = TPollfd(fd: fd, events: POLLIN)
    if posix.poll(addr descriptor, Tnfds(1), 2000) <= 0:
      task.result.status = -2
      return
    fd = cint(posix.accept(SocketHandle(fd), nil, nil))
    if fd < 0:
      task.result.status = -3
      return
  serve(fd, task.ceiling, task.selected, task.profileRequired, task.api, task.result)

proc runPeer*(
    ceiling, selected: uint64, body: proc(socket: Socket), profileRequired = false
): PeerResult =
  var handles: array[2, cint]
  doAssert posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, handles) == 0
  let socket =
    newSocket(SocketHandle(handles[0]), net.AF_UNIX, net.SOCK_STREAM, net.IPPROTO_IP)
  var thread: Thread[PeerTask]
  createThread(
    thread,
    servePeer,
    PeerTask(
      fd: handles[1],
      ceiling: ceiling,
      selected: selected,
      profileRequired: cuint(profileRequired),
      result: addr result,
    ),
  )
  try:
    body(socket)
  finally:
    socket.close()
    joinThread(thread)
