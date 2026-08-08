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
nim c -r --hints:off --path:src --nimcache:tests/nimcache tests/tsophia_wm_v1.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache tests/tpolicy_model.nim
nim c --hints:off --path:src --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/hagia-policy-proof" src/hagia_policy_proof.nim
cd "$SOPHIA_STACK_ROOT"
cargo run --offline -q -p sophia-runtime --example policy_c_conformance_host -- \
    "$build_dir/hagia-policy-proof" "$build_dir/session"
