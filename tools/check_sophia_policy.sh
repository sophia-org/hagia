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
    -o:"$build_dir/tsophia-wm-v1" tests/tsophia_wm_v1.nim
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
# These tests build a session config without naming a desktop profile, so
# discovery reaches whatever is in the developer's own XDG config and fails on
# a shortcut that a bare test session has no capability for. Give the command
# an empty config root so it sees compiled defaults, the way Sophia isolates
# its own workspace tests. The Hagia binary under test is still the real build.
mkdir -p "$build_dir/config"
chmod 700 "$build_dir/config"
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-session --features atomic-scanout-live \
    hagia_pregraphics_profile_admission_

# Pointer focus runs the real compiled Hagia over a socket: it negotiates with
# the setting off and on, sends Engine-authored empty-output and window-hover
# observations on the actual wire, and drives stage/commit plus timeout retry.
# Only owned offline processes, so it belongs in the ordinary gate.
cargo test --offline -q -p sophia-runtime --test policy_transport \
    hagia_pointer_focus_ -- --list >"$build_dir/pointer-tests"
for test in \
    hagia_pointer_focus_real_socket_commits_rejects_and_retries \
    hagia_pointer_focus_old_server_reports_the_setting_before_admission
do
    grep -Fqx "pointer_focus_hagia::$test: test" "$build_dir/pointer-tests" || {
        echo "missing paired pointer-focus test: $test" >&2
        exit 1
    }
done
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-runtime --test policy_transport \
    hagia_pointer_focus_

# Overview stays WM policy; the paired fixture admits generic presentation
# records over the real transport. Actual-frame input authority is checked by
# Sophia's session controls, not by these synthetic presentation receipts.
cargo test --offline -q -p sophia-runtime --test policy_transport \
    presentation_hagia -- --list >"$build_dir/presentation-tests"
for test in \
    hagia_without_presentation_actions_keeps_ordinary_policy_available \
    hagia_overview_publishes_generic_records_and_accepts_exact_targeted_actions \
    hagia_overview_timeout_retains_the_committed_publication \
    hagia_overview_revoked_receipt_closes_on_the_next_cycle \
    hagia_overview_reconnect_starts_closed_and_reuses_no_authority
do
    grep -Fqx "presentation_hagia::$test: test" "$build_dir/presentation-tests" || {
        echo "missing paired presentation test: $test" >&2
        exit 1
    }
done
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-runtime --test policy_transport \
    presentation_hagia

# Launch origin over a real X socket: the child connects, its ancestry is
# resolved by Sophia, and the freshly built Hagia places it where its launcher
# lives. A filter that matches nothing exits zero, so the paired case is named
# in a listing first; without that this step could pass while covering nothing.
origin_listing=$(XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-session --features native-session --lib \
    launch_origin_socket -- --list)
case "$origin_listing" in
    *hagia_real_x_child_origin_survives_monitor_switch_and_rejection*) ;;
    *)
        echo "shared gate lost the paired launch-origin case" >&2
        exit 1
        ;;
esac
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$build_dir/hagia" \
    cargo test --offline -q -p sophia-session --features native-session --lib \
    launch_origin_socket

printf '%s\n' \
    'hagia_policy_behavior_corpus schema=4 status=complete revision=3 scenarios=11 sequential=true action=true timeout_recovery=true stale_recovery=true invalid_recovery=true reconnect_restart=true preserved_commit=true'
