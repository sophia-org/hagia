import std/[os, strutils]

import ../types/observability
import ../observability
import ../types/policy_environment

## The one reader of Sophia's WM policy environment. Precedence is by presence:
## a set Sophia name wins even when empty, so an explicit empty value from a
## current Sophia is never replaced by a stale legacy value. Only when the
## Sophia name is unset is the legacy `HAGIA_POLICY_*` name read. An unset pair
## reads as empty, which each caller already treats as "not supplied".

proc resolve*(name: PolicyEnvironmentName): PolicyEnvironmentValue =
  if existsEnv(name.sophia):
    let value = getEnv(name.sophia)
    PolicyEnvironmentValue(
      value: value,
      source: PolicyEnvironmentSource.sophia,
      conflicting: existsEnv(name.legacy) and getEnv(name.legacy) != value,
    )
  elif existsEnv(name.legacy):
    PolicyEnvironmentValue(
      value: getEnv(name.legacy), source: PolicyEnvironmentSource.legacy
    )
  else:
    PolicyEnvironmentValue(source: PolicyEnvironmentSource.absent)

proc display*(name: PolicyEnvironmentName): string =
  ## Names the variable a current Sophia sets and the accepted fallback.
  name.sophia & " (or legacy " & name.legacy & ")"

proc resolvedValue*(name: PolicyEnvironmentName): string =
  ## Reads the value and reports a conflict once per read. A conflict is not a
  ## failure: the Sophia name is authoritative and the session proceeds.
  let resolved = name.resolve()
  if resolved.conflicting:
    operationalLog(
      OperationalLevel.warning,
      "environment",
      "conflict",
      name.sophia & " overrides a different " & name.legacy,
    )
  resolved.value

proc profileActivationRequired*(activation, candidatePath: string): bool =
  ## Empty runs an ordinary session; `required` demands Sophia's staged
  ## candidate. Any other value is a startup error.
  case activation
  of "":
    false
  of "required":
    if candidatePath.len == 0:
      raise newException(
        ValueError,
        "hagia: profile activation requires Sophia's staged policy candidate",
      )
    true
  else:
    raise newException(
      ValueError,
      "hagia: " & policyProfileActivationEnvironment.display() &
        " must be empty or required",
    )

proc policyEnvironmentContract*(): string =
  ## One stable line an installer can match before trusting a Hagia binary with
  ## the generic names. Built from the same names the readers use, so renaming a
  ## reader changes the line; a semantic change must bump the schema.
  var sophiaNames, legacyNames: seq[string]
  for name in policyEnvironmentNames:
    sophiaNames.add(name.sophia)
    legacyNames.add(name.legacy)
  "hagia_environment_contract schema=" & $policyEnvironmentContractSchema & " wm_policy=" &
    policyEnvironmentContractName & " names=" & sophiaNames.join(",") & " legacy=" &
    legacyNames.join(",") & " precedence=" & policyEnvironmentContractPrecedence
