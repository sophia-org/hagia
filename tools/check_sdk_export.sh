#!/bin/sh
# Optional real-export proof. It supplies admission and scripted outcomes;
# it does not launch a desktop or claim physical presentation.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SOPHIA_ROOT:?must name an explicit Sophia checkout}"
: "${CARGO_TARGET_DIR:?must name a private target outside both source trees}"
: "${SOPHIA_WM_FILE_PEER_EVIDENCE:?must name a fresh evidence directory}"
case "$SOPHIA_ROOT:$CARGO_TARGET_DIR:$SOPHIA_WM_FILE_PEER_EVIDENCE" in
 /*:/*:/*) ;;
 *) echo 'export proof paths must be absolute' >&2; exit 2;;
esac
# Resolve existing parents before comparing, including symlinks.
source=$(realpath "$SOPHIA_ROOT")
target=$(realpath -m "$CARGO_TARGET_DIR")
case "$target/" in
 "$source/"*|"$root/"*) echo 'target must be outside both source trees' >&2; exit 2;;
esac
if [ -e "$SOPHIA_WM_FILE_PEER_EVIDENCE" ]; then
    echo 'export evidence directory must be new' >&2
    exit 2
fi
unset DISPLAY WAYLAND_DISPLAY
build=$(mktemp -d "${TMPDIR:-/tmp}/hagia-export.XXXXXXXX")
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
cd "$root"
timeout -s KILL 300 nim c --hints:off --path:src \
    --nimcache:"$build/nimcache" -o:"$build/wm-sdk-session-peer" tests/wm_sdk_session_peer.nim
export SOPHIA_WM_FILE_PEER="$build/wm-sdk-session-peer"
SOPHIA_WM_FILE_PEER_SHA256=$(sha256sum "$SOPHIA_WM_FILE_PEER" | cut -d ' ' -f1)
export SOPHIA_WM_FILE_PEER_SHA256
mkdir -m 700 "$SOPHIA_WM_FILE_PEER_EVIDENCE"
cd "$source"
# Refuse a checkout lacking the tests instead of allowing a zero-test success.
tests=$(timeout -s KILL 600 cargo test \
    --offline --locked -p sophia-session --all-features --lib \
    independent_nim_supplied_stream -- --ignored --list)
for name in startup cycle; do
    if ! printf '%s\n' "$tests" | grep -q "independent_nim_supplied_stream_${name}: test$"; then
        echo "missing production export test: $name" >&2
        exit 1
    fi
done
timeout -s KILL 600 cargo test --offline --locked \
    -p sophia-session --all-features --lib independent_nim_supplied_stream \
    -- --ignored --test-threads=1 --nocapture
