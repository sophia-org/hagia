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

The lifecycle half followed once Sophia t277 delivered the chord lifecycle and
its ChordAction cause (feature/generic-chording through 39c0d442) and C SDK
0.6.0 (8f59a9cd):

- Hagia vendors SDK 0.6.0, byte-identical to Sophia's pin, and decodes causes
  7 (ActionLifecycle) and 8 (ChordAction).
- It offers `action_lifecycle` and `chord_actions` as optional. Only when both
  are selected, together with both presentation capabilities, does the
  Configuration declare `recent-window-next` and `recent-window-prev` with Held
  at 150 ms, niri's open delay. Otherwise it declares no chords, and every
  invocation is modal.
- A switcher is owned by chord identities, not by a per-connection mode. The
  opening ChordAction (equal serials) opens or steps the switcher and its chord
  becomes an owner; joins step it only while their chord owns it. Chords of
  the same action on two seats are distinct owners, at most nine (Sophia's
  eight open chords plus one terminal in flight).
- Owners are Hagia identities, issued once by the policy model. The adapter
  alone keeps which Sophia chord serial of the current connection each one
  is, pruned to the live owners, so Sophia's serials never enter policy
  state.
- An owner's Held draws the strip as an Overlay, with no keyboard capture, so
  the held modifier and further Tab presses still reach Sophia. An owner's
  Ended(released) commits the selection, and any other end closes it without
  moving focus. Closing the switcher in any way releases every owner. The
  events of a chord whose switcher closed (cancelled while its keys are down,
  or the other chord sharing the modifier) then act on nothing, not on a
  later switcher.
- A plain invocation (control, indicator, presentation, or a peer without the
  chord capabilities) owes no Ended. A switcher it opens is drawn at once and
  is modal. While a chord owns the switcher, a plain invocation only steps it.
- An Ended whose projection is refused, times out or is disconnected still
  ends its chord: the committed switcher closes if that chord owned it, and
  the refused candidate's focus is never promoted. A new connection epoch
  closes a switcher its chords owned.
- Each trace entry records whether its connection followed the switcher's
  chords. `hagia replay` restores it before reducing every entry, including
  connections appended to an older trace, and an entry without it keeps the
  modal default. The gate replays such traces through the real binary.
- Cancelling a held strip with Escape needs a binding, because the Overlay
  captures no keys; Sophia's own cancellations (a VT switch, device removal,
  a routing change) still end the chord without a switch. The default profile
  leaves `Alt+Escape` as a commented opt-in: bound, it is taken from
  applications even while the switcher is closed. There is no exact niri
  Escape without a binding scoped to the open switcher.

There is no live acceptance yet. The installable release combines this with
Sophia t276 and is assembled by Sophia's director.

## Connections

- h008 in `todo.md`.
- Sophia t277, the generic chord lifecycle contract.
- [Overview generic presentation lifecycle](knylvwd5-overview-generic-publication-and-receipt-lifecycle-checkpoint.md):
  the publication lifecycle the switcher shares.
