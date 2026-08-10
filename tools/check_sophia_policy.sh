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
    -o:"$build_dir/tpolicy-model" tests/tpolicy_model.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tfoundation" tests/tfoundation.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tprofile-handoff" tests/tprofile_handoff.nim
nim c --hints:off --path:src --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/hagia-policy-proof" src/hagia_policy_proof.nim
nim c --hints:off --path:src --nimcache:"$build_dir/nimcache-hagia" \
    -o:"$build_dir/hagia" src/hagia.nim
cd "$SOPHIA_STACK_ROOT"
cargo run --offline -q -p sophia-runtime --example policy_c_conformance_host -- \
    "$build_dir/hagia-policy-proof" "$build_dir/session" all
SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-cli --features atomic-scanout-live \
    hagia_pregraphics_profile_admission_activates_every_owner

printf '%s\n' \
    'hagia_policy_behavior_corpus schema=3 status=complete revision=3 scenarios=11 sequential=true action=true timeout_recovery=true stale_recovery=true invalid_recovery=true'
