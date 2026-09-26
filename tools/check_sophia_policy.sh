#!/bin/sh
set -eu

if [ "${SOPHIA_ROOT:-}" = "" ]; then
    echo "SOPHIA_ROOT must name a Sophia checkout" >&2
    exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cd "$root"
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tninep" tests/tninep.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/twm-files" tests/twm_files.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/twm-file-bodies" tests/twm_file_bodies.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tsophia-wm-v1" tests/tsophia_wm_v1.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tsnapshot-identity" tests/tsnapshot_identity.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/twm-file-arrays" tests/twm_file_arrays.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/twm-file-projection" tests/twm_file_projection.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/twm-presentation" tests/twm_presentation.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/toverview" tests/toverview.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/toverview-adapter" tests/toverview_adapter.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/ttab-trees" tests/ttab_trees.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tedge-maximized" tests/tedge_maximized.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tgap-layout" tests/tgap_layout.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tcolumn-sizing" tests/tcolumn_sizing.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tpolicy-model" tests/tpolicy_model.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tfoundation" tests/tfoundation.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tscroller-ops" tests/tscroller_ops.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tscroller-navigation" tests/tscroller_navigation.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tprofile-handoff" tests/tprofile_handoff.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tpolicy-wire" tests/tpolicy_wire.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tfile-wire" tests/tfile_wire.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/tpolicy-endpoint" tests/tpolicy_endpoint.nim
nim c -r --hints:off --path:src --nimcache:tests/nimcache \
    -o:"$build_dir/twm-file-client" tests/twm_file_client.nim
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
# The size vocabulary reaches the CLI through the same validator, so the CLI
# path covers it too rather than only the in-process tests above.
printf 'schema 1\npolicy { default-column-width { fixed 99999; } }\n' \
    >"$build_dir/invalid-size.kdl"
chmod 600 "$build_dir/invalid-size.kdl"
if "$build_dir/hagia" config check --config="$build_dir/invalid-size.kdl"; then
    echo "Hagia config check accepted an out-of-range column size" >&2
    exit 1
fi
printf 'schema 1\npolicy { column-width-presets 33 50 67; }\n' \
    >"$build_dir/retired-size.kdl"
chmod 600 "$build_dir/retired-size.kdl"
if "$build_dir/hagia" config check --config="$build_dir/retired-size.kdl"; then
    echo "Hagia config check accepted a retired policy spelling" >&2
    exit 1
fi
cd "$SOPHIA_ROOT"
cargo run --offline -q -p sophia-runtime --example policy_c_conformance_host -- \
    "$build_dir/hagia-policy-proof" "$build_dir/session" all
cargo run --offline -q -p sophia-runtime --example policy_c_conformance_host -- \
    "$build_dir/hagia-policy-proof" "$build_dir/session-restart" restart
# Hagia-specific interoperability cases (pregraphics profile admission,
# pointer focus, presentation, launch origin) moved to the opt-in
# tools/sophia_pairing/legacy overlay so Sophia's own tree stays WM-neutral.

printf '%s\n' \
    'hagia_policy_behavior_corpus schema=4 status=complete revision=3 scenarios=11 sequential=true action=true timeout_recovery=true stale_recovery=true invalid_recovery=true reconnect_restart=true preserved_commit=true'
