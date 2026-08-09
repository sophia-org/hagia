--------------------- MODULE MC ---------------------
EXTENDS base

CONSTANT BeginLimit, RejectLimit
VARIABLE faultCounts

mcVars == <<vars, faultCounts>>

MCInit == Init /\ faultCounts = [begin |-> 0, reject |-> 0]

MCBeginProfile(d) ==
    /\ faultCounts.begin < BeginLimit
    /\ BeginProfile(d)
    /\ faultCounts' = [faultCounts EXCEPT !.begin = @ + 1]

MCRejectPreparation(a) ==
    /\ faultCounts.reject < RejectLimit
    /\ RejectPreparation(a)
    /\ faultCounts' = [faultCounts EXCEPT !.reject = @ + 1]

MCRejectActivation(a) ==
    /\ faultCounts.reject < RejectLimit
    /\ RejectActivation(a)
    /\ faultCounts' = [faultCounts EXCEPT !.reject = @ + 1]

MCNext ==
    \/ \E d \in Digests : MCBeginProfile(d)
    \/ \E a \in Authorities : PrepareAuthority(a) /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : MCRejectPreparation(a)
    \/ RequestActivation /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : ActivateAuthority(a) /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : MCRejectActivation(a)
    \/ \E a \in Authorities : CompleteRollback(a) /\ UNCHANGED faultCounts
    \/ \E d \in Digests : IgnoreStaleCompletion(d) /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : IgnoreLateActivation(a) /\ UNCHANGED faultCounts

MCTypeOK == TypeOK /\ faultCounts \in [begin: 0..BeginLimit, reject: 0..RejectLimit]
MCView == vars
MCSymmetry == AuthoritySymmetry

=====================================================
