#!/bin/sh
# Hagia's legacy Sophia pairing, moved out of tools/check_sophia_policy.sh with
# its tests. Usage: check_legacy_pairing.sh OVERLAID_SOPHIA_CHECKOUT HAGIA_BINARY
# The checkout must already carry apply_legacy_overlay.sh; the caller owns the
# isolation (device-hidden sandbox, nice, CARGO_BUILD_JOBS, private
# CARGO_TARGET_DIR). Commands, filters and guards are unchanged from the
# original gate except that the pregraphics filter is now listed first too.
set -eu
checkout=$1
hagia=$2
[ -f "$checkout/.hagia-legacy-overlay.sha256" ] || {
    echo "checkout lacks the Hagia legacy overlay" >&2
    exit 1
}
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
cd "$checkout"
# These tests build a session config without naming a desktop profile, so
# discovery reaches whatever is in the developer's own XDG config and fails on
# a shortcut that a bare test session has no capability for. Give the command
# an empty config root so it sees compiled defaults, the way Sophia isolates
# its own workspace tests. The Hagia binary under test is still the real build.
mkdir -p "$build_dir/config"
chmod 700 "$build_dir/config"
# A filter that matches nothing exits zero, so the moved cases are named first.
cargo test --offline -q -p sophia-session --features atomic-scanout-live --lib \
    hagia_pregraphics_profile_admission_ -- --list >"$build_dir/pregraphics-tests"
for test in \
    delegated_policy::hagia_pregraphics_profile_admission_rejects_invalid_policy_values \
    hagia_pregraphics_activation::hagia_pregraphics_profile_admission_activates_every_owner
do
    grep -Fq "$test: test" "$build_dir/pregraphics-tests" || {
        echo "missing paired pregraphics test: $test" >&2
        exit 1
    }
done
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$hagia" \
    cargo test --offline -q -p sophia-session --features atomic-scanout-live \
    hagia_pregraphics_profile_admission_

# Pointer focus runs the real compiled Hagia over a socket: it negotiates with
# the setting off and on, sends Engine-authored empty-output and window-hover
# observations on the actual wire, and drives stage/commit plus timeout retry.
# Only owned offline processes.
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
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$hagia" \
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
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$hagia" \
    cargo test --offline -q -p sophia-runtime --test policy_transport \
    presentation_hagia

# Launch origin over a real X socket: the child connects, its ancestry is
# resolved by Sophia, and the freshly built Hagia places it where its launcher
# lives. A filter that matches nothing exits zero, so the paired case is named
# in a listing first; without that this step could pass while covering nothing.
origin_listing=$(XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$hagia" \
    cargo test --offline -q -p sophia-session --features native-session --lib \
    launch_origin_socket -- --list)
case "$origin_listing" in
    *hagia_launch_origin::hagia_real_x_child_origin_survives_monitor_switch_and_rejection*) ;;
    *)
        echo "legacy pairing lost the launch-origin case" >&2
        exit 1
        ;;
esac
XDG_CONFIG_HOME="$build_dir/config" SOPHIA_HAGIA_BIN="$hagia" \
    cargo test --offline -q -p sophia-session --features native-session --lib \
    launch_origin_socket

printf '%s\n' 'hagia_legacy_pairing status=complete pregraphics=2 pointer_focus=2 presentation=5 launch_origin=1'
