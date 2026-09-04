import std/[json, jsonutils, streams]

import ../types/session

## Recording and replay of a policy session.
##
## Hagia's reducer is pure: no clock, no randomness, explicit ordering for every
## entity kind. A cycle is therefore fully described by the snapshot it received
## and the request it answered, so a recorded pair replays to the same
## projection on any machine, with no compositor, no session, and no hardware.
##
## This is what makes an intermittent live bug into a fixture.

type PolicyTraceError* = object of CatchableError

proc traceLine*(entry: PolicyTraceEntry): string =
  $(
    %*{
      "snapshot": entry.snapshot.toJson(),
      "request": entry.request.toJson(),
      "transaction": entry.transaction,
    }
  )

proc parseTraceLine*(line: string): PolicyTraceEntry =
  let node =
    try:
      parseJson(line)
    except CatchableError as error:
      raise newException(PolicyTraceError, "trace line is not JSON: " & error.msg)
  for key in ["snapshot", "request", "transaction"]:
    if not node.hasKey(key):
      raise newException(PolicyTraceError, "trace line lacks " & key)
  result.snapshot.fromJson(node["snapshot"])
  result.request.fromJson(node["request"])
  result.transaction = uint64(node["transaction"].getBiggestInt())

proc appendTrace*(path: string, entry: PolicyTraceEntry) =
  ## Append-only. A trace that rewrites earlier cycles could not be replayed
  ## against the checkpoint it started from.
  var stream = openFileStream(path, fmAppend)
  defer:
    stream.close()
  stream.writeLine(entry.traceLine())

iterator readTrace*(path: string): PolicyTraceEntry =
  var stream = openFileStream(path, fmRead)
  defer:
    stream.close()
  var line: string
  while stream.readLine(line):
    if line.len > 0:
      yield line.parseTraceLine()
