import std/os

import sophia/policy_client

if paramCount() != 1:
  quit("usage: hagia-policy-proof SOCKET", 2)

try:
  runOnePolicyCycle(paramStr(1))
except CatchableError as error:
  stderr.writeLine("hagia-policy-proof: " & error.msg)
  quit(1)
