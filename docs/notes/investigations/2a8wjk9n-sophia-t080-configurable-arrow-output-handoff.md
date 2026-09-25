---
id: 2a8wjk9n
date: 2026-09-24
kind: investigation
status: resolved
tags: [investigation]
---
# Sophia t080 configurable arrow output handoff

## Question

Sophia t080 asks for configurable arrow navigation across outputs, default on,
so per-monitor workspaces can opt out. Sophia agent w9:pN owns its queue row
and integrated closure; no Hagia task identity is created.

## Evidence

Baseline: Hagia `50336ce66a9a14d731b34e34638c2cd9c4a71878`, branch `master`.
Source inspection found both empty-output and strip-edge handoff centralized
in `systems/focus.handOffToAdjacent`. Explicit output cycling uses a separate
procedure. This change adds a guard at that single boundary.

## Finding and resolution

`policy { arrow-crosses-outputs #false; }` disables column-navigation handoff;
true or omission preserves existing behavior. Local focus, explicit output
switching and pointer focus retain their owners. The preference lives in
`PolicySettings`, with exact boolean profile validation. Checkpoint version 19
stores it; versions 4 through 18 restore the historical true default. Applying
a new profile replaces the setting through the existing candidate transition.

## Validation and remaining work

Navigation regressions cover both directions, populated and empty outputs,
local movement, explicit switching and retained workspaces/focus. Profile tests
cover true, false, omission, malformed and repeated values. Adapter tests cover
checkpoint restoration, legacy migration and reload with retained monitor state.

Passed serial headless validation:

- `tscroller_navigation`: 13 cases.
- `tpolicy_model`: 180 cases, including local socket settlement and new
  checkpoint/reload coverage. Required unsandboxed local sockets; an initial
  sandbox run was interrupted after socket refusals. The successful rerun also
  includes the corrected current-version assertion (19).
- `tfoundation`: profile grammar/defaults and all existing foundation cases.
- `nim c ... src/hagia.nim`: candidate `/tmp/hagia-t080` built successfully.
- `nph --check src tests hagia.nimble`, `nimble layout`, `git diff --check`.

Temporary logs: `/tmp/hagia-t080-model.log`,
`/tmp/hagia-t080-foundation.log`, `/tmp/hagia-t080-build.log`.
The full cross-repository gate was not run here: Sophia main is reserved for
Claude XTS gates; the coordinator owns paired acceptance in its worktree.
Sophia w9:pN reports both values already survive its policy export; paired
export-to-Hagia and preflight acceptance are delegated to its isolated
`sophia-session-launch` checkout. No live installation or reload is authorized.
