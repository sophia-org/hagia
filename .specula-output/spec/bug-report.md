# Bug Hunting Report

The converged startup-profile lifecycle model found no invariant violations.

| Configuration | Search | States | Distinct | Diameter | Result |
|---|---|---:|---:|---:|---|
| `MC_hunt_partial_prepare.cfg` | exhaustive BFS | 2597 | 228 | 23 | pass |
| `MC_hunt_stale_completion.cfg` | exhaustive BFS | 11467 | 939 | 39 | pass |

Both searches exhausted their finite state spaces. The startup trace also
matched all sixteen events with strong post-state validation. No real
implementation bug was identified by these models.
