import std/[os, strutils]

import sophia/policy_client

proc socketPath(): string =
  result = getEnv("SOPHIA_WM_SOCKET")
  for argument in commandLineParams():
    if argument.startsWith("--socket="):
      result = argument[9 .. ^1]
    else:
      quit("usage: hagia [--socket=PATH]", 2)
  if result.len == 0:
    quit("hagia: SOPHIA_WM_SOCKET or --socket is required", 2)

try:
  runPolicySession(socketPath())
except CatchableError as error:
  stderr.writeLine("hagia: " & error.msg)
  quit(1)
