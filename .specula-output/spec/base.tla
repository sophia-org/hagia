-------------------- MODULE base --------------------
EXTENDS FiniteSets, Naturals, Sequences

CONSTANTS Authorities, Digests, NoDigest

VARIABLES active, candidate, prepared, phase, generation,
          rejected, activated, priorActive

vars == <<active, candidate, prepared, phase, generation,
          rejected, activated, priorActive>>

Phases == {"idle", "preparing"}

Init ==
    /\ active = NoDigest
    /\ candidate = NoDigest
    /\ prepared = {}
    /\ phase = "idle"
    /\ generation = 0
    /\ rejected = {}
    /\ activated = {}
    /\ priorActive = NoDigest

\* src/runtime/reducer.nim:80-92; begin an immutable candidate generation.
BeginProfile(d) ==
    /\ phase = "idle"
    /\ d \in Digests \ {NoDigest}
    /\ d \notin rejected \cup activated
    /\ candidate' = d
    /\ prepared' = {}
    /\ phase' = "preparing"
    /\ priorActive' = active
    /\ UNCHANGED <<active, generation, rejected, activated>>

\* src/config/coordinator.nim:88-91; each authority prepares independently.
PrepareAuthority(a) ==
    /\ phase = "preparing"
    /\ a \in Authorities \ prepared
    /\ prepared' = prepared \cup {a}
    /\ UNCHANGED <<active, candidate, phase, generation,
                    rejected, activated, priorActive>>

\* src/runtime/reducer.nim:93-95; rejection discards only the candidate.
RejectProfile ==
    /\ phase = "preparing"
    /\ rejected' = rejected \cup {candidate}
    /\ active' = priorActive
    /\ candidate' = NoDigest
    /\ prepared' = {}
    /\ phase' = "idle"
    /\ UNCHANGED <<generation, activated, priorActive>>

\* src/runtime/reducer.nim:134-139 and coordinator.nim:68-75.
\* The shared digest and full authority barrier are the activation guard.
ActivateProfile(d) ==
    /\ phase = "preparing"
    /\ d = candidate
    /\ prepared = Authorities
    /\ d \notin rejected
    /\ active' = d
    /\ activated' = activated \cup {d}
    /\ generation' = generation + 1
    /\ candidate' = NoDigest
    /\ prepared' = {}
    /\ phase' = "idle"
    /\ priorActive' = d
    /\ UNCHANGED rejected

\* src/runtime/reducer.nim:134-135; a stale completion cannot match candidate.
IgnoreStaleCompletion(d) ==
    /\ d \in Digests
    /\ d /= candidate
    /\ UNCHANGED vars

Next ==
    \/ \E d \in Digests : BeginProfile(d)
    \/ \E a \in Authorities : PrepareAuthority(a)
    \/ RejectProfile
    \/ \E d \in Digests : ActivateProfile(d)
    \/ \E d \in Digests : IgnoreStaleCompletion(d)

TypeOK ==
    /\ active \in Digests
    /\ candidate \in Digests
    /\ prepared \subseteq Authorities
    /\ phase \in Phases
    /\ generation \in Nat
    /\ rejected \subseteq Digests
    /\ activated \subseteq Digests
    /\ priorActive \in Digests

ActiveWasFullyPrepared == active = NoDigest \/ active \in activated
RejectedNeverActivated == rejected \cap activated = {}
PartialPreparationNotActive ==
    phase /= "preparing" \/ prepared = Authorities \/ active /= candidate
LastKnownGoodOnReject == phase /= "idle" \/ active = priorActive

=====================================================
