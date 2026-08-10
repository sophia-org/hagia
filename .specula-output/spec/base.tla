-------------------- MODULE base --------------------
EXTENDS FiniteSets, Naturals, Sequences, TLC

CONSTANTS Authorities, Digests, NoDigest, Generations, NoGeneration

VARIABLES active, activeGeneration, candidate, candidateGeneration,
          latestGeneration, prepared, locallyActivated, rollbackPending,
          phase, rejected, promoted, priorActive, priorActiveGeneration

vars == <<active, activeGeneration, candidate, candidateGeneration,
          latestGeneration, prepared, locallyActivated, rollbackPending,
          phase, rejected, promoted, priorActive, priorActiveGeneration>>

Phases == {"idle", "preparing", "prepared", "activating", "rollingBack"}
AuthoritySymmetry == Permutations(Authorities)

ProfileIdentity(g, d) == [generation |-> g, digest |-> d]
ProfileIdentities ==
    {ProfileIdentity(g, d) :
        g \in Generations \ {NoGeneration}, d \in Digests \ {NoDigest}}

Init ==
    /\ active = NoDigest
    /\ activeGeneration = NoGeneration
    /\ candidate = NoDigest
    /\ candidateGeneration = NoGeneration
    /\ latestGeneration = NoGeneration
    /\ prepared = {}
    /\ locallyActivated = {}
    /\ rollbackPending = {}
    /\ phase = "idle"
    /\ rejected = {}
    /\ promoted = {}
    /\ priorActive = NoDigest
    /\ priorActiveGeneration = NoGeneration

\* src/config/coordinator.nim:112-123; retain one immutable candidate and
\* dispatch prepare to the complete authority set. Every attempted generation,
\* including a rejected one, permanently advances the monotonic counter.
BeginProfile(g, d) ==
    /\ phase = "idle"
    /\ g \in Generations \ {NoGeneration}
    /\ d \in Digests \ {NoDigest}
    /\ g > activeGeneration
    /\ g > latestGeneration
    /\ d /= active
    /\ candidate' = d
    /\ candidateGeneration' = g
    /\ latestGeneration' = g
    /\ prepared' = {}
    /\ locallyActivated' = {}
    /\ rollbackPending' = {}
    /\ phase' = "preparing"
    /\ priorActive' = active
    /\ priorActiveGeneration' = activeGeneration
    /\ UNCHANGED <<active, activeGeneration, rejected, promoted>>

\* src/config/coordinator.nim:124-135; one successful prepare completion.
PrepareAuthority(a) ==
    /\ phase = "preparing"
    /\ a \in Authorities \ prepared
    /\ prepared' = prepared \cup {a}
    /\ phase' = IF prepared' = Authorities THEN "prepared" ELSE "preparing"
    /\ UNCHANGED <<active, activeGeneration, candidate, candidateGeneration,
                    latestGeneration, locallyActivated, rollbackPending,
                    rejected, promoted, priorActive, priorActiveGeneration>>

\* src/config/coordinator.nim:130-132,94-102; any failed prepare starts an
\* all-authority idempotent rollback and preserves active.
RejectPreparation(a) ==
    /\ phase = "preparing"
    /\ a \in Authorities \ prepared
    /\ phase' = "rollingBack"
    /\ rollbackPending' = Authorities
    /\ rejected' = rejected \cup
         {ProfileIdentity(candidateGeneration, candidate)}
    /\ UNCHANGED <<active, activeGeneration, candidate, candidateGeneration,
                    latestGeneration, prepared, locallyActivated, promoted,
                    priorActive, priorActiveGeneration>>

\* src/config/coordinator.nim:136-145; activation effects are unavailable
\* until the prepare barrier is complete.
RequestActivation ==
    /\ phase = "prepared"
    /\ prepared = Authorities
    /\ phase' = "activating"
    /\ UNCHANGED <<active, activeGeneration, candidate, candidateGeneration,
                    latestGeneration, prepared, locallyActivated,
                    rollbackPending, rejected, promoted, priorActive,
                    priorActiveGeneration>>

\* src/config/coordinator.nim:146-161; activation is per authority. Promotion
\* happens only on the final successful completion.
ActivateAuthority(a) ==
    /\ phase = "activating"
    /\ a \in Authorities \ locallyActivated
    /\ LET nextActivated == locallyActivated \cup {a}
           identity == ProfileIdentity(candidateGeneration, candidate)
       IN /\ locallyActivated' =
                IF nextActivated = Authorities THEN {} ELSE nextActivated
          /\ active' = IF nextActivated = Authorities THEN candidate ELSE active
          /\ activeGeneration' =
                IF nextActivated = Authorities
                THEN candidateGeneration ELSE activeGeneration
          /\ promoted' =
                IF nextActivated = Authorities
                THEN promoted \cup {identity} ELSE promoted
          /\ candidate' =
                IF nextActivated = Authorities THEN NoDigest ELSE candidate
          /\ candidateGeneration' =
                IF nextActivated = Authorities
                THEN NoGeneration ELSE candidateGeneration
          /\ prepared' = IF nextActivated = Authorities THEN {} ELSE prepared
          /\ rollbackPending' = {}
          /\ phase' =
                IF nextActivated = Authorities THEN "idle" ELSE "activating"
          /\ priorActive' =
                IF nextActivated = Authorities THEN candidate ELSE priorActive
          /\ priorActiveGeneration' =
                IF nextActivated = Authorities
                THEN candidateGeneration ELSE priorActiveGeneration
    /\ UNCHANGED <<latestGeneration, rejected>>

