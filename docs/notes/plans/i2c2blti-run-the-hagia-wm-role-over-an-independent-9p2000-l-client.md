---
id: i2c2blti
date: 2026-09-25
kind: plan
tags: [plan, milestone]
---
# Run the Hagia WM role over an independent 9P2000.L client

## Scope and exit

Hagia h006 is paired with Sophia t249 under niltempus's 2026-09-25 instruction
to implement the Hagia-first 9P plan. Implement an independent Nim 9P2000.L
client and the versioned binary WM records, using a direct Unix socket.
Preserve Hagia's standalone build and its existing policy, projection, actions,
overview and checkpoint behavior. The adapter stays thin and uses passive
types in `src/types`; no Sophia source or generated SDK becomes a dependency.

Only the WM role migrates initially. Separate output-control traffic remains
on the current protocol. The old WM transport remains an explicitly selected
fallback during development and remains the installed default. This task
authorizes no live reload, installation or hardware action.

## Task details

The shared contract is owned by Sophia t249. Hagia independently implements
its wire values and consumes its published corpus. Runtime records are compact
binary; derived text inspection does not create another mutation interface.
Snapshot reads remain pinned, proposals are explicitly submitted only after
complete bounded staging, and commits/checkpoints follow correlated semantic
outcomes rather than write acknowledgements. Lost replies cannot repeat an
effect; reconnect starts a fresh epoch and cannot restore stale input authority.

First prove startup/profile activation, one snapshot and proposal through real
Session commit, then expand to all current WM behavior: layouts/workspaces,
focus/sizing/fullscreen/floating, actions and session operations, launch origins,
multi-output/topology, reload/rollback, overview receipts and source updates,
timeout/restart and stale epoch refusal. Pin ordinary model/projection equality
between transports. Preserve red controls and exact paired binary identities.

Run Nim builds serially, format touched Nim files with nph, and run layout plus
the contributor/cross-repository gates in isolated worktrees. Claimed native
presentation must come from its actual owner; synthetic completions remain
development evidence. The director owns the paired gate and merge windows.

## Connections

- [Independent client checkpoint](../investigations/uof7k0rr-independent-hagia-9p-client-bounds-request-and-reply-custody.md)
  records the transport-only controls and remaining role integration.
- [Architecture](../../architecture.md), unchanged WM-only boundary.
- [Work tracking](../../work-tracking.md), h006 owns this client work.
- Sophia plan `docs/notes/plans/80blhke8-migrate-the-hagia-wm-role-to-admitted-9p2000-l-files.md`
  owns t247 foundation, t248 Session adapter and t249 paired role acceptance.
