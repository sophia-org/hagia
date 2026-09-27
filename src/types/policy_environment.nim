## The environment names Sophia uses to hand Hagia its policy files. Sophia now
## exports only the generic `SOPHIA_WM_POLICY_*` names; releases before the
## rename export `HAGIA_POLICY_*`. Presence of the Sophia name decides which one
## is read, so a set-but-empty Sophia name is never overridden by a legacy value.
type
  PolicyEnvironmentSource* {.pure.} = enum
    absent ## neither name is set; the value is empty
    sophia ## the generic Sophia name is set, possibly to an empty value
    legacy ## only the pre-rename Hagia name is set

  PolicyEnvironmentName* = object
    sophia*: string
    legacy*: string

  PolicyEnvironmentValue* = object
    value*: string
    source*: PolicyEnvironmentSource
    conflicting*: bool ## both names are set to different values; the Sophia name won

const
  policyCheckpointEnvironment* = PolicyEnvironmentName(
    sophia: "SOPHIA_WM_POLICY_CHECKPOINT", legacy: "HAGIA_POLICY_CHECKPOINT"
  )
  policyCandidateEnvironment* = PolicyEnvironmentName(
    sophia: "SOPHIA_WM_POLICY_CANDIDATE", legacy: "HAGIA_POLICY_CANDIDATE"
  )
  policyProfileActivationEnvironment* = PolicyEnvironmentName(
    sophia: "SOPHIA_WM_POLICY_PROFILE_ACTIVATION",
    legacy: "HAGIA_POLICY_PROFILE_ACTIVATION",
  )

  # Every reader above, in the order the contract line names them. The
  # capability probe prints this list, so it cannot drift from the readers.
  policyEnvironmentNames* = [
    policyCheckpointEnvironment, policyCandidateEnvironment,
    policyProfileActivationEnvironment,
  ]
  policyEnvironmentContractSchema* = 1
  policyEnvironmentContractName* = "sophia-wm-policy-v1"
  policyEnvironmentContractPrecedence* = "presence"
