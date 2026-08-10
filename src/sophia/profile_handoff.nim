import ../config/profile
import ./wm_v1

type
  ProfileHandoffError* = object of CatchableError

  ProfileHandoffPhase* {.pure.} = enum
    loaded
    prepared
    active
    rolledBack

  ProfileHandoffMsgKind* {.pure.} = enum
    prepare
    activate
    rollback

  ProfileHandoffModel* = object
    phase*: ProfileHandoffPhase
    connectionEpoch*: uint64
    candidateGeneration*: uint64
    candidateDigest*: array[profileDigestLen, byte]
    preparedIdentity*: ProfileIdentity
    activeIdentity*: ProfileIdentity
    rollbackIdentity*: ProfileIdentity

  ProfileHandoffMsg* = object
    kind*: ProfileHandoffMsgKind
    command*: ProfileCommand

  ProfileHandoffUpdate* = object
    model*: ProfileHandoffModel
    completion*: ProfileCompletion

proc fail(message: string) {.noreturn.} =
  raise newException(ProfileHandoffError, message)

proc hexNibble(value: char): byte =
  case value
  of '0' .. '9':
    byte(ord(value) - ord('0'))
  of 'a' .. 'f':
    byte(ord(value) - ord('a') + 10)
  of 'A' .. 'F':
    byte(ord(value) - ord('A') + 10)
  else:
    fail("profile digest contains a non-hexadecimal character")

proc decodeProfileDigest(value: string): array[profileDigestLen, byte] =
  if value.len != profileDigestLen * 2:
    fail("profile digest must contain exactly 32 bytes")
  for index in 0 ..< profileDigestLen:
    result[index] =
      (value[index * 2].hexNibble() shl 4) or value[index * 2 + 1].hexNibble()

proc initProfileHandoff*(
    candidate: AuthorityCandidate, connectionEpoch: uint64
): ProfileHandoffModel =
  if candidate.authority != ProfileAuthority.policy or candidate.generation == 0 or
      connectionEpoch == 0:
    fail("profile handoff requires a nonzero policy candidate")
  result.phase = ProfileHandoffPhase.loaded
  result.connectionEpoch = connectionEpoch
  result.candidateGeneration = candidate.generation
  result.candidateDigest = candidate.digest.decodeProfileDigest()

proc candidateMatches(model: ProfileHandoffModel, identity: ProfileIdentity): bool =
  identity.connectionEpoch == model.connectionEpoch and
    identity.profileGeneration == model.candidateGeneration and
    identity.profileDigest == model.candidateDigest

proc isNull(identity: ProfileIdentity): bool =
  identity.connectionEpoch == 0

proc accept(
    update: var ProfileHandoffUpdate,
    command: ProfileCommand,
    phase: ProfileHandoffPhase,
) =
  update.model.phase = phase
  update.completion = ProfileCompletion(
    transaction: command.transaction,
    identity: command.identity,
    outcome: ProfileOutcomeKind.accepted,
  )

proc reject(
    update: var ProfileHandoffUpdate,
    command: ProfileCommand,
    outcome: ProfileOutcomeKind,
) =
  update.completion = ProfileCompletion(
    transaction: command.transaction, identity: command.identity, outcome: outcome
  )

proc reduceProfileHandoff*(
    model: ProfileHandoffModel, message: ProfileHandoffMsg
): ProfileHandoffUpdate =
  ## Pure policy-authority participant reducer. The staged candidate is the
  ## only admissible payload identity; phase retries are exact and idempotent.
  result.model = model
  let command = message.command
  if command.transaction == 0 or command.identity.isNull():
    fail("profile handoff command identity is invalid")
  if not model.candidateMatches(command.identity):
    result.reject(command, ProfileOutcomeKind.rejectedIdentity)
    return

  case message.kind
  of ProfileHandoffMsgKind.prepare:
    case model.phase
    of ProfileHandoffPhase.loaded:
      result.model.preparedIdentity = command.identity
      result.accept(command, ProfileHandoffPhase.prepared)
    of ProfileHandoffPhase.prepared:
      if model.preparedIdentity == command.identity:
        result.accept(command, ProfileHandoffPhase.prepared)
      else:
        result.reject(command, ProfileOutcomeKind.rejectedIdentity)
    of ProfileHandoffPhase.active, ProfileHandoffPhase.rolledBack:
      result.reject(command, ProfileOutcomeKind.rejectedState)
  of ProfileHandoffMsgKind.activate:
    case model.phase
    of ProfileHandoffPhase.prepared:
      if model.preparedIdentity != command.identity:
        result.reject(command, ProfileOutcomeKind.rejectedIdentity)
        return
      result.model.activeIdentity = command.identity
      result.accept(command, ProfileHandoffPhase.active)
    of ProfileHandoffPhase.active:
      if model.activeIdentity == command.identity:
        result.accept(command, ProfileHandoffPhase.active)
      else:
        result.reject(command, ProfileOutcomeKind.rejectedIdentity)
    of ProfileHandoffPhase.loaded, ProfileHandoffPhase.rolledBack:
      result.reject(command, ProfileOutcomeKind.rejectedState)
  of ProfileHandoffMsgKind.rollback:
    case model.phase
    of ProfileHandoffPhase.loaded:
      result.model.rollbackIdentity = command.identity
      result.accept(command, ProfileHandoffPhase.rolledBack)
    of ProfileHandoffPhase.prepared:
      if model.preparedIdentity != command.identity:
        result.reject(command, ProfileOutcomeKind.rejectedIdentity)
        return
      result.model.preparedIdentity = ProfileIdentity()
      result.model.rollbackIdentity = command.identity
      result.accept(command, ProfileHandoffPhase.rolledBack)
    of ProfileHandoffPhase.active:
      if model.activeIdentity != command.identity:
        result.reject(command, ProfileOutcomeKind.rejectedIdentity)
        return
      result.model.activeIdentity = ProfileIdentity()
      result.model.rollbackIdentity = command.identity
      result.accept(command, ProfileHandoffPhase.rolledBack)
    of ProfileHandoffPhase.rolledBack:
      if model.rollbackIdentity == command.identity:
        result.accept(command, ProfileHandoffPhase.rolledBack)
      else:
        result.reject(command, ProfileOutcomeKind.rejectedIdentity)
