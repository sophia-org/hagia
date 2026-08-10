------------------- MODULE Trace -------------------
EXTENDS base, TLC, TraceData

IOEnv == [default |-> TRUE]
JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/startup.ndjson"

\* Local TLC lacks Specula's IOUtils override. TraceData is generated
\* deterministically from JsonFile by tools/render_profile_trace_tla.sh.

ASSUME Len(TraceLog) > 0

VARIABLE l
traceVars == <<vars, l>>
logline == TraceLog[l]
IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name

ValidatePostState ==
    /\ active' = logline.event.state.active
    /\ activeGeneration' = logline.event.state.activeGeneration
    /\ candidate' = logline.event.state.candidate
    /\ candidateGeneration' = logline.event.state.candidateGeneration
    /\ latestGeneration' = logline.event.state.latestGeneration
    /\ Cardinality(prepared') = logline.event.state.preparedCount
    /\ Cardinality(locallyActivated') = logline.event.state.locallyActivatedCount
    /\ Cardinality(rollbackPending') = logline.event.state.rollbackPendingCount
    /\ phase' = logline.event.state.phase
    /\ Cardinality(rejected') = logline.event.state.rejectedCount
    /\ Cardinality(promoted') = logline.event.state.promotedCount

TraceBeginProfile ==
    /\ IsEvent("BeginProfile")
    /\ BeginProfile(logline.event.generation, logline.event.digest)
    /\ ValidatePostState
    /\ l' = l + 1

TracePrepareAuthority ==
    /\ IsEvent("PrepareAuthority")
    /\ PrepareAuthority(logline.event.authority)
    /\ ValidatePostState
    /\ l' = l + 1

TraceRequestActivation ==
    /\ IsEvent("RequestActivation")
    /\ RequestActivation
    /\ ValidatePostState
    /\ l' = l + 1

TraceActivateAuthority ==
    /\ IsEvent("ActivateAuthority")
    /\ ActivateAuthority(logline.event.authority)
    /\ ValidatePostState
    /\ l' = l + 1

TraceInit == Init /\ l = 1
TraceNext ==
    \/ TraceBeginProfile
    \/ TracePrepareAuthority
    \/ TraceRequestActivation
    \/ TraceActivateAuthority
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED traceVars

TraceMatched == WF_traceVars(TraceNext) => <>(l > Len(TraceLog))
TraceView == vars

====================================================
