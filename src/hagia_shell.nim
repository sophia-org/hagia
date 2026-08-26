import std/[net, options, os, strutils]

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

## The bar strip is a bounded status zone the shell claims work area for.
## Its thickness comes from the session so the operator, not the shell, decides
## how much of the desktop a panel may take; an unset or zero value means this
## shell reserves nothing and behaves exactly as the switcher-only shell did.
proc barReservation(): Option[ShellReservation] =
  let configured = getEnv("SOPHIA_SHELL_BAR_THICKNESS")
  if configured.len == 0:
    return none(ShellReservation)
  var thickness: int
  try:
    thickness = parseInt(configured)
  except ValueError:
    fail("hagia-shell: SOPHIA_SHELL_BAR_THICKNESS is not a number")
  if thickness <= 0:
    return none(ShellReservation)
  if thickness > int(shellMaxReservationThickness):
    fail("hagia-shell: SOPHIA_SHELL_BAR_THICKNESS exceeds the protocol maximum")
  some(
    ShellReservation(
      edge: ShellReservationEdge.bottom, thicknessPx: uint16(thickness)
    )
  )

## Reserve, withdraw, and reconnect at a fresh epoch.
##
## The withdrawal carries no reservation, which is how the protocol expresses
## releasing a claim: Engine's coordinator commits the absence through the same
## bundle path that committed the claim, so there is no separate release
## message that could be lost on its own.
proc runBarProof(socketPath: string) =
  let socket = socketPath.connect()
  socket.sendFrame(clientHelloFrame())
  let connectionEpoch = socket.receiveFrame().validateWelcome()
  var model = ShellModel(connectionEpoch: connectionEpoch)
  let reservation = barReservation()
  if reservation.isNone:
    fail("hagia-shell: the bar proof requires SOPHIA_SHELL_BAR_THICKNESS")

  let firstFrame = socket.receiveFrame()
  let first = firstFrame.decodeSnapshot()
  model.reconcile(first)
  socket.sendFrame(
    model.candidate(1, true, reservation).candidateFrame(firstFrame.transaction)
  )
  if socket.receiveFrame().decodeOutcome().kind !=
      ShellCandidateOutcomeKind.prepared:
    fail("Sophia did not prepare the reserving bar candidate")
  let presented = socket.receiveFrame().decodeOutcome()
  if presented.kind != ShellCandidateOutcomeKind.presented:
    fail("Sophia did not present the reserving bar candidate")
  model.rememberPresented(presented)

  let withdrawalFrame = socket.receiveFrame()
  model.reconcile(withdrawalFrame.decodeSnapshot())
  socket.sendFrame(model.candidate(2, false).candidateFrame(withdrawalFrame.transaction))
  if socket.receiveFrame().decodeOutcome().kind !=
      ShellCandidateOutcomeKind.prepared:
    fail("Sophia did not prepare the bar withdrawal")
  if socket.receiveFrame().decodeOutcome().kind !=
      ShellCandidateOutcomeKind.presented:
    fail("Sophia did not present the bar withdrawal")
  stdout.writeLine(
    "hagia_shell_bar_proof schema=1 status=complete edge=bottom thickness=" &
      $reservation.get().thicknessPx & " withdrawn=true"
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
  let reservation = barReservation()
  if reservation.isSome:
    stdout.writeLine(
      "hagia_shell schema=1 status=bar_configured edge=bottom thickness=" &
        $reservation.get().thicknessPx
    )
  stdout.writeLine(
    "hagia_shell schema=1 status=ready connection_epoch=" & $connectionEpoch
  )
  while true:
    let snapshotFrame = socket.receiveFrame()
    let snapshot = snapshotFrame.decodeSnapshot()
    model.reconcile(snapshot)
    let candidate = model.candidate(candidateGeneration, showNext, reservation)
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
  elif arguments == @["--bar-proof"]:
    socketPath.runBarProof()
  elif arguments == @["--serve"]:
    socketPath.runServer()
  else:
    fail("hagia-shell: expected --proof, --bar-proof, or --serve")

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
