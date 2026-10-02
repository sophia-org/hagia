import std/[os, osproc, strutils, tempfiles, unittest]

import types/[actions, session]
import sophia/policy_trace
import support/recent_windows_requests

## `hagia replay` restores each recorded connection's chord context before
## reducing its cycles, including connections appended to an older trace.

let hagiaBinary = getEnv("HAGIA_BINARY")

proc entry(request: ProjectionRequest, followed: bool): string =
  PolicyTraceEntry(
    snapshot: scene(),
    request: request,
    transaction: request.requestId,
    actionLifecycle: followed,
  ).traceLine()

proc replay(lines: openArray[string]): (string, int) =
  let directory = createTempDir("hagia-replay-", "")
  defer:
    removeDir(directory)
  let trace = directory / "trace.jsonl"
  writeFile(trace, lines.join("\n") & "\n")
  execCmdEx(quoteShellCommand([hagiaBinary, "replay", trace]))

proc presentations(output: string): seq[string] =
  for line in output.splitLines():
    if line.startsWith("cycle="):
      result.add(line.split("presentation=")[1])

suite "recent-windows replay through the CLI":
  doAssert hagiaBinary.len > 0 and fileExists(hagiaBinary), "set HAGIA_BINARY"
  let snapshot = scene()

  test "an older connection replays modal and an appended one follows its chord":
    # Connection 7 predates the chord context; connection 8 recorded it.
    let old = entry(snapshot.request(1, PolicyAction.recentWindowNext), false).replace(
        ""","actionLifecycle":false""", ""
      )
    check "actionLifecycle" notin old
    var held = snapshot.lifecycle(4, 1, 0, chord = 3)
    held.connectionEpoch = 8
    var released = snapshot.lifecycle(5, 2, 1, chord = 3)
    released.connectionEpoch = 8
    let (output, status) = replay(
      [
        old,
        entry(snapshot.request(2, PolicyAction.recentWindowCancel), false),
        entry(snapshot.chordAction(3, 3, epoch = 8), true),
        entry(held, true),
        entry(released, true),
      ]
    )
    check status == 0
    check output.presentations() ==
      @["replaceApplications", "none", "none", "overlay", "none"]
    check "replayed cycles=5" in output

  test "a followed chord without its recorded context is refused":
    let line = entry(snapshot.chordAction(1, 1), true)
    check replay([line])[1] == 0
    let (output, status) = replay([line.replace(""","actionLifecycle":true""", "")])
    check status != 0
    check "replayed cycles" notin output
