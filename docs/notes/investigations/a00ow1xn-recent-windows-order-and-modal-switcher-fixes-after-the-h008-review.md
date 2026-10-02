---
id: a00ow1xn
date: 2026-10-01
kind: investigation
status: resolved
tags: [investigation, recent-windows, presentation]
---
# Recent-windows order and modal switcher fixes after the h008 review

## Question

h008 landed the recent-windows switcher in `5eaa712`. An independent read-only
review of that commit, relayed by Sophia's director, found one confirmed
ordering bug and two defects in the modal fallback. Which boundary is
responsible for each, and does the switcher work on a desktop with more than
one output?

## Evidence

The review is kept at
`~/.local/state/sophia/development-evidence/t276-idle-wakeups-01/claude-hagia-review.log`.
The follow-up evidence is in `~/.local/state/sophia/development-evidence/h008-recent-windows-02/`.

- **Ordering, read from source.** `setFocus` recorded the recent-focus order on
  every call. `reconcile` calls `setFocus` for each output that reports a
  focus, in Sophia's snapshot order, before every cause. So with `b` focused
  on the right output and then `a` on the left, the next snapshot rewrote the
  order to put `b` after `a`. Alt+Tab then skipped `b` for an older window
  beside `a`. Every existing test used one snapshot output.
- **Reproduction.** A new two-output `PolicySession` test
  (`trecent_windows_adapter`, "restoring each output's focus does not reorder
  the recent windows") was compiled against `git archive 5eaa712` sources
  (`00-head-mru-repro.log`). It shows the order `[2, 1, 3]` where `[1, 2, 3]`
  is expected.
- **Second bug, observed in the same reproduction and not in the review.**
  `revokeChangedPresentation` cleared every publication whose output count
  differed from the snapshot's. The switcher publishes only the output it
  opened on, so on a two-output desktop each reconcile dropped it. Enter or a
  click then failed with "presentation action has no active policy
  publication".
- **Modal capture, read from Sophia source.** `presented_policy.rs` matches
  modifiers exactly, and any unbound key is consumed. The fallback bound Tab
  only under six masks, and Enter and Escape only with no modifiers. So
  Ctrl+Tab could open the switcher but not step it. Alt+Enter and Alt+Escape
  were swallowed while Alt was still held.

## Finding and resolution

- **The order is a policy-model concern, not a focus primitive.** `setFocus`
  no longer touches it. `noteRecentFocus` records the active output's focused
  window after reconciliation and after each cause settles: at the end of
  `reducePolicy`, at the end of `reconcile`, and after
  `applyPresentationAction`, which bypasses the reducer. A repeat is
  idempotent.
- **The output-count revoke belongs to the overview,** which covers every
  output. The per-output generation, geometry and source checks still apply
  to the switcher.
- **Modal bindings cover every chord the operator may still hold.** The policy
  never learns which chord opened the switcher. So Tab, Right, Left, Enter, KP
  Enter and Escape are each bound under all 16 Shift/Ctrl/Alt/Super masks, 96
  bindings against Sophia's limit of 256; Shift+Tab steps back. A trigger on a
  key other than Tab opens the switcher but cannot step it. That is a
  documented limit of the fallback, and the chord lifecycle removes it.
- **The default `Alt+Escape` cancel bind is removed** until the lifecycle
  path exists. Outside the switcher it did nothing, yet it still took
  Alt+Escape from clients.

## Validation and remaining work

Deterministic checks, on final diff `hagia-followup-final.diff`:

- `nph --check` and the data-oriented layout check pass.
- The full policy gate passes (`03-policy-gate.log`).
- The foundation and profile-lifecycle models pass (`04`, `05`).
- Sophia's director approved diff `f4020fe25c53ca0b`. The final diff differs only in the wording the review asked for.

Mutant note: putting the old `setFocus` recording back on its own survives,
because the reconcile-end record re-records the active focus last. The
faithful red is the run against the h008 sources.

Remaining: h008's lifecycle half (Overlay presentation, Held and Ended) waits on
Sophia t277 and C SDK 0.5.0. There is no live acceptance yet.

## Connections

- h008 in `todo.md`.
- Sophia t277, the generic chord lifecycle contract.
- [Overview generic presentation lifecycle](knylvwd5-overview-generic-publication-and-receipt-lifecycle-checkpoint.md):
  the publication lifecycle the switcher shares.
