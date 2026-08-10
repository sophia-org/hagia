#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 TRACE.ndjson" >&2
    exit 2
fi

trace=$1
jq -s -r '
  def checked_string($field):
    .[$field] as $value
    | if ($value | type) != "string" or
         ($value | test("^[A-Za-z0-9_-]+$") | not)
      then error("invalid trace string field " + $field)
      else ($value | @json)
      end;
  def checked_number($field):
    .[$field] as $value
    | if ($value | type) != "number" or $value < 0 or $value != ($value | floor)
      then error("invalid trace number field " + $field)
      else ($value | tostring)
      end;
  def state:
    .state
    | "State(" +
      ([checked_string("active"), checked_number("activeGeneration"),
        checked_string("candidate"), checked_number("candidateGeneration"),
        checked_number("latestGeneration"), checked_number("preparedCount"),
        checked_number("locallyActivatedCount"),
        checked_number("rollbackPendingCount"), checked_string("phase"),
        checked_number("rejectedCount"), checked_number("promotedCount")]
       | join(", ")) + ")";
  def event:
    .name as $name
    | if $name == "BeginProfile" then
        "name |-> \"BeginProfile\", generation |-> " +
        checked_number("generation") + ", digest |-> " +
        checked_string("digest")
      elif $name == "PrepareAuthority" or $name == "ActivateAuthority" then
        "name |-> " + checked_string("name") + ", authority |-> " +
        checked_string("authority")
      elif $name == "RequestActivation" then
        "name |-> \"RequestActivation\""
      else
        error("unsupported profile trace event " + ($name | tostring))
      end;
  map(
    if .tag != "trace" or (.event | type) != "object" then
      error("invalid profile trace envelope")
    else
      .event
    end
  ) as $events
  | if ($events | length) == 0 then error("profile trace is empty") else . end
  | "---------------- MODULE TraceData ----------------\n" +
    "State(a, ag, c, cg, lg, p, la, rb, ph, r, pr) ==\n" +
    "    [active |-> a, activeGeneration |-> ag,\n" +
    "     candidate |-> c, candidateGeneration |-> cg, latestGeneration |-> lg,\n" +
    "     preparedCount |-> p, locallyActivatedCount |-> la,\n" +
    "     rollbackPendingCount |-> rb, phase |-> ph,\n" +
    "     rejectedCount |-> r, promotedCount |-> pr]\n\n" +
    "TraceLog == <<\n" +
    ($events
      | map("  [event |-> [" + event + ", state |-> " + state + "]]" )
      | join(",\n")) +
    "\n>>\n\n====================================================="
' "$trace"