\* src/config/coordinator.nim:154-156,94-102; partial local activation is
\* rolled back generation-wide without promoting the candidate.
RejectActivation(a) ==
    /\ phase = "activating"
    /\ a \in Authorities \ locallyActivated
    /\ phase' = "rollingBack"
    /\ rollbackPending' = Authorities
    /\ rejected' = rejected \cup
         {ProfileIdentity(candidateGeneration, candidate)}
    /\ UNCHANGED <<active, activeGeneration, candidate, candidateGeneration,
                    latestGeneration, prepared, locallyActivated, promoted,
                    priorActive, priorActiveGeneration>>

\* src/config/coordinator.nim:162-170; clear the candidate only after every
\* participant acknowledged rollback. latestGeneration deliberately survives.
CompleteRollback(a) ==
    /\ phase = "rollingBack"
    /\ a \in rollbackPending
    /\ LET remaining == rollbackPending \ {a}
       IN /\ rollbackPending' = remaining
          /\ candidate' = IF remaining = {} THEN NoDigest ELSE candidate
          /\ candidateGeneration' =
                IF remaining = {} THEN NoGeneration ELSE candidateGeneration
          /\ prepared' = IF remaining = {} THEN {} ELSE prepared
          /\ locallyActivated' =
                IF remaining = {} THEN {} ELSE locallyActivated
          /\ phase' = IF remaining = {} THEN "idle" ELSE "rollingBack"
    /\ UNCHANGED <<active, activeGeneration, latestGeneration, rejected,
                    promoted, priorActive, priorActiveGeneration>>

\* src/config/coordinator.nim:73-76,125-126,147-150,163-164; completions from
\* any different (generation, digest) identity are typed no-ops.
IgnoreStaleCompletion(g, d) ==
    /\ g \in Generations
    /\ d \in Digests
    /\ g /= candidateGeneration \/ d /= candidate
    /\ UNCHANGED vars

\* src/config/coordinator.nim:149-150; matching late activation completions
\* received after rollback starts are also no-ops.
IgnoreLateActivation(a) ==
    /\ phase = "rollingBack"
    /\ a \in Authorities
    /\ UNCHANGED vars

Next ==
    \/ \E g \in Generations, d \in Digests : BeginProfile(g, d)
    \/ \E a \in Authorities : PrepareAuthority(a)
    \/ \E a \in Authorities : RejectPreparation(a)
    \/ RequestActivation
    \/ \E a \in Authorities : ActivateAuthority(a)
    \/ \E a \in Authorities : RejectActivation(a)
    \/ \E a \in Authorities : CompleteRollback(a)
    \/ \E g \in Generations, d \in Digests : IgnoreStaleCompletion(g, d)
    \/ \E a \in Authorities : IgnoreLateActivation(a)

TypeOK ==
    /\ active \in Digests
    /\ activeGeneration \in Generations
    /\ candidate \in Digests
    /\ candidateGeneration \in Generations
    /\ latestGeneration \in Generations
    /\ prepared \subseteq Authorities
    /\ locallyActivated \subseteq Authorities
    /\ rollbackPending \subseteq Authorities
    /\ phase \in Phases
    /\ rejected \subseteq ProfileIdentities
    /\ promoted \subseteq ProfileIdentities
    /\ priorActive \in Digests
    /\ priorActiveGeneration \in Generations
    /\ (active = NoDigest) = (activeGeneration = NoGeneration)
    /\ (candidate = NoDigest) = (candidateGeneration = NoGeneration)

ActiveWasFullyActivated ==
    active = NoDigest \/
        ProfileIdentity(activeGeneration, active) \in promoted
RejectedNeverPromoted == rejected \cap promoted = {}
PartialCandidateNotActive ==
    candidate = NoDigest \/ phase = "idle" \/
        ProfileIdentity(activeGeneration, active) /=
            ProfileIdentity(candidateGeneration, candidate)
LastKnownGoodUntilPromotion ==
    phase = "idle" \/
        ProfileIdentity(activeGeneration, active) =
            ProfileIdentity(priorActiveGeneration, priorActive)
RollbackCannotPromote ==
    phase /= "rollingBack" \/
        ProfileIdentity(activeGeneration, active) =
            ProfileIdentity(priorActiveGeneration, priorActive)
GenerationNeverRecycles ==
    /\ latestGeneration >= activeGeneration
    /\ (candidateGeneration = NoGeneration \/
          candidateGeneration = latestGeneration)
    /\ \A identity \in rejected \cup promoted :
          identity.generation <= latestGeneration
CandidateIdentityIsFresh ==
    phase = "rollingBack" \/ candidate = NoDigest \/
        ProfileIdentity(candidateGeneration, candidate) \notin rejected \cup promoted

=====================================================
