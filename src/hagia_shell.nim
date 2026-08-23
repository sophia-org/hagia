import std/[net, os]

import sophia/shell_v1

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
      fail("shell socket closed during a frame")
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

proc run(arguments: seq[string]) =
  if arguments != @["--proof"]:
    fail("hagia-shell: only the offline --proof lifecycle is published")
  let socketPath = getEnv("SOPHIA_SHELL_SOCKET")
  if socketPath.len == 0:
    fail("hagia-shell: SOPHIA_SHELL_SOCKET is required")
  socketPath.runProof()

try:
  run(commandLineParams())
except CatchableError as error:
  stderr.writeLine("hagia-shell: " & error.msg)
  quit(1)
