import std/strutils
import ../types/policy_endpoint

proc selectPolicyEndpoint*(
    arguments: openArray[string], currentIpcEnvironment, fileEnvironment: string
): PolicyEndpoint =
  ## A command-line path overrides only its own wire's environment. Supplying
  ## both wires is an error even when one explicit path is empty; it never
  ## silently opts out of Session's choice. Missing-path refusal stays at the
  ## entrypoint after profile validation, preserving the legacy error order.
  var currentPath = currentIpcEnvironment
  var filePath = fileEnvironment
  var currentExplicit = false
  var fileExplicit = false
  for argument in arguments:
    if argument.startsWith("--socket="):
      currentExplicit = true
      currentPath = argument[9 .. ^1]
    elif argument.startsWith("--9p-socket="):
      fileExplicit = true
      filePath = argument[12 .. ^1]
    elif not argument.startsWith("--config="):
      raise
        newException(ValueError, "unknown option " & argument & "; try hagia --help")
  let currentSelected = currentExplicit or currentIpcEnvironment.len > 0
  let fileSelected = fileExplicit or fileEnvironment.len > 0
  if currentSelected and fileSelected:
    raise newException(
      ValueError, "hagia: current IPC and 9P WM sockets are mutually exclusive"
    )
  if fileSelected:
    PolicyEndpoint(kind: PolicyEndpointKind.wmFiles, path: filePath)
  else:
    PolicyEndpoint(kind: PolicyEndpointKind.currentIpc, path: currentPath)

proc requirePolicyEndpoint*(endpoint: PolicyEndpoint) =
  if endpoint.path.len == 0:
    case endpoint.kind
    of PolicyEndpointKind.currentIpc:
      raise newException(ValueError, "hagia: SOPHIA_WM_SOCKET or --socket is required")
    of PolicyEndpointKind.wmFiles:
      raise newException(
        ValueError, "hagia: SOPHIA_WM_9P_SOCKET or --9p-socket is required"
      )
