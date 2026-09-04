#!/bin/sh
# Rebuild Hagia and ask the running instance to hand over to it.
#
# Hagia does not replace itself. It saves its checkpoint and exits, and Sophia's
# supervisor starts the binary again from the same path; the new process
# reconciles the checkpoint against a complete snapshot. That is why this script
# installs over the path the running process was launched from, and why it does
# nothing that needs a live session's cooperation beyond one signal.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

pid=${1:-}
if [ -z "$pid" ]; then
    pid=$(pgrep -x hagia | head -n 1 || true)
fi
if [ -z "$pid" ]; then
    echo "live-reload: no running hagia found" >&2
    echo "  pass a pid explicitly: tools/live_reload.sh PID" >&2
    exit 1
fi
if [ ! -d "/proc/$pid" ]; then
    echo "live-reload: no such process: $pid" >&2
    exit 1
fi

target=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
if [ -z "$target" ]; then
    echo "live-reload: cannot read /proc/$pid/exe; run as the session owner" >&2
    exit 1
fi
case "$target" in
*" (deleted)") target=${target%" (deleted)"} ;;
esac
if [ ! -w "$(dirname "$target")" ]; then
    echo "live-reload: $(dirname "$target") is not writable" >&2
    echo "  an installed session needs the install step, not a live reload" >&2
    exit 1
fi

# A running executable cannot be written in place, so build beside it and
# rename over it. Rename swaps the inode, which the kernel allows.
staged="$target.reload.$$"
trap 'rm -f -- "$staged"' EXIT HUP INT TERM
nim c -d:release --hints:off --path:src --nimcache:tests/nimcache -o:"$staged" src/hagia.nim
chmod 755 "$staged"
mv -f "$staged" "$target"
trap - EXIT HUP INT TERM

kill -HUP "$pid"
printf '%s\n' "live-reload: installed $target and signalled pid $pid"

# The request is honoured at the next committed cycle, because that is the point
# where this generation's checkpoint is durable. An idle desktop produces no
# cycle, so nothing happens until something moves.
waited=0
while [ "$waited" -lt 100 ]; do
    if [ ! -d "/proc/$pid" ]; then
        printf '%s\n' "live-reload: pid $pid handed over; Sophia restarts from $target"
        exit 0
    fi
    sleep 0.1
    waited=$((waited + 1))
done
echo "live-reload: pid $pid is still running after 10s" >&2
echo "  the request lands on the next committed cycle; move a window to force one" >&2
exit 1
