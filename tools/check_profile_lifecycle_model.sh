#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
spec=$root/.specula-output/spec
trace=$root/.specula-output/traces/startup.ndjson
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

for command in java jq timeout; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Hagia profile lifecycle verification requires $command" >&2
        exit 1
    fi
done

tla_jar=${HAGIA_TLA2TOOLS_JAR:-}
if [ -z "$tla_jar" ]; then
    specula_root=${HAGIA_SPECULA_ROOT:-${HOME:-}/src/Specula}
    tla_jar=$specula_root/lib/tla2tools.jar
fi
if [ ! -f "$tla_jar" ]; then
    echo "set HAGIA_TLA2TOOLS_JAR to the pinned tla2tools.jar" >&2
    exit 1
fi

"$root/tools/render_profile_trace_tla.sh" "$trace" >"$work/TraceData.tla"
if ! diff -u "$spec/TraceData.tla" "$work/TraceData.tla"; then
    echo "startup.ndjson and TraceData.tla differ" >&2
    exit 1
fi

workers=${HAGIA_TLC_WORKERS:-auto}
run_tlc() {
    name=$1
    config=$2
    module=$3
    log=$work/$name.out
    metadata=$work/$name-states
    if ! timeout 30m java -XX:+UseParallelGC -cp "$tla_jar" tlc2.TLC \
        -cleanup -deadlock -workers "$workers" -metadir "$metadata" \
        -config "$config" "$module" >"$log" 2>&1; then
        sed -n '1,260p' "$log" >&2
        exit 1
    fi
    if ! grep -Fq "Model checking completed. No error has been found." "$log"; then
        sed -n '1,260p' "$log" >&2
        exit 1
    fi
    states=$(grep -E '[0-9]+ states generated, [0-9]+ distinct states found' "$log" | tail -n 1)
    printf '%s\n' "tla+ pass: $name: $states"
}

cd "$spec"
run_tlc startup-trace Trace.cfg Trace
run_tlc lifecycle MC.cfg MC
run_tlc partial-prepare MC_hunt_partial_prepare.cfg MC
run_tlc stale-completion MC_hunt_stale_completion.cfg MC
