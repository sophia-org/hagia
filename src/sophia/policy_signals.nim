import std/posix

## Process signals a developer can send a running Hagia.
##
## Hagia deliberately does not listen on a control socket: it is the
## least-authority component of the desktop, and `docs/capability-map.md`
## excludes a general command surface. A signal needs no endpoint, no framing,
## and no protocol version, so it adds nothing an attacker could reach.
##
## A handler may only set a flag. The session loop acts on it at a point where
## the model is durable, never inside a frame.

var reloadFlag: cint = 0

proc onReload(signalNumber: cint) {.noconv.} =
  reloadFlag = 1

proc installPolicySignals*() =
  ## SIGHUP asks for a supervised reload. Sophia restarts the process and the
  ## next generation loads the checkpoint, so the request is only honoured once
  ## the checkpoint for this cycle has been written.
  signal(SIGHUP, onReload)

proc takeReloadRequest*(): bool =
  ## Read and clear. A refused request must not linger and fire later against
  ## an unrelated cycle.
  result = reloadFlag != 0
  if result:
    reloadFlag = 0
