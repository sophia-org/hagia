import
  std/[
    monotimes, net, options, os, osproc, posix, streams, strtabs, strutils, tempfiles,
    times, unittest,
  ]
import sophia/policy_checkpoint
import support/sdk_stop_peer

## SIGTERM and SIGINT against the real `hagia` binary, held by a scripted SDK
## endpoint at startup, at an idle wait and inside an unsettled cycle. The
## endpoint is the SDK's test-only engine, not Session or Engine; no policy
## acceptance is claimed.

const
  # Well inside the 4 s outcome and 12 s bootstrap deadlines, so a stop is
  # never mistaken for a deadline failure.
  stopBoundMsec = 3000
  stageBoundMsec = 15000

let hagiaBinary = getEnv("HAGIA_BINARY")

type Run = object
  directory, socket, checkpoint, evidence: string
  listener: Socket
  state: StopPeerState
  thread: Thread[StopPeerTask]
  process: Process
  target: Pid

proc elapsedMsec(start: MonoTime): int64 =
  (getMonoTime() - start).inMilliseconds

proc start(run: var Run, script: StopScript, namespaceInit = false) =
  run.directory = createTempDir("hagia-stop-", "")
  run.socket = run.directory / "wm.sock"
  run.checkpoint = run.directory / "checkpoint"
  run.evidence = run.directory / "evidence.ndjson"
  run.listener = newSocket(Domain.AF_UNIX, SockType.SOCK_STREAM, Protocol.IPPROTO_IP)
  run.listener.bindUnix(run.socket)
  run.listener.listen()
  run.state.script = cuint(ord(script))
  createThread(
    run.thread,
    serveStopPeer,
    StopPeerTask(listener: cint(run.listener.getFd()), state: addr run.state),
  )
  let environment = newStringTable(
    {
      "HOME": run.directory,
      "XDG_CONFIG_HOME": run.directory / "config",
      "SOPHIA_WM_9P_SOCKET": run.socket,
      "SOPHIA_WM_POLICY_CHECKPOINT": run.checkpoint,
      "HAGIA_EVIDENCE_NDJSON": run.evidence,
      "HAGIA_LOG_LEVEL": "info",
    },
    modeCaseSensitive,
  )
  if namespaceInit:
    # A PID namespace init ignores every signal it installed no handler for.
    run.process = startProcess(
      "/usr/bin/unshare",
      args =
        ["--user", "--map-root-user", "--pid", "--fork", "--kill-child", hagiaBinary],
      env = environment,
      options = {poStdErrToStdOut},
    )
    let children =
      "/proc" / $run.process.processID / "task" / $run.process.processID / "children"
    let start = getMonoTime()
    while run.target == 0 and start.elapsedMsec < stageBoundMsec:
      let listed = readFile(children).strip()
      if listed.len > 0:
        run.target = Pid(parseInt(listed.splitWhitespace()[0]))
      else:
        sleep(5)
    doAssert run.target != 0, "unshare never forked Hagia"
    var nsPid = ""
    for line in readFile("/proc" / $run.target / "status").splitLines():
      if line.startsWith("NSpid:"):
        nsPid = line.splitWhitespace()[^1]
    doAssert nsPid == "1", "Hagia is not its namespace's init: " & nsPid
  else:
    run.process =
      startProcess(hagiaBinary, env = environment, options = {poStdErrToStdOut})
    run.target = Pid(run.process.processID)

proc reach(run: var Run, stage: StopStage) =
  let start = getMonoTime()
  while (addr run.state).stage() != stage:
    if not run.process.running():
      doAssert false,
        "Hagia exited before " & $stage & ":\n" & run.process.outputStream().readAll()
    doAssert start.elapsedMsec < stageBoundMsec, "Hagia never reached " & $stage
    sleep(5)

