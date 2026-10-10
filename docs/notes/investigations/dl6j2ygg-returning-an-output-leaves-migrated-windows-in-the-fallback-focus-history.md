---
id: dl6j2ygg
date: 2026-10-10
kind: investigation
status: investigating
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

## Validation and remaining work

Two generic regressions cover current and historical focus on the fallback,
plus adapter reconciliation with and without checkpoint restoration. Both fail
against the original source with `policy focus history is invalid`. The initial
adapter fixture did not establish the migrated focus history and was strengthened
before the final red. An initial compile-only failure from a comment typo is
preserved separately and is not red evidence.

The full Hagia gate and a matched integration release precede another physical
reconnect. h018 and Sophia t310 remain open until the window returns to HDMI,
workspace labels reappear, and keyboard and pointer routing work. No new live
run has been performed by the agent.

The incident also exposed a Sophia supervision limit: negotiation marks the
process healthy and resets the restart budget before it successfully answers a
cycle. A client that repeatedly negotiates then fails can restart indefinitely.
This is a separate Session follow-up; the Hagia repair does not change it.

## Connections

The configured workspace-affinity implementation owns restoration of private
views and windows. Sophia's t310 investigation `ig4obtxu` and plan `cmoaia7z`
own the integrated physical acceptance and retain the earlier output-loss fix.
