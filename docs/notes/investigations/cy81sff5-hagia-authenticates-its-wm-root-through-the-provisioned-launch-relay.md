---
id: cy81sff5
date: 2026-10-11
kind: investigation
status: investigating
tags: [investigation]
---
# Hagia authenticates its WM root through the provisioned launch relay

## Question

For Sophia t317 and Hagia h006, can the ordinary Nim WM authenticate using
Session's launch relay and continue on that same admitted root through restart?

## Implementation

The vendored C SDK is signed commit `93361918dd0213a13a2fc8bd26a7911ff7ae16e1`.
Thin bindings call its launch helper and `sophia_ws_open_attached`. Hagia polls
both wires and its stop wakeup; the SDK owns every conversation step, deadline,
nonce and fid. The role client and its storage outlive the borrowing WM session.
The relay is close-on-exec and remains open until owner teardown. Errors close
both transports; they do not select the raw-attach fixture path.

`SOPHIA_LAUNCH_AUTH_FD` is a strictly parsed descriptor, not an identity claim.
Absent that variable, supplied-admission fixtures retain their raw attach;
production Session requires an afid and refuses that route.

## Evidence

Packages are under `~/.local/state/sophia/development-evidence/`:

- `t317-hagia-sdk-pin-01`: strict SDK checks, Nim binding and supplied-admission
  regression checks, descriptor parsing and dead-relay cleanup.
- `t317-hagia-auth-01`: retained STOP, fixture compilation used the wrong
  supervisor termination signature; no execution claim.
- `t317-hagia-auth-02`: PASS against Sophia
  `a24934b15750377110f713799513a0b72656e8a0`, through a test-only source overlay
  mounting `tests/external/authenticated_launch.rs`. The ordinary Hagia binary
  authenticates, commits at epoch 1, is terminated by the supervisor, acquires
  launch registration 2, and commits at epoch 2. Its binary hash and candidate
  file hashes are retained. The source overlay never changes the Sophia tree.

The join uses the real Factotum export with a supplied trusted Session channel,
real protected spawn and production authentication/restart owners. The empty
scene and layout completions are supplied. The ESTALE message follows deliberate
worker teardown, after the child-alive check. No device or physical claim.

## Remaining qualification

`t317-hagia-claim-control-01` changes only the client's `wm` claim to
`forged-wm`. Authentication fails before profile admission, with no epoch/cycle
success record. The test exits 101 with one failure at the expected startup
assertion; restoration is hash-checked. This demonstrates claim refusal, not a
new authority mechanism.

`t317-hagia-local-01` reached the contributor pass marker with 529 Nim checks,
then Nimble exited 1 because the read-only sandbox prohibited saving its own
`nimbledata2.json`. It is retained as STOP, not a successful command.
`t317-hagia-local-02` passed the same layout and contributor scripts directly:
529 Nim checks, strict SDK checks and CLI cases, exit 0. The scripts ran serially
with devices, network and display access hidden. Formatting and the exact
154-file SDK inventory also passed.

`t317-hagia-auth-restored-01` passed startup and restart after restoring the
control. Its rebuilt ordinary Hagia binary has the same SHA-256 as the first
positive run: `b9157502a8ad1fe527536670696b6c5521a7534eccf5077cd56d0ee4829bad91`.
The source and build identities are in the package; no binary was copied to
evidence.
Occupied recovery, a changed-profile replacement and installed-session acceptance
are not established by this empty-scene join. Shell migration and Sophia's t317
closure remain separate. No live installation or reload occurred.

## Connections

[Environment contract](../../environment.md) describes the provisioned descriptor.
[SDK migration map](../../sdk-test-migration.md) separates supplied admission
from this authenticated production-owner join. This result contributes to h006;
it does not close all of that task's release and physical obligations.
