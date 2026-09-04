import std/[net, os, strutils]

import ../types/observability
import ../observability

## Socket primitives for the policy connection: byte conversion, exact reads
## with a timeout, readiness retry, and the fault injection the conformance
## corpus uses. Nothing here knows what a policy frame means.

type PolicyClientError* = object of CatchableError

var configuredFaultOccurrences* {.threadvar.}: int

proc fail*(message: string) {.noreturn.} =
  raise newException(PolicyClientError, message)

proc injectConfiguredFault*(phase: string) =
  ## Deterministic live-gate hook. It is inert unless both variables are set,
  ## and the marker makes one supervised replacement the maximum effect.
  let selected = getEnv("HAGIA_POLICY_FAULT_AFTER")
  let marker = getEnv("HAGIA_POLICY_FAULT_MARKER")
  if selected != phase or marker.len == 0 or fileExists(marker):
    return
  inc configuredFaultOccurrences
  let occurrence = parseInt(getEnv("HAGIA_POLICY_FAULT_OCCURRENCE", "1"))
  if configuredFaultOccurrences != occurrence:
    return
  let delayMsec = parseInt(getEnv("HAGIA_POLICY_FAULT_DELAY_MSEC", "0"))
  if delayMsec > 0:
    sleep(delayMsec)
  writeFile(marker, phase & "\n")
  operationalLog(OperationalLevel.failure, "fault_injected", phase)
  recordEvidence(EvidenceEvent(kind: EvidenceKind.connection, status: phase))
  quit(70)

proc toBytes*(data: string): seq[byte] =
  result = newSeq[byte](data.len)
  for index, character in data:
    result[index] = byte(character)

proc toBinaryString*(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc receiveExact*(socket: Socket, length: int, timeoutMsec = -1): seq[byte] =
  result = newSeqOfCap[byte](length)
  while result.len < length:
    let part = socket.recv(length - result.len, timeoutMsec)
    if part.len == 0:
      fail("policy socket closed during a frame")
    result.add(part.toBytes())

proc connectWhenReady*(path: string): Socket =
  for _ in 0 ..< 200:
    let socket = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    try:
      socket.connectUnix(path)
      return socket
    except OSError:
      socket.close()
      sleep(10)
  fail("Sophia policy socket did not become ready")
