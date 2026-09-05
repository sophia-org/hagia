#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

alloy_bin=${HAGIA_ALLOY:-alloy}
z3_bin=${HAGIA_Z3:-z3}

if [ "$($alloy_bin version 2>/dev/null)" != "6.2.0" ]; then
    echo "Hagia foundation models require Alloy 6.2.0" >&2
    exit 1
fi
# Known-good Z3 versions: the expected-results file was produced under 4.16.0
# and verified byte-identical under 5.1.0. A new version is admitted by
# checking `z3 validation/z3/entities.smt2` against the expected file and
# adding it here, not by loosening this match to a wildcard.
case "$($z3_bin --version 2>/dev/null)" in
    "Z3 version 4.16.0"* | "Z3 version 5.1.0"*) ;;
    *)
        echo "Hagia foundation models require Z3 4.16.0 or 5.1.0" >&2
        exit 1
        ;;
esac

run_alloy() {
    command=$1
    output=$work/alloy-$command
    log=$work/alloy-$command.log
    "$alloy_bin" exec -q -s sat4j -y 20 -c "$command" -t json \
        -o "$output" "$root/validation/alloy/entities.als" >"$log" 2>&1 || {
        sed -n '1,160p' "$log" >&2
        exit 1
    }
    if [ ! -f "$output/receipt.json" ]; then
        echo "Alloy emitted no receipt for $command" >&2
        exit 1
    fi
    solutions=$(find "$output" -name '*-solution-0.json' -type f | wc -l)
    if [ "$solutions" -ne 0 ]; then
        echo "Alloy found a counterexample for $command" >&2
        exit 1
    fi
    printf '%s\n' "alloy unsat: $command"
}

run_alloy EntityOwnership
run_alloy MembershipNonempty
run_alloy NoDanglingReferences
run_alloy UniqueIds
run_alloy NoStaleDynamicWorkspace
run_alloy ScratchpadsCannotBecomeViews
run_alloy ScratchpadsRetainRestoreMembership
run_alloy ParentGraphIsAcyclic

actual=$work/entities.actual
"$z3_bin" "$root/validation/z3/entities.smt2" >"$actual"
if ! diff -u "$root/validation/z3/entities.expected" "$actual"; then
    echo "Z3 entity invariant results changed" >&2
    exit 1
fi
printf '%s\n' 'z3 expected results: entities'
