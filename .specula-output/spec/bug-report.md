# Bug Hunting Report

The converged startup-profile lifecycle model found no invariant violations.

| Configuration | Search | States | Distinct | Diameter | Result |
|---|---|---:|---:|---:|---|
| `MC_hunt_partial_prepare.cfg` | exhaustive BFS | 710 | 131 | 10 | pass |
| `MC_hunt_stale_completion.cfg` | exhaustive BFS | 4767 | 777 | 19 | pass |

Both searches exhausted their finite state spaces. The startup trace also
matched all nine events with strong post-state validation. No real
implementation bug was identified by these models.
