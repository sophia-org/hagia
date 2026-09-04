import ./wm_v1

## Passive records for the startup profile handoff: the phase Hagia reached,
## the identities it prepared or activated, and the disposition it settled on.
## The transition and digest decoding live in `src/sophia/profile_handoff.nim`.

type
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

  StartupProfileHandoffDisposition* {.pure.} = enum
    activated
    rolledBack
    rejected
