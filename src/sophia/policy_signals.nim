import std/[oserrors, posix]

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
  reloadFlag: cint = 0
  dumpFlag: cint = 0
  stopSignal: cint = 0
  # Self-pipe: the read end is polled beside the session socket, so a stop
  # that lands just before a wait still ends that wait at once.
  stopWake: array[2, cint] = [-1'i32, -1]

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
  if stopWake[0] < 0:
    if posix.pipe(stopWake) != 0:
      raiseOSError(osLastError(), "stop wake pipe")
    for descriptor in stopWake:
      discard fcntl(descriptor, F_SETFD, FD_CLOEXEC)
      discard fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) or O_NONBLOCK)
  var action: Sigaction
  action.sa_handler = onStop
  discard sigemptyset(action.sa_mask)
  for number in [SIGTERM, SIGINT]:
    if sigaction(number, action, nil) != 0:
      raiseOSError(osLastError(), "stop signal handler")

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
