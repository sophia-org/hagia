import std/[options, os, strutils]

import config/[migration, profile]
import types/config_values
import types/observability
import observability
import types/session
import
  sophia/
    [policy_adapter, policy_checkpoint, policy_client, policy_session, policy_trace]

proc option(arguments: openArray[string], name: string): string =
  let prefix = "--" & name & "="
  for argument in arguments:
    if argument.startsWith(prefix):
      return argument[prefix.len .. ^1]

const usage = """hagia — reference window manager for the Sophia display server

usage:
  hagia [--socket=PATH] [--config=PATH]   run the policy session
  hagia config check [--config=PATH]      validate a desktop profile
  hagia config init [--config=PATH]       seed the default profile, never
                                          overwriting an existing one
  hagia config print-effective [--config=PATH]
                                          print the fully expanded profile
  hagia config migrate-triad --input=PATH --output-dir=ABSOLUTE_PATH
                                          translate a Triad configuration
  hagia dump-checkpoint PATH              print a checkpoint or state dump
  hagia replay TRACE [--checkpoint=PATH]  re-run a recorded session offline
  hagia --help                            this text

signals:
  SIGHUP   checkpoint and hand over to a rebuilt binary
  SIGUSR1  write the committed model to $HAGIA_POLICY_DUMP

common environment:
  SOPHIA_WM_SOCKET          session-owned policy socket (Sophia sets this)
  HAGIA_POLICY_CHECKPOINT   private checkpoint path (Sophia sets this)
  HAGIA_LOG_LEVEL           debug | info | warn | error, default info
  HAGIA_EVIDENCE_NDJSON     absolute path for the evidence stream
  HAGIA_POLICY_DUMP         where SIGUSR1 writes state
  HAGIA_POLICY_TRACE        record a replayable session trace

docs/environment.md documents every variable, including fault injection."""

proc run(arguments: seq[string]) =
  if arguments.len >= 1 and arguments[0] in ["--help", "-h", "help"]:
    stdout.write(usage & "\n")
    return

  if arguments.len >= 2 and arguments[0] == "config":
    let configPath = arguments.option("config")
    case arguments[1]
    of "check":
      let profile = loadDesktopProfile(configPath)
      discard initPolicyAdapter(profile.candidates[ProfileAuthority.policy])
      stdout.writeLine(
        "ok generation=" & $profile.generation & " digest=" & profile.digest
      )
    of "init":
      # Seed-if-absent, never overwrite. Validation is the load-back: a write
      # that cannot be loaded must not report success.
      let (path, installed) = initDesktopProfile(configPath)
      if installed:
        let profile = loadDesktopProfile(path)
        stdout.writeLine(
          "installed " & path & " generation=" & $profile.generation & " digest=" &
            profile.digest
        )
      else:
        stdout.writeLine("left existing " & path)
    of "print-effective":
      stdout.write(loadDesktopProfile(configPath).effectiveProfile())
    of "migrate-triad":
      let inputPath = arguments.option("input")
      let outputDirectory = arguments.option("output-dir")
      let report = writeMigration(inputPath, outputDirectory)
      stdout.writeLine(
        "migrated settings=" & $report.items.len & " physical-bindings=" &
          $report.physicalBindingCount() & " output=" & outputDirectory
      )
    else:
      raise newException(
        ValueError,
        "usage: hagia config check|print-effective|init [--config=PATH]\n" &
          "       hagia config migrate-triad --input=PATH --output-dir=ABSOLUTE_PATH",
      )
    return

  if arguments.len >= 1 and arguments[0] == "dump-checkpoint":
    # The checkpoint is a private, stable-ID-ordered DTO, not a portable
    # configuration format. Printing it is the only way to see what a running
    # or restored Hagia actually believes without writing Nim against the
    # loader.
    if arguments.len != 2:
      raise newException(ValueError, "usage: hagia dump-checkpoint PATH")
    let dumped = loadPolicyCheckpoint(arguments[1])
    if dumped.isNone:
      raise newException(ValueError, "no checkpoint at " & arguments[1])
    stdout.writeLine(dumped.get().checkpointPayload().dumpCheckpointJson())
    return

  if arguments.len >= 1 and arguments[0] == "replay":
    # Offline. The reducer is pure, so a recorded snapshot and request replay to
    # the same projection without a compositor, a session, or hardware. This is
    # how a live bug becomes something reproducible.
    if arguments.len < 2:
      raise newException(ValueError, "usage: hagia replay TRACE [--checkpoint=PATH]")
    let checkpoint = arguments.option("checkpoint")
    var session =
      if checkpoint.len > 0:
        let restored = loadPolicyCheckpoint(checkpoint)
        if restored.isNone:
          raise newException(ValueError, "no checkpoint at " & checkpoint)
        initPolicySession(restored.get())
      else:
        initPolicySession()
    var cycle = 0
    for entry in readTrace(arguments[1]):
      inc cycle
      let projection = session.prepare(entry.snapshot, entry.request, entry.transaction)
      stdout.writeLine(
        "cycle=" & $cycle & " request=" & $entry.request.requestId & " outputs=" &
          $projection.outputs.len & " active=" & $projection.activeOutput
      )
      session.settle(
        ProjectionOutcome(
          kind: ProjectionOutcomeKind.committed,
          connectionEpoch: entry.request.connectionEpoch,
          requestId: entry.request.requestId,
          transaction: entry.transaction,
          sceneGeneration: entry.snapshot.generation,
        )
      )
    stdout.writeLine("replayed cycles=" & $cycle)
    return

  var socketPath = getEnv("SOPHIA_WM_SOCKET")
  let explicitConfig = arguments.option("config")
  for argument in arguments:
    if argument.startsWith("--socket="):
      socketPath = argument[9 .. ^1]
    elif not argument.startsWith("--config="):
      raise
        newException(ValueError, "unknown option " & argument & "; try hagia --help")
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
      event: "desktop_profile",
      generation: candidate.generation,
      status: "validated",
      digest: candidate.digest,
    )
  )
  if socketPath.len == 0:
    raise newException(ValueError, "hagia: SOPHIA_WM_SOCKET or --socket is required")
  case getEnv("HAGIA_POLICY_PROFILE_ACTIVATION")
  of "":
    runPolicySession(socketPath, candidate)
  of "required":
    if candidatePath.len == 0:
      raise newException(
        ValueError,
        "hagia: profile activation requires Sophia's staged policy candidate",
      )
    runProfileActivatedPolicySession(socketPath, candidate)
  else:
    raise newException(
      ValueError, "hagia: HAGIA_POLICY_PROFILE_ACTIVATION must be empty or required"
    )

try:
  run(commandLineParams())
except CatchableError as error:
  stderr.writeLine("hagia: " & error.msg)
  quit(1)
