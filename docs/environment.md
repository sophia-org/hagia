# Environment

Every environment variable Hagia reads, what it does, and who sets it. Four of
them are set for you by Sophia in an installed session; the rest are yours, and
most exist for development and debugging.

## Set by Sophia in an installed session

You do not set these by hand for a real desktop. Sophia's session passes them
when it launches Hagia into its protection domain
(`crates/sophia-session/src/live_session/wm/public_policy.rs`). They are listed
because you will see them in a process listing and because standalone
development sometimes needs one.

| Variable | Meaning |
| --- | --- |
| `SOPHIA_WM_SOCKET` | Path to the session-owned policy socket. Hagia connects; it never creates or owns this endpoint. Required — `--socket=PATH` is the standalone equivalent. |
| `HAGIA_POLICY_CANDIDATE` | Path to the policy authority slice Sophia has already staged and validated. When set, it replaces profile discovery entirely, and passing `--config` as well is refused. |
| `HAGIA_POLICY_CHECKPOINT` | Path to the private policy checkpoint. Written atomically after every committed cycle, owner-only, bounded. Unset disables checkpointing, which also disables `SIGHUP` reload. |
| `HAGIA_POLICY_PROFILE_ACTIVATION` | Empty runs an ordinary session. `required` runs the profile-activated path and demands `HAGIA_POLICY_CANDIDATE`. Any other value is a startup error. |

## Configuration discovery

| Variable | Default | Meaning |
| --- | --- | --- |
| `XDG_CONFIG_HOME` | `~/.config` | Root of profile discovery. The search order is `--config=PATH` (absolute), then `$XDG_CONFIG_HOME/hagia/config.kdl`, then `~/.config/hagia/config.kdl`, then `/etc/hagia/config.kdl`, then the compiled fallback that `examples/config/default.kdl` mirrors exactly. `hagia config init` seeds the user location with that default — once, never overwriting. |

## Observability

| Variable | Default | Meaning |
| --- | --- | --- |
| `HAGIA_LOG_LEVEL` | `info` | `debug`, `info`, `warn`/`warning`, or `error`/`failure`. Unrecognised values fall back to `info`. Goes to stdout, which in a supervised session belongs to Sophia's capture. |
| `HAGIA_EVIDENCE_NDJSON` | unset, off | Absolute path to the structured evidence stream. A relative path is a startup error. Created owner-only, rotates at 1 MiB keeping four files. Schema 2 records name the event and carry a sequence number. |

## Development and debugging

| Variable | Default | Meaning |
| --- | --- | --- |
| `HAGIA_POLICY_DUMP` | unset | Where `SIGUSR1` writes the committed model. Read-only; the dump reuses the checkpoint format, so `hagia dump-checkpoint` prints it. Without this, a `SIGUSR1` is logged and refused. |
| `HAGIA_POLICY_TRACE` | unset | Append a JSONL trace of every `(snapshot, request, transaction)` the session answers. Replay it offline with `hagia replay`. Recording happens before the reduction, so a trace carries inputs rather than conclusions. |

### Fault injection

Deterministic crash injection for recovery testing, used by the conformance
corpus. Inert unless both `_AFTER` and `_MARKER` are set, and the marker makes
one supervised replacement the maximum effect.

| Variable | Default | Meaning |
| --- | --- | --- |
| `HAGIA_POLICY_FAULT_AFTER` | unset | Phase to exit at: `configuration_installed`, `snapshot_received`, `projection_prepared`, `outcome_received`, or `checkpoint_saved`. |
| `HAGIA_POLICY_FAULT_MARKER` | unset | Marker file path. If it already exists the hook is spent, so a supervisor cannot be driven into a crash loop. |
| `HAGIA_POLICY_FAULT_OCCURRENCE` | `1` | Which arrival at the phase actually exits. |
| `HAGIA_POLICY_FAULT_DELAY_MSEC` | `0` | Sleep before exiting, for racing the supervisor deliberately. |

The process exits with code 70 and logs `fault_injected`.

## Signals

Not environment, but the same surface. See `README.md`.

| Signal | Effect |
| --- | --- |
| `SIGHUP` | Save the checkpoint at the next committed cycle and exit, so Sophia restarts a rebuilt binary and the next generation restores. Refused with a warning when `HAGIA_POLICY_CHECKPOINT` is unset, because exiting would drop the session rather than reload it. |
| `SIGUSR1` | Write the committed model to `HAGIA_POLICY_DUMP`. Read-only. |

## Tooling

These are read by scripts, not by `src/`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `SOPHIA_STACK_ROOT` | none | A Sophia checkout. Required by `nimble test` and `nimble verify`. |
| `HAGIA_ALLOY`, `HAGIA_Z3` | `alloy`, `z3` | Model checkers for `nimble verify`. Alloy is pinned to 6.2.0; Z3 admits the known-good list in `tools/check_foundation_models.sh` (4.16.0, 5.1.0), grown by verifying the expected results under a new version. |
| `HAGIA_TLA2TOOLS_JAR` | under `~/src/Specula/lib/` | TLC jar for the profile lifecycle model. |
| `HAGIA_SPECULA_ROOT` | `~/src/Specula` | Where the TLA+ tooling lives. |
| `HAGIA_TLC_WORKERS` | `auto` | TLC worker count. |
