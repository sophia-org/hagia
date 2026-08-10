--------------------- MODULE MC ---------------------
EXTENDS base

CONSTANT BeginLimit, RejectLimit
VARIABLE faultCounts

mcVars == <<vars, faultCounts>>

MCInit == Init /\ faultCounts = [begin |-> 0, reject |-> 0]

MCBeginProfile(g, d) ==
    /\ faultCounts.begin < BeginLimit
    /\ BeginProfile(g, d)
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
    \/ \E g \in Generations, d \in Digests : MCBeginProfile(g, d)
    \/ \E a \in Authorities : PrepareAuthority(a) /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : MCRejectPreparation(a)
    \/ RequestActivation /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : ActivateAuthority(a) /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : MCRejectActivation(a)
    \/ \E a \in Authorities : CompleteRollback(a) /\ UNCHANGED faultCounts
    \/ \E g \in Generations, d \in Digests :
          IgnoreStaleCompletion(g, d) /\ UNCHANGED faultCounts
    \/ \E a \in Authorities : IgnoreLateActivation(a) /\ UNCHANGED faultCounts

MCTypeOK ==
    TypeOK /\ faultCounts \in [begin: 0..BeginLimit, reject: 0..RejectLimit]
MCView == vars
MCSymmetry == AuthoritySymmetry

=====================================================
