-------------------- MODULE base --------------------
EXTENDS FiniteSets, Naturals, Sequences, TLC

CONSTANTS Authorities, Digests, NoDigest

VARIABLES active, candidate, prepared, locallyActivated, rollbackPending,
          phase, generation, rejected, promoted, priorActive

vars == <<active, candidate, prepared, locallyActivated, rollbackPending,
          phase, generation, rejected, promoted, priorActive>>

Phases == {"idle", "preparing", "prepared", "activating", "rollingBack"}
AuthoritySymmetry == Permutations(Authorities)

Init ==
    /\ active = NoDigest
    /\ candidate = NoDigest
    /\ prepared = {}
    /\ locallyActivated = {}
    /\ rollbackPending = {}
    /\ phase = "idle"
    /\ generation = 0
    /\ rejected = {}
    /\ promoted = {}
    /\ priorActive = NoDigest

\* src/config/coordinator.nim:111-121; retain one immutable candidate and
\* dispatch prepare to the complete authority set.
BeginProfile(d) ==
    /\ phase = "idle"
    /\ d \in Digests \ {NoDigest}
    /\ d \notin rejected \cup promoted
    /\ candidate' = d
    /\ prepared' = {}
    /\ locallyActivated' = {}
    /\ rollbackPending' = {}
    /\ phase' = "preparing"
    /\ priorActive' = active
    /\ UNCHANGED <<active, generation, rejected, promoted>>

\* src/config/coordinator.nim:122-133; one successful prepare completion.
PrepareAuthority(a) ==
    /\ phase = "preparing"
    /\ a \in Authorities \ prepared
    /\ prepared' = prepared \cup {a}
    /\ phase' = IF prepared' = Authorities THEN "prepared" ELSE "preparing"
    /\ UNCHANGED <<active, candidate, locallyActivated, rollbackPending,
                    generation, rejected, promoted, priorActive>>

\* src/config/coordinator.nim:128-130,93-101; any failed prepare starts an
\* all-authority idempotent rollback and preserves active.
RejectPreparation(a) ==
    /\ phase = "preparing"
    /\ a \in Authorities \ prepared
    /\ phase' = "rollingBack"
    /\ rollbackPending' = Authorities
    /\ rejected' = rejected \cup {candidate}
    /\ UNCHANGED <<active, candidate, prepared, locallyActivated,
                    generation, promoted, priorActive>>

\* src/config/coordinator.nim:134-143; activation effects are unavailable
\* until the prepare barrier is complete.
RequestActivation ==
    /\ phase = "prepared"
    /\ prepared = Authorities
    /\ phase' = "activating"
    /\ UNCHANGED <<active, candidate, prepared, locallyActivated,
                    rollbackPending, generation, rejected, promoted, priorActive>>

\* src/config/coordinator.nim:144-159; activation is per authority. Promotion
\* happens only on the final successful completion.
ActivateAuthority(a) ==
    /\ phase = "activating"
    /\ a \in Authorities \ locallyActivated
    /\ LET nextActivated == locallyActivated \cup {a}
       IN /\ locallyActivated' = IF nextActivated = Authorities THEN {} ELSE nextActivated
          /\ active' = IF nextActivated = Authorities THEN candidate ELSE active
          /\ promoted' = IF nextActivated = Authorities
                           THEN promoted \cup {candidate} ELSE promoted
          /\ generation' = IF nextActivated = Authorities
                            THEN generation + 1 ELSE generation
          /\ candidate' = IF nextActivated = Authorities THEN NoDigest ELSE candidate
          /\ prepared' = IF nextActivated = Authorities THEN {} ELSE prepared
          /\ rollbackPending' = {}
          /\ phase' = IF nextActivated = Authorities THEN "idle" ELSE "activating"
          /\ priorActive' = IF nextActivated = Authorities THEN candidate ELSE priorActive
    /\ UNCHANGED rejected

\* src/config/coordinator.nim:152-154,93-101; partial local activation is
\* rolled back generation-wide without promoting the candidate.
RejectActivation(a) ==
    /\ phase = "activating"
    /\ a \in Authorities \ locallyActivated
    /\ phase' = "rollingBack"
    /\ rollbackPending' = Authorities
    /\ rejected' = rejected \cup {candidate}
    /\ UNCHANGED <<active, candidate, prepared, locallyActivated,
                    generation, promoted, priorActive>>

\* src/config/coordinator.nim:160-168; clear the candidate only after every
\* participant acknowledged rollback.
CompleteRollback(a) ==
    /\ phase = "rollingBack"
    /\ a \in rollbackPending
    /\ LET remaining == rollbackPending \ {a}
       IN /\ rollbackPending' = remaining
          /\ candidate' = IF remaining = {} THEN NoDigest ELSE candidate
          /\ prepared' = IF remaining = {} THEN {} ELSE prepared
          /\ locallyActivated' = IF remaining = {} THEN {} ELSE locallyActivated
          /\ phase' = IF remaining = {} THEN "idle" ELSE "rollingBack"
    /\ UNCHANGED <<active, generation, rejected, promoted, priorActive>>

\* src/config/coordinator.nim:123-124,145-148,161-162; stale completions are
\* typed no-ops, including late activation completions during rollback.
IgnoreStaleCompletion(d) ==
    /\ d \in Digests
    /\ d /= candidate
    /\ UNCHANGED vars

\* src/config/coordinator.nim:147-148; matching late activation completions
\* received after rollback starts are also no-ops.
IgnoreLateActivation(a) ==
    /\ phase = "rollingBack"
    /\ a \in Authorities
    /\ UNCHANGED vars

Next ==
    \/ \E d \in Digests : BeginProfile(d)
    \/ \E a \in Authorities : PrepareAuthority(a)
    \/ \E a \in Authorities : RejectPreparation(a)
    \/ RequestActivation
    \/ \E a \in Authorities : ActivateAuthority(a)
    \/ \E a \in Authorities : RejectActivation(a)
    \/ \E a \in Authorities : CompleteRollback(a)
    \/ \E d \in Digests : IgnoreStaleCompletion(d)
    \/ \E a \in Authorities : IgnoreLateActivation(a)

TypeOK ==
    /\ active \in Digests
    /\ candidate \in Digests
    /\ prepared \subseteq Authorities
    /\ locallyActivated \subseteq Authorities
    /\ rollbackPending \subseteq Authorities
    /\ phase \in Phases
    /\ generation \in Nat
    /\ rejected \subseteq Digests
    /\ promoted \subseteq Digests
    /\ priorActive \in Digests

ActiveWasFullyActivated == active = NoDigest \/ active \in promoted
RejectedNeverPromoted == rejected \cap promoted = {}
PartialCandidateNotActive ==
    candidate = NoDigest \/ phase = "idle" \/ active /= candidate
LastKnownGoodUntilPromotion == phase = "idle" \/ active = priorActive
RollbackCannotPromote == phase /= "rollingBack" \/ active = priorActive

=====================================================
