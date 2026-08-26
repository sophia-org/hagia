import std/[options, os, strutils, unittest]

import sophia/shell_v1

proc hexNibble(character: char): int =
  case character
  of '0' .. '9':
    ord(character) - ord('0')
  of 'a' .. 'f':
    ord(character) - ord('a') + 10
  else:
    -1

proc decodeHex(text: string): seq[byte] =
  if text.len mod 2 != 0:
    raise newException(ValueError, "odd hexadecimal input")
  result = newSeq[byte](text.len div 2)
  for index in 0 ..< result.len:
    let high = text[index * 2].hexNibble()
    let low = text[index * 2 + 1].hexNibble()
    if high < 0 or low < 0:
      raise newException(ValueError, "invalid hexadecimal input")
    result[index] = byte((high shl 4) or low)

proc corpusLines(path: string): seq[string] =
  for line in readFile(path).splitLines():
    let stripped = line.strip()
    if stripped.len > 0 and not stripped.startsWith("#"):
      result.add(stripped)

proc frameNamed(path, name: string): ShellFrame =
  for line in path.corpusLines():
    let fields = line.split('|')
    if fields[0] == name:
      return fields[2].decodeHex().decodeShellFrame()
  raise newException(ValueError, "missing shell corpus frame " & name)

suite "independent Sophia Shell v1 wire and reducer":
  test "shared golden frames round trip and malformed frames fail closed":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    let valid = sophiaRoot / "protocol/golden/sophia-shell-v1.frames"
    let malformed = sophiaRoot / "protocol/golden/sophia-shell-v1-malformed.frames"
    let validLines = valid.corpusLines()
    let malformedLines = malformed.corpusLines()
    check validLines.len == 10
    check malformedLines.len == 16
    for line in validLines:
      let fields = line.split('|')
      check fields.len == 3
      let bytes = fields[2].decodeHex()
      check bytes.decodeShellFrame().encodeShellFrame() == bytes
    for line in malformedLines:
      let fields = line.split('|')
      check fields.len == 4
      expect ShellProtocolError:
        discard fields[3].decodeHex().decodeShellFrame()

  test "unlabeled descriptor consumes only its presence and redaction bytes":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    let valid = sophiaRoot / "protocol/golden/sophia-shell-v1.frames"
    let snapshot = valid.frameNamed("descriptor_snapshot_unlabeled").decodeSnapshot()
    check snapshot.descriptors.len == 1
    check snapshot.descriptors[0].label.isNone
    check not snapshot.descriptors[0].labelRedacted

  test "presented activation is exact and consumed at most once":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    let valid = sophiaRoot / "protocol/golden/sophia-shell-v1.frames"
    let snapshot = valid.frameNamed("descriptor_snapshot").decodeSnapshot()
    var model = ShellModel(connectionEpoch: snapshot.connectionEpoch)
    model.reconcile(snapshot)
    let candidate = model.candidate(1, true)
    check candidate.visible
    check candidate.selected.get() == 2
    check candidate.entries.len == 1
    model.rememberPresented(valid.frameNamed("candidate_outcome").decodeOutcome())
    let activation = valid.frameNamed("activation").decodeActivation()
    check model.accept(activation) == ShellActivationDisposition.consumed
    check model.accept(activation) == ShellActivationDisposition.rejectedStale
    var stale = activation
    stale.activation += 1
    stale.presentationEpoch += 1
    check model.accept(stale) == ShellActivationDisposition.rejectedStale

  test "a reserving candidate encodes exactly the shared golden frame":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    let valid = sophiaRoot / "protocol/golden/sophia-shell-v1.frames"
    var golden: string
    for line in valid.corpusLines():
      let fields = line.split('|')
      if fields[0] == "candidate_reserved":
        golden = fields[2]
    require golden.len > 0
    let snapshot = valid.frameNamed("descriptor_snapshot").decodeSnapshot()
    var model = ShellModel(connectionEpoch: snapshot.connectionEpoch)
    model.reconcile(snapshot)
    let reserving = model.candidate(
      2,
      true,
      some(ShellReservation(edge: ShellReservationEdge.bottom, thicknessPx: 28)),
    )
    check reserving.reservation.isSome
    let transaction = 0x0102030405060708'u64
    check reserving.candidateFrame(transaction).encodeShellFrame() ==
      golden.decodeHex()

  test "complete snapshot withdrawal clears visible shell state":
    let sophiaRoot = getEnv("SOPHIA_STACK_ROOT")
    require sophiaRoot.len > 0
    let valid = sophiaRoot / "protocol/golden/sophia-shell-v1.frames"
    let snapshot = valid.frameNamed("descriptor_snapshot").decodeSnapshot()
    var model = ShellModel(connectionEpoch: snapshot.connectionEpoch)
    model.reconcile(snapshot)
    var empty = snapshot
    empty.generation += 1
    empty.descriptors.setLen(0)
    model.reconcile(empty)
    let withdrawal = model.candidate(2, false)
    check not withdrawal.visible
    check withdrawal.selected.isNone
    check withdrawal.entries.len == 0
