---
id: dl6j2ygg
date: 2026-10-10
kind: investigation
status: closed
tags: [investigation]
---
# Returning an output leaves migrated windows in the fallback focus history

## Question

Why does reconnecting an occupied HDMI output leave the bar without workspace
labels and physical input held, after unplugging and using the migrated window
on the remaining output succeeded? This is h018, the Hagia part of Sophia t310.

## Evidence

The attended run used Hagia `155daab6c0b035dd3328fd114e70af65456ff336`, Sophia
`adfecd4e1feba9483ed171c64dce546c11bb27e6`, and integration release
`niltempus-9d9413c9aeb19a0bdace`. Session
`00000001791630270246-acde5c19-88e2-4770-9b74-cc0834a908de` began on DP, admitted
HDMI, then survived HDMI removal. niltempus confirmed the workspace-4 window
appeared on DP and accepted typing. Workspace actions 14 and 11 committed.

The next HDMI return resolved and readied two heads for native owner 4, but
never committed that replacement's output realization. Hagia restarted thousands
of times after configuration and snapshot delivery. The original client error
was not captured: client stderr went to `/dev/null`, and reduced records omit
the transport error. Capture also reports discarded records and storage errors.
The exact error in the original process is therefore not claimed as observed.

Evidence is under
`~/.local/state/sophia/development-evidence/t310-two-output-attended-04/`:
`occupied-hdmi-loss-01` records the passing loss, and
`hdmi-return-frozen-input-02` preserves the reconnect across log rotation
(manifest `19094e2367504f3d2dbde70572dda6408f217016fb0913706b479da2fec59348`).
niltempus authorized ending that frozen session; its lifecycle records SIGTERM
exit 143 and handoff to the display manager. No installation changed.

The retained private checkpoint survived under the session's temporary policy
directory. Its SHA256 is
`4d206fe82b1188e2aeec57ceae8e60f9ce903b3a328ed313b270f416c0bbd9b3`.
Offline reconciliation of that checkpoint with a returning second output and
its hidden window reproduces `PolicyStateError: policy focus history is invalid`.
The checkpoint is real; the returning snapshot is supplied, not captured wire.
Reproduction sources and logs are in `t310-hdmi-return-diagnosis-01`.

## Finding and resolution

`restoreOutput` moves windows and columns from the fallback back to their
preferred output. A window used while displaced can also appear in the
fallback's `focusHistory`, which the old implementation left behind. Validation
correctly rejects a history entry whose window belongs to another output.
Restarting from the same checkpoint repeats this failure for a hidden migrated
window, because no current placement overrides its restored affinity.

The output lifecycle operation now removes returning windows from surviving
outputs' focus histories and clears a current focus that moved with them.
History order and focus for windows that remain are preserved. Restored-output
focus still follows its saved affinity and existing eligibility checks. Scene
validation, protocol boundaries and authority ownership are unchanged.

## Validation and acceptance

Two generic regressions cover current and historical focus on the fallback,
plus adapter reconciliation with and without checkpoint restoration. Both fail
against the original source with `policy focus history is invalid`. The initial
adapter fixture did not establish the migrated focus history and was strengthened
before the final red. An initial compile-only failure from a comment typo is
preserved separately and is not red evidence.

Signed repair `ed2f30060a09c5796f80f779ff8f8ebf2033c516` passed the full
device-hidden `nimble verify` gate: 527 reported Nim OK lines, zero failed,
eight Alloy checks, one Z3 result set and four TLC configurations, plus
formatting, layout and SDK checks. Gate `t310-hagia-output-return-gate-01` has
CLOSURE `e976fc2111afc765af83095ca5fe9b76b6e64a5e5be81196d4bff9f9806bd61c`.
The diagnostic records are closed separately with CLOSURE
`4f7e8545ea6c13dd30fc5293f62a424bac0798e121d67b071e32ba43fd870b69`.
All eight supplied return cases using the real checkpoint pass with the repair.

Matched integration `a8067a043` built release
`niltempus-66f68ee2cef161b3829d`, not installed. It changes only Hagia among the
ten executables. Sophia remains `adfecd4e1`, and the output profile differs only
in generated release paths; graphics libraries and other component pins stay
fixed. `t310-hagia-output-return-release-01/READY.txt` carries installation,
accepted one-output recovery and the physical sequence; the package CLOSURE is
`d06ed8faea4e41d2b3a530bb0890ee0d499fc28873db3310172ddb47665bf40c`.

At that handoff, h018 and Sophia t310 still awaited the window's return to HDMI,
workspace labels and working keyboard/pointer routing. The agent performed no
live run; the failed desktop was stopped with permission while niltempus used
the X13.

On 2026-10-10 the installed successor
`niltempus-d59a72c27a32a2c05e27` passed that sequence. Hagia remains the gated
`ed2f30060`; Sophia is `6fd66325b`, and integration is `dc57e532`. niltempus
opened a workspace-4 window, unplugged HDMI, reached it on DP-1, and reconnected
the same dGPU HDMI port. The session survived, and niltempus explicitly
confirmed workspace labels and working keyboard/mouse on both monitors.

The same surface moved output 2 -> output 1 -> output 2 in committed policy;
the returned owner committed two outputs. Hagia PID 30212 has start ticks at
session startup and the gated executable hash, so the successful return did
not require a WM restart. Sophia's investigation `ig4obtxu` owns the integrated
account and limits. Frozen receipt:
`~/.local/state/sophia/development-evidence/t310-two-output-attended-06/acceptance-01`,
manifest `8b02d63a6b4517aa848261c22b07ab756d5eddcd7ace37edba66ef3a791ff13a`.
The bounded log contains the positive joins but also reports discarded records;
the user's observation supplies visual/input acceptance. This meets h018's exit.
The intervening `66f68` run restored Hagia's layout but later failed in Sophia's
forced topology repaint; that separate repaired failure remains in ig4obtxu.

The incident also exposed a Sophia supervision limit: negotiation marks the
process healthy and resets the restart budget before it successfully answers a
cycle. A client that repeatedly negotiates then fails can restart indefinitely.
This is a separate Session follow-up; the Hagia repair does not change it.

## Connections

The configured workspace-affinity implementation owns restoration of private
views and windows. Sophia's t310 investigation `ig4obtxu` and plan `cmoaia7z`
own the integrated physical acceptance and retain the earlier output-loss fix.