proc stop(run: var Run, number: cint): tuple[code: int, msec: int64, output: string] =
  let start = getMonoTime()
  doAssert posix.kill(run.target, number) == 0
  while run.process.running() and start.elapsedMsec < stopBoundMsec:
    sleep(2)
  result.msec = start.elapsedMsec
  if run.process.running():
    run.process.kill()
  result.code = run.process.waitForExit()
  result.output = run.process.outputStream().readAll()
  run.process.close()
  run.process = nil
  joinThread(run.thread)
  echo "stop latency msec=", result.msec, " code=", result.code

proc finish(run: var Run) =
  # Also reached after a failed stage, so nothing outlives the test.
  if run.process != nil:
    if run.process.running():
      run.process.kill()
    discard run.process.waitForExit()
    run.process.close()
  if run.thread.running():
    joinThread(run.thread)
  if run.listener != nil:
    run.listener.close()
  removeDir(run.directory)

template requireGracefulStop(
    run: Run, stopped: tuple[code: int, msec: int64, output: string], name: string
) =
  # A template, so every check fails the enclosing test rather than a helper.
  check stopped.msec < stopBoundMsec
  check stopped.code == 0
  check ("stop requested by " & name) in stopped.output
  check "hagia:" notin stopped.output
  # The peer saw an orderly end of stream, not a timeout.
  check run.state.closed == 1
  check run.state.status == 0
  check "\"event\":\"stop\"" in readFile(run.evidence)

suite "graceful stop of the real binary":
  doAssert hagiaBinary.len > 0 and fileExists(hagiaBinary), "set HAGIA_BINARY"

  test "SIGTERM during bootstrap closes before negotiation":
    var run: Run
    run.start(StopScript.mute)
    try:
      run.reach(StopStage.connected)
      let stopped = run.stop(SIGTERM)
      run.requireGracefulStop(stopped, "SIGTERM")
      check run.state.configurations == 0
      check not fileExists(run.checkpoint)
    finally:
      run.finish()

  for (name, number) in [("SIGTERM", SIGTERM), ("SIGINT", SIGINT)]:
    test name & " at the idle wait closes the session":
      var run: Run
      run.start(StopScript.idle)
      try:
        run.reach(StopStage.idleRead)
        let stopped = run.stop(number)
        run.requireGracefulStop(stopped, name)
        check run.state.configurations == 1
        check run.state.projections == 0
      finally:
        run.finish()

  test "SIGTERM inside an unsettled cycle discards it without replay":
    var run: Run
    run.start(StopScript.ambiguous)
    try:
      run.reach(StopStage.unsettled)
      let stopped = run.stop(SIGTERM)
      run.requireGracefulStop(stopped, "SIGTERM")
      # Custody went to the endpoint and no outcome came back: the candidate
      # is neither retried nor promoted into a checkpoint.
      check run.state.projections == 1
      check not fileExists(run.checkpoint)
    finally:
      run.finish()

  test "SIGTERM after a commit keeps that cycle's checkpoint":
    var run: Run
    run.start(StopScript.commitThen)
    try:
      run.reach(StopStage.unsettled)
      let committed = readFile(run.checkpoint)
      let stopped = run.stop(SIGTERM)
      run.requireGracefulStop(stopped, "SIGTERM")
      check run.state.projections == 2
      check readFile(run.checkpoint) == committed
      check run.checkpoint.loadPolicyCheckpoint().isSome
      var names: seq[string]
      for kind, path in walkDir(run.directory):
        names.add(path.extractFilename())
      # No partial replacement is left beside the durable checkpoint.
      for name in names:
        check name in ["wm.sock", "checkpoint", "evidence.ndjson"]
    finally:
      run.finish()

  test "SIGTERM reaches Hagia as a PID namespace init":
    var run: Run
    run.start(StopScript.idle, namespaceInit = true)
    try:
      run.reach(StopStage.idleRead)
      let stopped = run.stop(SIGTERM)
      run.requireGracefulStop(stopped, "SIGTERM")
    finally:
      run.finish()
