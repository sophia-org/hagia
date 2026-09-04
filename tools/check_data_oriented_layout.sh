#!/bin/sh
# Enforces the data/logic separation mandated by docs/data-oriented-design.md
# and docs/style-guide.md. This gate exists because the separation was declared
# once and then eroded: records drifted into the modules that consumed them
# until twenty of twenty-six modules mixed data with logic.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
violations=$work/violations
: >"$violations"

# A module outside src/types declares no public record. Three kinds of
# declaration are admitted, each for a stated reason:
#
#   * an error type and the enum that classifies it, which belong to the module
#     that raises them;
#   * a closure vtable, which is injected behavior and not passive data; and
#   * an encapsulated state machine whose fields are private on purpose, where
#     exporting them to satisfy a file-location rule would trade a real
#     authority boundary for a cosmetic one.
#
# Adding a name here must be a deliberate act with a reason, not a way to make
# the gate quiet.
allowed_public_type() {
    case "$1" in
    *Error) return 0 ;;
    src/sophia/wm_v1.nim:PolicyProtocolErrorKind) return 0 ;;
    src/runtime/effect_executor.nim:RuntimeEffectHandler) return 0 ;;
    src/runtime/effect_executor.nim:RuntimeEffectExecutor) return 0 ;;
    src/sophia/policy_adapter.nim:PolicyAdapter) return 0 ;;
    src/sophia/policy_session.nim:PolicySession) return 0 ;;
    esac
    return 1
}

# A module in src/types declares data only, and is a leaf. The single admitted
# routine exception is the identity interop Nim requires for distinct IDs:
# `==`, `$`, and `hash` in types/core.nim. The import rule keeps data from ever
# depending on behavior.
for file in src/types/*.nim; do
    awk -v file="$file" '
        /^(proc|func|method|converter|iterator|template|macro) / {
            name = $2
            sub(/[*(\[].*$/, "", name)
            if (file == "src/types/core.nim" &&
                (name == "`==`" || name == "`$`" || name == "hash")) next
            printf "%s:%d declares routine %s; a types module holds data only\n", \
                file, NR, name
        }
        /^import / {
            line = $0
            sub(/^import[ \t]+/, "", line)
            if (line ~ /^std\//) next
            if (line ~ /^\.\/[A-Za-z_[]/) next
            printf "%s:%d imports %s; a types module may import only std and its siblings\n", \
                file, NR, line
        }
    ' "$file" >>"$violations"
done

# Public record declarations outside the types layer.
for file in $(find src -name '*.nim' -not -path 'src/types/*' | sort); do
    awk -v file="$file" '
        /^type[ \t]*$/ { section = 1; next }
        /^type[ \t]+[A-Z]/ {
            name = $2
            if (name ~ /\*/) { sub(/\*.*$/, "", name); printf "%s\t%d\t%s\n", file, NR, name }
            section = 0
            next
        }
        /^[^ \t]/ { section = 0 }
        section && /^  [A-Z][A-Za-z0-9_]*\*/ {
            name = $1
            sub(/\*.*$/, "", name)
            printf "%s\t%d\t%s\n", file, NR, name
        }
    ' "$file"
done >"$work/public-types"

while IFS="$(printf '\t')" read -r file line name; do
    [ -n "${name:-}" ] || continue
    if ! allowed_public_type "$file:$name" && ! allowed_public_type "$name"; then
        printf '%s:%d declares public record %s outside src/types\n' \
            "$file" "$line" "$name" >>"$violations"
    fi
done <"$work/public-types"

if [ -s "$violations" ]; then
    while IFS= read -r line; do
        echo "data-oriented layout violation: $line" >&2
    done <"$violations"
    echo "" >&2
    echo "Records are data. Move the declaration into src/types and leave the" >&2
    echo "procedures behind, or state the exception in tools/$(basename "$0")." >&2
    exit 1
fi

modules=$(find src/types -name '*.nim' | wc -l | tr -d ' ')
records=$(cat src/types/*.nim | grep -cE '^  [A-Za-z_][A-Za-z0-9_]*\*' || true)
printf '%s\n' \
    "hagia_data_oriented_layout types_modules=$modules public_records=$records data_logic_separation=enforced"
