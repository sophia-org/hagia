import std/[os, strutils]

import sophia/policy_client

if paramCount() < 1 or paramCount() > 2:
  quit("usage: hagia-policy-proof SOCKET [CYCLES]", 2)

try:
  let cycles =
    if paramCount() == 2:
      parseInt(paramStr(2))
    else:
      1
  runPolicyCycles(paramStr(1), cycles)
except CatchableError as error:
  stderr.writeLine("hagia-policy-proof: " & error.msg)
  quit(1)
