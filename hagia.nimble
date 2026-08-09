version = "0.1.0"
author = "Mason Austin Green"
description = "Standalone spatial-policy client for the Sophia display server"
license = "BSD-3-Clause"
srcDir = "src"
bin = @["hagia", "hagia_policy_proof"]

requires "nim >= 2.2.4"
requires "chronicles >= 0.10.3"
requires "nimcrypto >= 0.6.2"
requires "nimkdl >= 2.1.0"

task test, "Run the independent Sophia policy conformance suite":
  exec "sh tools/check_sophia_policy.sh"

task verify, "Check formatting and run the independent conformance suite":
  exec "nph --check src tests hagia.nimble"
  exec "sh tools/check_sophia_policy.sh"
