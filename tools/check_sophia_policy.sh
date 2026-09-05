#!/bin/sh
set -eu

if [ "${SOPHIA_STACK_ROOT:-}" = "" ]; then
    echo "SOPHIA_STACK_ROOT must name a Sophia Stack checkout" >&2
    exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cd "$root"
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tsophia-wm-v1" tests/tsophia_wm_v1.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/ttab-trees" tests/ttab_trees.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tpolicy-model" tests/tpolicy_model.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tfoundation" tests/tfoundation.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tprofile-handoff" tests/tprofile_handoff.nim
nim c --hints:off --path:src --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/hagia-policy-proof" src/hagia_policy_proof.nim
nim c --hints:off --path:src --nimcache:"$build_dir/nimcache-hagia" \
    -o:"$build_dir/hagia" src/hagia.nim
# The CLI must validate the same policy values as runtime preparation.
"$build_dir/hagia" config check --config="$root/examples/config/default.kdl"
printf 'schema 1\npolicy { outer-gap 513; }\n' >"$build_dir/invalid-policy.kdl"
chmod 600 "$build_dir/invalid-policy.kdl"
if "$build_dir/hagia" config check --config="$build_dir/invalid-policy.kdl"; then
    echo "Hagia config check accepted invalid policy geometry" >&2
    exit 1
fi
cd "$SOPHIA_STACK_ROOT"
cargo run --offline -q -p sophia-runtime --example policy_c_conformance_host -- \
    "$build_dir/hagia-policy-proof" "$build_dir/session" all
cargo run --offline -q -p sophia-runtime --example policy_c_conformance_host -- \
    "$build_dir/hagia-policy-proof" "$build_dir/session-restart" restart
SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-session --features atomic-scanout-live \
    hagia_pregraphics_profile_admission_

printf '%s\n' \
    'hagia_policy_behavior_corpus schema=4 status=complete revision=3 scenarios=11 sequential=true action=true timeout_recovery=true stale_recovery=true invalid_recovery=true reconnect_restart=true preserved_commit=true'
