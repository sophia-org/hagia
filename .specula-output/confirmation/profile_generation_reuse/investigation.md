# Profile Generation Reuse Investigation

## Code audit

- `src/config/coordinator.nim:111-121` admits a candidate when its generation
  exceeds only `activeGeneration`. A rejected candidate does not advance that
  field.
- `src/config/coordinator.nim:63-69` clears the candidate identity after every
  rollback acknowledgement without retaining the attempted generation.
- `src/config/coordinator.nim:72-75` treats a completion as current when its
  generation and digest equal the current candidate. It has no independent
  attempt/epoch identity.
- The public `reduceProfileActivation` API is the normal coordinator entry
  point. A prepare failure dispatches rollback to all seven authorities; after
  all rollback completions, the same generation/digest can be begun again.
  Delayed successful prepare and activation completions from the first batch
  then satisfy the second attempt's identity checks.

The concrete trigger is: begin generation 5; reject preparation; complete the
seven rollbacks; begin generation 5 again; deliver the delayed successful
completions from the first attempt. No invalid model state or private function
call is required. There is no caller-side reuse guard in this repository; the
coordinator type itself owns candidate admission.

## Developer-knowledge search

- Commit `9bc9e2d` introduced the coordinator and states that every failure
  preserves the previous active digest. Its model simultaneously assumed that
  rejected candidate identities could not be begun again.
- `.specula-output/modeling-brief.md` calls epoch/digest confusion a high-priority
  risk and requires stale identities to be ignored.
- Existing tests cover a stale completion with both an older generation and a
  different digest, but do not cover reuse of the rejected generation/digest.
- On 2026-08-10, searches across all open/closed GitHub issues and pull requests
  in `sophia-org/hagia` for profile generation, stale completion, rollback, and
  retry found no report of this mechanism at this site.

## Known status

No matching issue, pull request, advisory, or prior Specula finding was found.
The finding proceeds to public-API reproduction.
