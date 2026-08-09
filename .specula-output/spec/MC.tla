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

MCRejectProfile ==
    /\ faultCounts.reject < RejectLimit
    /\ RejectProfile
    /\ faultCounts' = [faultCounts EXCEPT !.reject = @ + 1]

MCNext ==
    \/ \E d \in Digests : MCBeginProfile(d)
    \/ \E a \in Authorities : PrepareAuthority(a) /\ UNCHANGED faultCounts
    \/ MCRejectProfile
    \/ \E d \in Digests : ActivateProfile(d) /\ UNCHANGED faultCounts
    \/ \E d \in Digests : IgnoreStaleCompletion(d) /\ UNCHANGED faultCounts

MCTypeOK == TypeOK /\ faultCounts \in [begin: 0..BeginLimit, reject: 0..RejectLimit]
MCView == vars

=====================================================
