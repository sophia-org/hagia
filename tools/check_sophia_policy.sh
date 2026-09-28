#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/hagia-policy.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cd "$root"
# Release dependency custody is a separate bound build. This contributor gate
# uses the developer's Nim toolchain and private per-run output/cache paths.
unset DISPLAY WAYLAND_DISPLAY
nice -n 19 make -C vendor/sophia-desktop-sdk/source -j2 WITH_IPC=0 \
    BUILD="$build_dir/c-sdk" check
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tdesktop-sdk" tests/tdesktop_sdk.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tninep" tests/tninep.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/twm-files" tests/twm_files.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/twm-file-bodies" tests/twm_file_bodies.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tsophia-wm-v1" tests/tsophia_wm_v1.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tsnapshot-identity" tests/tsnapshot_identity.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/twm-file-arrays" tests/twm_file_arrays.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/twm-file-projection" tests/twm_file_projection.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/twm-presentation" tests/twm_presentation.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/toverview" tests/toverview.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/toverview-adapter" tests/toverview_adapter.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/ttab-trees" tests/ttab_trees.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tedge-maximized" tests/tedge_maximized.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tgap-layout" tests/tgap_layout.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tcolumn-sizing" tests/tcolumn_sizing.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tpolicy-model" tests/tpolicy_model.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tfoundation" tests/tfoundation.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tscroller-ops" tests/tscroller_ops.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tscroller-navigation" tests/tscroller_navigation.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tprofile-handoff" tests/tprofile_handoff.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tpolicy-wire" tests/tpolicy_wire.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tfile-wire" tests/tfile_wire.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tpolicy-endpoint" tests/tpolicy_endpoint.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tpolicy-environment" tests/tpolicy_environment.nim
nice -n 19 nim c -r --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/twm-file-client" tests/twm_file_client.nim
nice -n 19 nim c --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache-hagia" \
    -o:"$build_dir/hagia" src/hagia.nim
# Stop signals are exercised against the binary itself, not a linked loop.
nice -n 19 nim c --hints:off --path:src --parallelBuild:2 --nimcache:"$build_dir/nimcache" \
    -o:"$build_dir/tgraceful-stop" tests/tgraceful_stop.nim
HAGIA_BINARY="$build_dir/hagia" nice -n 19 "$build_dir/tgraceful-stop"
# The environment contract probe is what an installer matches before trusting
# a binary with the generic names; its exact line is part of the contract.
contract=$("$build_dir/hagia" config check-environment-contract)
expected_contract='hagia_environment_contract schema=1 wm_policy=sophia-wm-policy-v1 names=SOPHIA_WM_POLICY_CHECKPOINT,SOPHIA_WM_POLICY_CANDIDATE,SOPHIA_WM_POLICY_PROFILE_ACTIVATION legacy=HAGIA_POLICY_CHECKPOINT,HAGIA_POLICY_CANDIDATE,HAGIA_POLICY_PROFILE_ACTIVATION precedence=presence'
if [ "$contract" != "$expected_contract" ]; then
    echo "Hagia environment contract probe changed: $contract" >&2
    exit 1
fi
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
printf '%s\n' 'hagia_policy_tests schema=1 status=pass wire=9p2000.L scope=local_sdk_and_policy'
