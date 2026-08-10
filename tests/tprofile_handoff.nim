import std/[strutils, unittest]

import config/profile
import sophia/[profile_handoff, wm_v1]

proc candidate(generation: uint64, digestByte: string): AuthorityCandidate =
  AuthorityCandidate(
    authority: ProfileAuthority.policy,
    generation: generation,
    digest: repeat(digestByte, profileDigestLen),
  )

proc identity(epoch, generation: uint64, digest: byte): ProfileIdentity =
  result.connectionEpoch = epoch
  result.profileGeneration = generation
  for index in 0 ..< profileDigestLen:
    result.profileDigest[index] = digest

proc command(transaction: uint64, identity: ProfileIdentity): ProfileCommand =
  ProfileCommand(transaction: transaction, identity: identity)

proc reduce(
    model: ProfileHandoffModel,
    kind: ProfileHandoffMsgKind,
    transaction: uint64,
    identity: ProfileIdentity,
): ProfileHandoffUpdate =
  model.reduceProfileHandoff(
    ProfileHandoffMsg(kind: kind, command: command(transaction, identity))
  )

suite "Hagia profile authority handoff":
  test "exact prepare and activate promote only the loaded candidate":
    let identity = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff()
    check loaded.phase == ProfileHandoffPhase.loaded

    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, identity)
    check prepared.model.phase == ProfileHandoffPhase.prepared
    check prepared.completion.outcome == ProfileOutcomeKind.accepted
    check prepared.model.preparedIdentity == identity

    let active = prepared.model.reduce(ProfileHandoffMsgKind.activate, 2, identity)
    check active.model.phase == ProfileHandoffPhase.active
    check active.completion.outcome == ProfileOutcomeKind.accepted
    check active.model.activeIdentity == identity

  test "file and wire identity mismatch is rejected without mutation":
    let loaded = candidate(7, "5a").initProfileHandoff()
    for wrong in [identity(9, 8, 0x5a), identity(9, 7, 0xa5)]:
      let update = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, wrong)
      check update.model == loaded
      check update.completion.outcome == ProfileOutcomeKind.rejectedIdentity

  test "phase and epoch mismatches fail closed":
    let exact = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff()
    let premature = loaded.reduce(ProfileHandoffMsgKind.activate, 1, exact)
    check premature.model == loaded
    check premature.completion.outcome == ProfileOutcomeKind.rejectedState

    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 2, exact).model
    let wrongEpoch =
      prepared.reduce(ProfileHandoffMsgKind.activate, 3, identity(10, 7, 0x5a))
    check wrongEpoch.model == prepared
    check wrongEpoch.completion.outcome == ProfileOutcomeKind.rejectedIdentity

  test "exact retries are idempotent and preserve the latest transaction":
    let exact = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff()
    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, exact).model
    let retried = prepared.reduce(ProfileHandoffMsgKind.prepare, 2, exact)
    check retried.model == prepared
    check retried.completion.transaction == 2
    check retried.completion.outcome == ProfileOutcomeKind.accepted

  test "rollback discards prepared or active candidate state":
    let exact = identity(9, 7, 0x5a)
    let loaded = candidate(7, "5a").initProfileHandoff()
    let prepared = loaded.reduce(ProfileHandoffMsgKind.prepare, 1, exact).model
    let rolledBack = prepared.reduce(ProfileHandoffMsgKind.rollback, 2, exact)
    check rolledBack.model.phase == ProfileHandoffPhase.rolledBack
    check rolledBack.model.preparedIdentity == ProfileIdentity()
    check rolledBack.completion.outcome == ProfileOutcomeKind.accepted

    let retry = rolledBack.model.reduce(ProfileHandoffMsgKind.rollback, 3, exact)
    check retry.model == rolledBack.model
    check retry.completion.outcome == ProfileOutcomeKind.accepted

  test "invalid local candidate and command identities are terminal errors":
    expect ProfileHandoffError:
      discard AuthorityCandidate(
        authority: ProfileAuthority.session,
        generation: 1,
        digest: repeat("11", profileDigestLen),
      ).initProfileHandoff()
    let loaded = candidate(7, "5a").initProfileHandoff()
    expect ProfileHandoffError:
      discard loaded.reduce(ProfileHandoffMsgKind.prepare, 0, identity(9, 7, 0x5a))
