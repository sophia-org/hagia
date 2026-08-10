# Bug Hunting Report

The implementation-fidelity cross-check found and reproduced one reducer bug:
a rejected generation could be reused and delayed completions could promote it.
`latestGeneration` now advances on every attempt and survives rollback.

After that repair, the generation-aware model found no invariant violations.

| Configuration | Search | States | Distinct | Diameter | Result |
|---|---|---:|---:|---:|---|
| `MC.cfg` | exhaustive BFS | 50933 | 2271 | 39 | pass |
| `MC_hunt_partial_prepare.cfg` | exhaustive BFS | 3281 | 228 | 23 | pass |
| `MC_hunt_stale_completion.cfg` | exhaustive BFS | 31565 | 1427 | 39 | pass |

All finite state spaces were exhausted. The generated startup trace matched all
sixteen events with strong generation/digest and post-state validation. The
confirmed bug record and public-API reproduction live under
`.specula-output/confirmation/profile_generation_reuse/`.
