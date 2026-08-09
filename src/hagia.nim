import std/[os, strutils]

import config/[migration, profile]
import observability
import sophia/policy_client

proc option(arguments: openArray[string], name: string): string =
  let prefix = "--" & name & "="
  for argument in arguments:
    if argument.startsWith(prefix):
      return argument[prefix.len .. ^1]

proc run(arguments: seq[string]) =
  if arguments.len >= 2 and arguments[0] == "config":
    let configPath = arguments.option("config")
    case arguments[1]
    of "check":
      let profile = loadDesktopProfile(configPath)
      stdout.writeLine(
        "ok generation=" & $profile.generation & " digest=" & profile.digest
      )
    of "print-effective":
      stdout.write(loadDesktopProfile(configPath).effectiveProfile())
    of "migrate-triad":
      let inputPath = arguments.option("input")
      let outputDirectory = arguments.option("output-dir")
      let report = writeMigration(inputPath, outputDirectory)
      stdout.writeLine(
        "migrated settings=" & $report.items.len & " output=" & outputDirectory
      )
    else:
      raise newException(
        ValueError,
        "usage: hagia config check|print-effective [--config=PATH]\n" &
          "       hagia config migrate-triad --input=PATH --output-dir=ABSOLUTE_PATH",
      )
    return

  var socketPath = getEnv("SOPHIA_WM_SOCKET")
  let explicitConfig = arguments.option("config")
  for argument in arguments:
    if argument.startsWith("--socket="):
      socketPath = argument[9 .. ^1]
    elif not argument.startsWith("--config="):
      raise newException(ValueError, "usage: hagia [--socket=PATH] [--config=PATH]")
  let candidatePath = getEnv("HAGIA_POLICY_CANDIDATE")
  if candidatePath.len > 0 and explicitConfig.len > 0:
    raise newException(
      ValueError, "hagia: --config cannot replace Sophia's staged policy candidate"
    )
  # Installed startup receives only Sophia's immutable, already partitioned
  # policy candidate. Standalone development retains the compiled/profile path.
  let candidate =
    if candidatePath.len > 0:
      loadAuthorityCandidate(candidatePath, ProfileAuthority.policy)
    else:
      loadDesktopProfile(explicitConfig).candidates[ProfileAuthority.policy]
  operationalLog(OperationalLevel.info, "configuration", "validated")
  recordEvidence(
    EvidenceEvent(
      kind: EvidenceKind.configuration,
      generation: candidate.generation,
      status: "validated",
      digest: candidate.digest,
    )
  )
  if socketPath.len == 0:
    raise newException(ValueError, "hagia: SOPHIA_WM_SOCKET or --socket is required")
  runPolicySession(socketPath, candidate)

try:
  run(commandLineParams())
except CatchableError as error:
  stderr.writeLine("hagia: " & error.msg)
  quit(1)
