#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${SOPHIA_ROOT:?supply the clean pinned Sophia checkout}"
: "${HAGIA_PAIRING_BIN:?supply the frozen normal Hagia executable}"
: "${HAGIA_PAIRING_SHA256:?supply its SHA256}"
: "${HAGIA_PAIRING_EVIDENCE:?supply a fresh absolute evidence directory}"
: "${HAGIA_PAIRING_TARGET:?supply an exclusive absolute Cargo target directory}"
exec nice -n 19 env CARGO_BUILD_JOBS=2 cargo +1.96.1 run --offline --locked -j 2 \
  --manifest-path "$repo/tools/sophia_pairing/runner/Cargo.toml" \
  --target-dir "${HAGIA_PAIRING_RUNNER_TARGET:-$repo/.artifacts/pairing-runner}" -- \
  --sophia-root="$SOPHIA_ROOT" --hagia-bin="$HAGIA_PAIRING_BIN" \
  --hagia-sha256="$HAGIA_PAIRING_SHA256" --output="$HAGIA_PAIRING_EVIDENCE" \
  --target-dir="$HAGIA_PAIRING_TARGET" --timeout="${HAGIA_PAIRING_TIMEOUT:-3600}"
