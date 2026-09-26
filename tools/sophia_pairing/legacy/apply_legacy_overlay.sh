#!/bin/sh
# Install Hagia's legacy Sophia pairing into an ISOLATED scratch Sophia checkout.
# Usage: apply_legacy_overlay.sh SOPHIA_SCRATCH_CHECKOUT
# The result is "Sophia <commit> + Hagia legacy overlay <manifest sha256>", not
# exact Sophia source. Never point this at a working tree anyone edits.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target=$1
if [ -n "$(git -C "$target" status --porcelain)" ]; then
    echo "scratch checkout is not clean: $target" >&2
    exit 1
fi
install_file() { # source (relative to legacy/), destination (relative to checkout)
    if [ -e "$target/$2" ]; then
        echo "overlay target already exists: $2" >&2
        exit 1
    fi
    cp "$here/$1" "$target/$2"
}
mount_after_end() { # file (relative to checkout), anchor that must occur once, lines
    file=$target/$1
    [ "$(grep -Fxc -- "$2" "$file")" = 1 ] || {
        echo "overlay anchor missing or ambiguous in $1: $2" >&2
        exit 1
    }
    printf '%s\n' "$3" >>"$file"
}
install_file runtime/pointer_focus_hagia.rs crates/sophia-runtime/tests/support/pointer_focus_hagia.rs
install_file runtime/presentation_hagia.rs crates/sophia-runtime/tests/support/presentation_hagia.rs
mount_after_end crates/sophia-runtime/tests/policy_transport.rs \
    'fn pointer_focus_is_sent_only_to_a_peer_that_negotiated_it() {' \
    '#[path = "support/pointer_focus_hagia.rs"]
mod pointer_focus_hagia;
#[path = "support/presentation_hagia.rs"]
mod presentation_hagia;'
install_file session/delegated_policy.rs crates/sophia-session/tests/support/delegated_policy.rs
install_file session/pregraphics_activation.rs crates/sophia-session/tests/support/hagia_pregraphics_activation.rs
mount_after_end crates/sophia-session/tests/support/live_session/profile_preparation_tests.rs \
    'fn profile_restart_reattaches_the_exact_key_under_a_fresh_epoch() {' \
    '#[path = "../delegated_policy.rs"]
mod delegated_policy;
#[path = "../hagia_pregraphics_activation.rs"]
mod hagia_pregraphics_activation;'
install_file session/hagia_launch_origin.rs crates/sophia-session/tests/support/hagia_launch_origin.rs
mount_after_end crates/sophia-session/tests/support/launch_origin_socket.rs \
    'trait OriginPolicy {' \
    '#[path = "hagia_launch_origin.rs"]
mod hagia_launch_origin;'
(cd "$here" && find runtime session -type f -name '*.rs' | sort | xargs sha256sum) >"$target/.hagia-legacy-overlay.sha256"
echo "hagia_legacy_overlay applied base=$(git -C "$target" rev-parse HEAD) manifest_sha256=$(sha256sum "$target/.hagia-legacy-overlay.sha256" | cut -d' ' -f1)"
