import std/[oserrors, posix]
import posix/linux

## Process signals a developer or supervisor can send a running Hagia.
##
## Hagia deliberately does not listen on a control socket: it is the
## least-authority component of the desktop, and `docs/capability-map.md`
## excludes a general command surface. A signal needs no endpoint, no framing,
## and no protocol version, so it adds nothing an attacker could reach.
##
## A handler may only record a request. The session loop acts on it at a point
## where the model is durable, never inside a frame.

type StopRequestedError* = object of CatchableError
  ## Raised by ordinary code, never by a handler, once SIGTERM or SIGINT asked
  ## the process to stop. It unwinds through the normal close paths.

var
  # Handler-shared: volatile int, the storage sig_atomic_t names on Linux.
  reloadFlag {.volatile.}: cint = 0
  dumpFlag {.volatile.}: cint = 0
  stopSignal {.volatile.}: cint = 0
  # Self-pipe: the read end is polled beside the session socket, so a stop
  # that lands just before a wait still ends that wait at once.
  stopWake: array[2, cint] = [-1'i32, -1]

# Handlers run asynchronously: no stack-trace frames, line tracking or checks,
# only stores and one write(2), which is async-signal-safe.
{.push stackTrace: off, lineTrace: off, checks: off.}

proc onReload(signalNumber: cint) {.noconv.} =
  reloadFlag = 1

proc onDump(signalNumber: cint) {.noconv.} =
  dumpFlag = 1

proc onStop(signalNumber: cint) {.noconv.} =
  stopSignal = signalNumber
  if stopWake[1] >= 0:
    let saved = errno
    var token = 1'u8
    discard posix.write(stopWake[1], addr token, 1)
    errno = saved

{.pop.}

proc installPolicySignals*() =
  ## SIGHUP asks for a supervised reload: Sophia restarts the process and the
  ## next generation loads the checkpoint, so the request is only honoured once
  ## the checkpoint for this cycle has been written.
  ##
  ## SIGUSR1 asks for a state dump, which is read-only and changes nothing.
  signal(SIGHUP, onReload)
  signal(SIGUSR1, onDump)

proc installStopSignals*() =
  ## SIGTERM and SIGINT ask for a stop. The next wait closes the session and
  ## returns: a candidate in flight is discarded and never replayed, and the
  ## checkpoint keeps the last committed cycle, exactly as a disconnect would
  ## leave it. Installed before connecting, because as a namespace init
  ## without a handler Hagia would ignore both signals.
  ##
  ## Either both handlers and the wake pipe are in place, or none is: a
  ## failure restores the previous dispositions and closes the pipe.
  if stopWake[0] >= 0:
    return
  # The handler writes without blocking, and the pipe never reaches a child.
  var wake: array[2, cint]
  if pipe2(wake, O_NONBLOCK or O_CLOEXEC) != 0:
    raiseOSError(osLastError(), "stop wake pipe")
  stopWake = wake
  const numbers = [SIGTERM, SIGINT]
  var action: Sigaction
  var previous: array[numbers.len, Sigaction]
  action.sa_handler = onStop
  discard sigemptyset(action.sa_mask)
  for index, number in numbers:
    if sigaction(number, action, previous[index]) != 0:
      let error = osLastError()
      for restored in 0 ..< index:
        discard sigaction(numbers[restored], previous[restored], nil)
      stopWake = [-1'i32, -1]
      discard posix.close(wake[0])
      discard posix.close(wake[1])
      raiseOSError(error, "stop signal handler")

proc stopWakeFd*(): cint =
  ## Readable once a stop was requested; -1 before `installStopSignals`, which
  ## poll ignores.
  stopWake[0]

proc requireRunning*() =
  ## Called at waits and before new custody, so a stop never begins another
  ## submission or cycle.
  if stopSignal != 0:
    raise newException(
      StopRequestedError,
      "stop requested by " & (if stopSignal == SIGINT: "SIGINT" else: "SIGTERM"),
    )

proc takeReloadRequest*(): bool =
  ## Read and clear. A refused request must not linger and fire later against
  ## an unrelated cycle.
  result = reloadFlag != 0
  if result:
    reloadFlag = 0

proc takeDumpRequest*(): bool =
  ## Read and clear, so one signal produces one dump.
  result = dumpFlag != 0
  if result:
    dumpFlag = 0
