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
  # Startup is transactional: reject every participating profile section
  # before opening the graphical-session policy connection.
  let profile = loadDesktopProfile(explicitConfig)
  operationalLog(OperationalLevel.info, "configuration", "validated")
  recordEvidence(
    EvidenceEvent(
      kind: EvidenceKind.configuration,
      generation: profile.generation,
      status: "validated",
      digest: profile.digest,
    )
  )
  if socketPath.len == 0:
    raise newException(ValueError, "hagia: SOPHIA_WM_SOCKET or --socket is required")
  runPolicySession(socketPath, profile.candidates[ProfileAuthority.policy])

try:
  run(commandLineParams())
except CatchableError as error:
  stderr.writeLine("hagia: " & error.msg)
  quit(1)
