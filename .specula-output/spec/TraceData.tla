---------------- MODULE TraceData ----------------
State(a, ag, c, cg, lg, p, la, rb, ph, r, pr) ==
    [active |-> a, activeGeneration |-> ag,
     candidate |-> c, candidateGeneration |-> cg, latestGeneration |-> lg,
     preparedCount |-> p, locallyActivatedCount |-> la,
     rollbackPendingCount |-> rb, phase |-> ph,
     rejectedCount |-> r, promotedCount |-> pr]

TraceLog == <<
  [event |-> [name |-> "BeginProfile", generation |-> 1, digest |-> "d1", state |-> State("none", 0, "d1", 1, 1, 0, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "policy", state |-> State("none", 0, "d1", 1, 1, 1, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "shell", state |-> State("none", 0, "d1", 1, 1, 2, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "shortcut", state |-> State("none", 0, "d1", 1, 1, 3, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "session", state |-> State("none", 0, "d1", 1, 1, 4, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "input", state |-> State("none", 0, "d1", 1, 1, 5, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "output", state |-> State("none", 0, "d1", 1, 1, 6, 0, 0, "preparing", 0, 0)]],
  [event |-> [name |-> "PrepareAuthority", authority |-> "broker", state |-> State("none", 0, "d1", 1, 1, 7, 0, 0, "prepared", 0, 0)]],
  [event |-> [name |-> "RequestActivation", state |-> State("none", 0, "d1", 1, 1, 7, 0, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "policy", state |-> State("none", 0, "d1", 1, 1, 7, 1, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "shell", state |-> State("none", 0, "d1", 1, 1, 7, 2, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "shortcut", state |-> State("none", 0, "d1", 1, 1, 7, 3, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "session", state |-> State("none", 0, "d1", 1, 1, 7, 4, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "input", state |-> State("none", 0, "d1", 1, 1, 7, 5, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "output", state |-> State("none", 0, "d1", 1, 1, 7, 6, 0, "activating", 0, 0)]],
  [event |-> [name |-> "ActivateAuthority", authority |-> "broker", state |-> State("d1", 1, "none", 0, 1, 0, 0, 0, "idle", 0, 1)]]
>>

=====================================================
