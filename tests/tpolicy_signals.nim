import std/[os, posix, strutils, unittest]
import sophia/policy_signals

## The stop handler in this process: its wake pipe's descriptor flags and a
## real SIGTERM. The binary-level stop paths are in `tgraceful_stop`.

proc pipeDescriptors(): seq[cint] =
  ## Both ends of the wake pipe, found by the inode the read end names.
  let name = expandSymlink("/proc/self/fd" / $stopWakeFd())
  for kind, path in walkDir("/proc/self/fd"):
    try:
      if expandSymlink(path) == name:
        result.add(cint(parseInt(path.extractFilename())))
    except OSError:
      discard

suite "stop signal installation":
  test "the wake pipe is nonblocking and close-on-exec at both ends":
    check stopWakeFd() == -1
    installStopSignals()
    let descriptors = pipeDescriptors()
    check descriptors.len == 2
    for descriptor in descriptors:
      check (fcntl(descriptor, F_GETFL) and O_NONBLOCK) != 0
      check (fcntl(descriptor, F_GETFD) and FD_CLOEXEC) != 0

  test "installing again keeps the one pipe":
    let before = stopWakeFd()
    installStopSignals()
    check stopWakeFd() == before
    check pipeDescriptors().len == 2

  test "SIGTERM records a stop and wakes the pipe":
    requireRunning()
    check posix.raise(SIGTERM) == 0
    var ready = TPollfd(fd: stopWakeFd(), events: POLLIN)
    check posix.poll(addr ready, Tnfds(1), 0) == 1
    expect StopRequestedError:
      requireRunning()
    try:
      requireRunning()
    except StopRequestedError as stop:
      check stop.msg == "stop requested by SIGTERM"
