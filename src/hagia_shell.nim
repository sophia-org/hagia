import std/[net, os]

import sophia/shell_v1

type ShellSocketClosedError = object of CatchableError

proc fail(message: string) {.noreturn.} =
  raise newException(ValueError, message)

proc toBytes(data: string): seq[byte] =
  result = newSeq[byte](data.len)
  for index, value in data:
    result[index] = byte(value)

proc toBinaryString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc receiveExact(socket: Socket, length: int): seq[byte] =
  while result.len < length:
    let part = socket.recv(length - result.len)
    if part.len == 0:
      raise newException(ShellSocketClosedError, "shell socket closed during a frame")
    result.add(part.toBytes())

proc receiveFrame(socket: Socket): ShellFrame =
  let header = socket.receiveExact(shellFrameHeaderLen)
  let payloadLength = int(header.u32At(16))
  if payloadLength > shellMaxPayloadLen:
    fail("shell payload is excessive")
  var bytes = header
  bytes.add(socket.receiveExact(payloadLength))
  bytes.decodeShellFrame()

proc sendFrame(socket: Socket, frame: ShellFrame) =
  socket.send(frame.encodeShellFrame().toBinaryString())

proc connect(path: string): Socket =
  for _ in 0 ..< 200:
    result = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    try:
      result.connectUnix(path)
      return
    except OSError:
      result.close()
      sleep(10)
  fail("Sophia shell socket did not become ready")

proc runProof(socketPath: string) =
  let socket = socketPath.connect()
  socket.sendFrame(clientHelloFrame())
  let connectionEpoch = socket.receiveFrame().validateWelcome()
  var model = ShellModel(connectionEpoch: connectionEpoch)

  let firstFrame = socket.receiveFrame()
  let first = firstFrame.decodeSnapshot()
  model.reconcile(first)
  socket.sendFrame(model.candidate(1, true).candidateFrame(firstFrame.transaction))
  let prepared = socket.receiveFrame().decodeOutcome()
  if prepared.kind != ShellCandidateOutcomeKind.prepared:
    fail("Sophia did not prepare the shell candidate")
  let presented = socket.receiveFrame().decodeOutcome()
  model.rememberPresented(presented)

  let activationFrame = socket.receiveFrame()
  let activation = activationFrame.decodeActivation()
  let disposition = model.accept(activation)
  socket.sendFrame(
    activationAckFrame(
      model.connectionEpoch, activation.activation, activationFrame.transaction,
      disposition,
    )
  )
  if disposition != ShellActivationDisposition.consumed:
    fail("Sophia delivered a stale shell activation")

  let withdrawalFrame = socket.receiveFrame()
  let withdrawalSnapshot = withdrawalFrame.decodeSnapshot()
  model.reconcile(withdrawalSnapshot)
  socket.sendFrame(
    model.candidate(2, false).candidateFrame(withdrawalFrame.transaction)
  )
  let withdrawalPrepared = socket.receiveFrame().decodeOutcome()
  if withdrawalPrepared.kind != ShellCandidateOutcomeKind.prepared:
    fail("Sophia did not prepare the shell withdrawal")
  let withdrawn = socket.receiveFrame().decodeOutcome()
  if withdrawn.kind != ShellCandidateOutcomeKind.presented:
    fail("Sophia did not present the shell withdrawal")
  stdout.writeLine(
    "hagia_shell_proof schema=1 status=complete descriptors=" & $first.descriptors.len &
      " activations=1 withdrawn=true"
  )

proc runServer(socketPath: string) =
  let socket = socketPath.connect()
  defer:
    socket.close()
  socket.sendFrame(clientHelloFrame())
  let connectionEpoch = socket.receiveFrame().validateWelcome()
  var model = ShellModel(connectionEpoch: connectionEpoch)
  var candidateGeneration = 1'u64
  var showNext = true
  stdout.writeLine(
    "hagia_shell schema=1 status=ready connection_epoch=" & $connectionEpoch
  )
  while true:
    let snapshotFrame = socket.receiveFrame()
    let snapshot = snapshotFrame.decodeSnapshot()
    model.reconcile(snapshot)
    let candidate = model.candidate(candidateGeneration, showNext)
    socket.sendFrame(candidate.candidateFrame(snapshotFrame.transaction))
    let prepared = socket.receiveFrame().decodeOutcome()
    if prepared.connectionEpoch != connectionEpoch or
        prepared.candidateGeneration != candidateGeneration or
        prepared.kind != ShellCandidateOutcomeKind.prepared:
      fail("Sophia did not prepare the live shell candidate")
    let presented = socket.receiveFrame().decodeOutcome()
    if presented.candidateGeneration != candidateGeneration:
      fail("Sophia presented another live shell candidate")
    if presented.kind in
        {ShellCandidateOutcomeKind.rejected, ShellCandidateOutcomeKind.superseded}:
      if candidateGeneration == high(uint64):
        fail("live shell candidate generation exhausted")
      inc candidateGeneration
      continue
    model.rememberPresented(presented)
    if candidate.visible:
      let activationFrame = socket.receiveFrame()
      let activation = activationFrame.decodeActivation()
      let disposition = model.accept(activation)
      socket.sendFrame(
        activationAckFrame(
          connectionEpoch, activation.activation, activationFrame.transaction,
          disposition,
        )
      )
      if disposition != ShellActivationDisposition.consumed:
        fail("Sophia delivered a stale live shell activation")
      showNext = false
    else:
      showNext = true
    if candidateGeneration == high(uint64):
      fail("live shell candidate generation exhausted")
    inc candidateGeneration

proc run(arguments: seq[string]) =
  let socketPath = getEnv("SOPHIA_SHELL_SOCKET")
  if socketPath.len == 0:
    fail("hagia-shell: SOPHIA_SHELL_SOCKET is required")
  if arguments == @["--proof"]:
    socketPath.runProof()
  elif arguments == @["--serve"]:
    socketPath.runServer()
  else:
    fail("hagia-shell: expected --proof or --serve")

try:
  run(commandLineParams())
except ShellSocketClosedError as error:
  if commandLineParams() == @["--serve"]:
    quit(0)
  stderr.writeLine("hagia-shell: " & error.msg)
  quit(1)
except CatchableError as error:
  stderr.writeLine("hagia-shell: " & error.msg)
  quit(1)
