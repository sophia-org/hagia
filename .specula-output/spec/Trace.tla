------------------- MODULE Trace -------------------
EXTENDS base, TLC

IOEnv == [default |-> TRUE]
JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/startup.ndjson"

\* Local TLC 1.7.4 does not ship Specula's IOUtils Java override. This literal
\* is the exact semantic mirror of ../traces/startup.ndjson; the JsonFile
\* operator remains the instrumentation contract for the pipeline runner.
TraceLog == <<
  [event |-> [name |-> "BeginProfile", digest |-> "d1",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 0,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "policy",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 1,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "shell",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 2,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "shortcut",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 3,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "session",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 4,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "input",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 5,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "output",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 6,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "broker",
    state |-> [active |-> "none", candidate |-> "d1", preparedCount |-> 7,
      phase |-> "preparing", generation |-> 0, rejectedCount |-> 0,
      activatedCount |-> 0]]],
  [event |-> [name |-> "ActivateProfile", digest |-> "d1",
    state |-> [active |-> "d1", candidate |-> "none", preparedCount |-> 0,
      phase |-> "idle", generation |-> 1, rejectedCount |-> 0,
      activatedCount |-> 1]]]
>>

ASSUME Len(TraceLog) > 0

VARIABLE l
traceVars == <<vars, l>>
logline == TraceLog[l]

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name

ValidatePostState ==
    /\ active' = logline.event.state.active
    /\ candidate' = logline.event.state.candidate
    /\ Cardinality(prepared') = logline.event.state.preparedCount
    /\ phase' = logline.event.state.phase
    /\ generation' = logline.event.state.generation
    /\ Cardinality(rejected') = logline.event.state.rejectedCount
    /\ Cardinality(activated') = logline.event.state.activatedCount

TraceBeginProfile ==
    /\ IsEvent("BeginProfile")
    /\ BeginProfile(logline.event.digest)
    /\ ValidatePostState
    /\ l' = l + 1

TracePrepareAuthority ==
    /\ IsEvent("PrepareAuthority")
    /\ PrepareAuthority(logline.event.authority)
    /\ ValidatePostState
    /\ l' = l + 1

TraceActivateProfile ==
    /\ IsEvent("ActivateProfile")
    /\ ActivateProfile(logline.event.digest)
    /\ ValidatePostState
    /\ l' = l + 1

TraceInit == Init /\ l = 1

TraceNext ==
    \/ TraceBeginProfile
    \/ TracePrepareAuthority
    \/ TraceActivateProfile
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED traceVars

\* INIT/NEXT specifications admit semantic stuttering at every state. Fairness
\* makes trace progress the obligation while retaining the required completion
\* property as a falsifiable check.
TraceMatched == WF_traceVars(TraceNext) => <>(l > Len(TraceLog))
TraceView == vars

====================================================
