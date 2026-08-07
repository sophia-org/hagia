version = "0.1.0"
author = "Mason Austin Green"
description = "Standalone spatial-policy client for the Sophia display server"
license = "BSD-3-Clause"
srcDir = "src"
bin = @["hagia_policy_proof"]

requires "nim >= 2.2.4"

task test, "Run the independent Sophia policy conformance suite":
  exec "sh tools/check_sophia_policy.sh"
