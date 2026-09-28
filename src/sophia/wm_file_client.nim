import std/options
import ../config/policy_candidate
import ../types/config_values
import ../types/observability
import ../observability
import ./[policy_loop, policy_signals, policy_transport, policy_wire, wm_file_wire]

proc runFilePolicySession*(
    path: string, candidate: AuthorityCandidate, profileActivation: bool
) =
  ## Only the selected endpoint is connected. Discovery/admission belongs to
  ## fileWire; profile activation and policy settlement use the shared loop.
  ## A stop signal is an ordinary return once the session has closed.
  installStopSignals()
  let settings = candidate.policyCandidateSettings()
  try:
    let wire = path.connectWhenReady().fileWire(
        requestProfileActivation = profileActivation,
        requestPointerFocus = settings.focusFollowsMouse,
        requestOutputAssignments = settings.workspaceAssignments.len > 0,
      )
    try:
      if profileActivation:
        wire.runActivatedPolicy(candidate)
      else:
        wire.runPolicySession(true, some(candidate))
    finally:
      wire.close()
  except StopRequestedError as stop:
    operationalLog(OperationalLevel.info, "session", "stopped", stop.msg)
    recordEvidence(
      EvidenceEvent(kind: EvidenceKind.connection, event: "stop", status: "stopped")
    )
