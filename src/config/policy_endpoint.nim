import std/strutils
import ../types/policy_endpoint

proc selectPolicyEndpoint*(
    arguments: openArray[string], fileEnvironment: string
): PolicyEndpoint =
  ## An empty explicit override stays empty; a retired --socket cannot
  ## select another transport.
  result.path = fileEnvironment
  var explicit = false
  for argument in arguments:
    if argument.startsWith("--9p-socket="):
      if explicit:
        raise newException(ValueError, "duplicate --9p-socket")
      explicit = true
      result.path = argument[12 .. ^1]
    elif not argument.startsWith("--config="):
      raise
        newException(ValueError, "unknown option " & argument & "; try hagia --help")

proc requirePolicyEndpoint*(endpoint: PolicyEndpoint) =
  if endpoint.path.len == 0:
    raise
      newException(ValueError, "hagia: SOPHIA_WM_9P_SOCKET or --9p-socket is required")
