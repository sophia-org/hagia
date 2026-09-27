import std/[os, unittest]

import config/policy_environment
import types/policy_environment
import sophia/policy_checkpoint

## Sophia's WM policy environment: the generic `SOPHIA_WM_POLICY_*` names, the
## pre-rename `HAGIA_POLICY_*` fallback, and the presence rule between them.

proc clear(name: PolicyEnvironmentName) =
  delEnv(name.sophia)
  delEnv(name.legacy)

proc isolated(body: proc()) =
  ## Every pair starts unset, so an inherited session value cannot answer.
  for name in policyEnvironmentNames:
    name.clear()
  try:
    body()
  finally:
    for name in policyEnvironmentNames:
      name.clear()

proc raisedMessage(body: proc()): string =
  try:
    body()
  except CatchableError as error:
    return error.msg
  "no error"

suite "Sophia WM policy environment names":
  test "each reader names the generic Sophia variable and its legacy fallback":
    check policyCheckpointEnvironment.sophia == "SOPHIA_WM_POLICY_CHECKPOINT"
    check policyCheckpointEnvironment.legacy == "HAGIA_POLICY_CHECKPOINT"
    check policyCandidateEnvironment.sophia == "SOPHIA_WM_POLICY_CANDIDATE"
    check policyCandidateEnvironment.legacy == "HAGIA_POLICY_CANDIDATE"
    check policyProfileActivationEnvironment.sophia ==
      "SOPHIA_WM_POLICY_PROFILE_ACTIVATION"
    check policyProfileActivationEnvironment.legacy == "HAGIA_POLICY_PROFILE_ACTIVATION"

  test "only the Sophia name set is read":
    proc body() =
      for name in policyEnvironmentNames:
        putEnv(name.sophia, "/sophia/" & name.sophia)
        let resolved = name.resolve()
        check resolved.value == "/sophia/" & name.sophia
        check resolved.source == PolicyEnvironmentSource.sophia
        check not resolved.conflicting
        check name.resolvedValue() == "/sophia/" & name.sophia

    isolated(body)

  test "only the legacy name set is read from a release before the rename":
    proc body() =
      for name in policyEnvironmentNames:
        putEnv(name.legacy, "/legacy/" & name.legacy)
        let resolved = name.resolve()
        check resolved.value == "/legacy/" & name.legacy
        check resolved.source == PolicyEnvironmentSource.legacy
        check not resolved.conflicting
        check name.resolvedValue() == "/legacy/" & name.legacy

    isolated(body)

  test "both set to different values: the Sophia name wins and is reported":
    proc body() =
      for name in policyEnvironmentNames:
        putEnv(name.sophia, "/sophia")
        putEnv(name.legacy, "/legacy")
        let resolved = name.resolve()
        check resolved.value == "/sophia"
        check resolved.source == PolicyEnvironmentSource.sophia
        check resolved.conflicting
        # A conflict is a diagnostic, never a failure.
        check name.resolvedValue() == "/sophia"

    isolated(body)

  test "both set to the same value is no conflict":
    proc body() =
      for name in policyEnvironmentNames:
        putEnv(name.sophia, "/same")
        putEnv(name.legacy, "/same")
        let resolved = name.resolve()
        check resolved.value == "/same"
        check resolved.source == PolicyEnvironmentSource.sophia
        check not resolved.conflicting

    isolated(body)

  test "a set but empty Sophia name wins over a legacy value":
    # Presence decides precedence, so a current Sophia's explicit empty value is
    # never replaced by a stale legacy value inherited beside it.
    proc body() =
      for name in policyEnvironmentNames:
        putEnv(name.sophia, "")
        putEnv(name.legacy, "/legacy")
        let resolved = name.resolve()
        check resolved.value == ""
        check resolved.source == PolicyEnvironmentSource.sophia
        check resolved.conflicting
        check name.resolvedValue() == ""

    isolated(body)

  test "neither name set reads as empty, the existing not-supplied value":
    proc body() =
      for name in policyEnvironmentNames:
        let resolved = name.resolve()
        check resolved.value == ""
        check resolved.source == PolicyEnvironmentSource.absent
        check not resolved.conflicting
        check name.resolvedValue() == ""

    isolated(body)

  test "the checkpoint path follows the same rule":
    proc body() =
      check checkpointPath() == ""
      putEnv(policyCheckpointEnvironment.legacy, "/legacy/policy.checkpoint")
      check checkpointPath() == "/legacy/policy.checkpoint"
      # Hagia uses the path it is given; the generic file name is Sophia's.
      putEnv(policyCheckpointEnvironment.sophia, "/sophia/sophia-wm-policy.checkpoint")
      check checkpointPath() == "/sophia/sophia-wm-policy.checkpoint"
      putEnv(policyCheckpointEnvironment.sophia, "")
      check checkpointPath() == ""

    isolated(body)

  test "the unset diagnostic names the Sophia variable and the accepted fallback":
    check policyCheckpointEnvironment.display() ==
      "SOPHIA_WM_POLICY_CHECKPOINT (or legacy HAGIA_POLICY_CHECKPOINT)"

suite "profile activation value":
  test "empty runs an ordinary session with or without a candidate":
    check not profileActivationRequired("", "")
    check not profileActivationRequired("", "/candidate")

  test "required demands Sophia's staged candidate":
    check profileActivationRequired("required", "/candidate")
    check raisedMessage(
      proc() =
        discard profileActivationRequired("required", "")
    ) == "hagia: profile activation requires Sophia's staged policy candidate"

  test "any other value is refused by the Sophia name with the legacy fallback":
    check raisedMessage(
      proc() =
        discard profileActivationRequired("yes", "/candidate")
    ) ==
      "hagia: SOPHIA_WM_POLICY_PROFILE_ACTIVATION (or legacy " &
      "HAGIA_POLICY_PROFILE_ACTIVATION) must be empty or required"
