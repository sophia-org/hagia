version = "0.1.0"
author = "Mason Austin Green"
description = "Standalone spatial-policy client for the Sophia display server"
license = "BSD-3-Clause"
srcDir = "src"
bin = @["hagia"]

requires "nim >= 2.2.4"
requires "chronicles >= 0.10.3"
requires "nimcrypto >= 0.6.2"
requires "nimkdl >= 2.1.0"

task layout, "Check the data-oriented layout of the source tree":
  exec "sh tools/check_data_oriented_layout.sh"

task pairing, "Run optional Hagia pairing against a pinned isolated Sophia overlay":
  exec "sh tools/check_sophia_pairing.sh"

task exportProof, "Exercise the SDK PolicyWire peer against a supplied Sophia export":
  exec "sh tools/check_sdk_export.sh"

task liveReload, "Rebuild and hand the running Hagia over to the new binary":
  exec "sh tools/live_reload.sh"

task test, "Run SDK, independent file corpus and policy tests":
  exec "sh tools/check_data_oriented_layout.sh"
  exec "sh tools/check_sophia_policy.sh"

task verify, "Check formatting and run SDK and policy tests":
  exec "nph --check src tests hagia.nimble"
  exec "sh tools/check_data_oriented_layout.sh"
  exec "sh tools/check_sophia_policy.sh"
  exec "sh tools/check_foundation_models.sh"
  exec "sh tools/check_profile_lifecycle_model.sh"
