------------------- MODULE Trace -------------------
EXTENDS base, TLC

IOEnv == [default |-> TRUE]
JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/startup.ndjson"

\* Local TLC lacks Specula's IOUtils override. This is the exact semantic
\* mirror of ../traces/startup.ndjson; JsonFile remains the runner contract.
State(a, c, p, la, rb, ph, g, r, pr) ==
    [active |-> a, candidate |-> c, preparedCount |-> p,
     locallyActivatedCount |-> la, rollbackPendingCount |-> rb,
     phase |-> ph, generation |-> g, rejectedCount |-> r, promotedCount |-> pr]

TraceLog == <<
  [event |-> [name |-> "BeginProfile", digest |-> "d1",
    state |-> State("none", "d1", 0, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "policy",
    state |-> State("none", "d1", 1, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "shell",
    state |-> State("none", "d1", 2, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "shortcut",
    state |-> State("none", "d1", 3, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "session",
    state |-> State("none", "d1", 4, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "input",
    state |-> State("none", "d1", 5, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "output",
    state |-> State("none", "d1", 6, 0, 0, "preparing", 0, 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "broker",
    state |-> State("none", "d1", 7, 0, 0, "prepared", 0, 0, 0)]],
  [event |-> [name |-> "RequestActivation",
    state |-> State("none", "d1", 7, 0, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "policy",
    state |-> State("none", "d1", 7, 1, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "shell",
    state |-> State("none", "d1", 7, 2, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "shortcut",
    state |-> State("none", "d1", 7, 3, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "session",
    state |-> State("none", "d1", 7, 4, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "input",
    state |-> State("none", "d1", 7, 5, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "output",
    state |-> State("none", "d1", 7, 6, 0, "activating", 0, 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "broker",
    state |-> State("d1", "none", 0, 0, 0, "idle", 1, 0, 1)]]
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
    /\ Cardinality(locallyActivated') = logline.event.state.locallyActivatedCount
    /\ Cardinality(rollbackPending') = logline.event.state.rollbackPendingCount
    /\ phase' = logline.event.state.phase
    /\ generation' = logline.event.state.generation
    /\ Cardinality(rejected') = logline.event.state.rejectedCount
    /\ Cardinality(promoted') = logline.event.state.promotedCount

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
