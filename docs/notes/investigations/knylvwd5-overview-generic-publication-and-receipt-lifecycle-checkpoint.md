---
id: knylvwd5
date: 2026-09-25
kind: investigation
status: resolved
tags: [investigation]
---
# Overview generic publication and receipt lifecycle checkpoint

## Question

Does Hagia keep overview policy private while publishing generic render intent
and refusing stale presented actions across settlement, withdrawal and restart?

## Evidence

Signed Hagia candidate `d3920d4` on `overview` builds to
`/tmp/hagia-h002-publication`, SHA-256
`10fc95c8266e933abe2327373846d5d86fe01acdd61ddddd95afecd69e02447e`.
Its pure policy predecessor is `4272cea`; independent wire checkpoint is
`e326c298`. Sophia's joined renderer/protocol/default-profile candidate at this
checkpoint is `87ce4acb` on `rendering/foundation`.

Checksummed logs are retained at
`~/.local/state/hagia/development-evidence/h002-d3920d4/`.
Ten adapter lifecycle controls, the real socket receipt-interleaving control,
46 foundation/profile controls, standalone build, default config validation,
formatting and data-oriented layout pass. The full model run passed its 180
existing controls but exposed a zero transaction in the new receipt fixture;
the corrected socket control passes separately. Both that red run and the
earlier profile-count assertion failures are retained. They are fixture fixes,
not evidence of a production fault or a mutation control.

## Finding and resolution

The WM owns preview geometry, selection and navigation. The adapter maps logical
destinations to connection-local instance/region ids. A content repaint keeps
the complete presentation and target identities; geometry or action changes
advance generations, and removed ids are not reused in that connection.
Sophia owns rendering, source generations, actual completion and physical input.

Receipts may arrive among snapshot chunks or before projection settlement.
The client validates and bounds them, then applies them after settlement and
before the next reduction. A matching revocation closes the current publication;
a late receipt cannot close its successor. Trace records include these receipts.
Source/output/work-area loss, lost selection eligibility, reload and reconnect
close modal state. Private checkpoints never serialize presentation authority.

Super+O and Triad migration now name the pure WM action. The catalog omits the
overview actions when the two generic presentation capabilities are absent.
No process launch, shell metadata, buffer or raw input crosses into Hagia.

## Validation and remaining work

The actual Hagia subprocess-to-Rust transport/reducer controls now pass in
Sophia `de3b9f95`: publication and exact actions, timeout preservation, receipt
revocation, reconnect, and ordinary policy without both presentation capabilities.
These five controls use synthetic receipts, not physical completion evidence.
The separate reducer-only stale-epoch probe remains ignored and explicitly
documents why authenticated session receipt validation is necessary.

The full contributor gate passed with Hagia source `983dd83` and Sophia source
`9a8318ad`: 319 Nim cases, two eleven-scenario policy corpora, four then-current
paired presentation controls, profile/pointer/launch-origin checks, eight Alloy
assertions, Z3 expectations, and four TLA+ lifecycle checks. The log is
`~/.local/state/hagia/development-evidence/h002-joined-verify/verify.log`, with its
checksum beside it. The preceding disk-capacity failure during Rust compilation
remains under `h002-84e717d-verify`; rerunning with a disk-backed target passed.

Final Triad comparison found one policy mismatch: upward entry to a monocle or
deck workspace selected its first window instead of its last. A regression
failed for both layouts; `f59cdf1` fixes the entry direction, and all nine policy
tests plus the layout gate pass. Red/green logs are under
`~/.local/state/hagia/development-evidence/h002-983dd83/`. `aa51b1c` adds the fifth
paired capability-fallback control to the contributor gate. Neither change adds
new feature scope.

The generic session's actual-frame/input join and review fixes are being
integrated under Sophia t241 and t245. Final paired gates remain required;
h002 is open in [the queue](../../../todo.md).
No Hagia live install/reload or physical acceptance was performed.

The Sophia renderer agent separately reported two unintended real-card smoke
runs caused by an inherited environment flag. Both refused submission; full
logs were not saved. Its owning investigation `a16e9iwc` records this incident,
the captured refusal and subsequent device-hidden reruns. It provides no
physical acceptance for this feature.

## Final paired acceptance

The complete native-protocol-family gate passes all eight phases on signed Hagia
`12d314290ce441c853cb8cd7502c367685a15f1f`, signed Sophia
`6251aa7915266f79e700c0997267f4361d46d70d` and unchanged Narthex `50b9014d`.
The gate checked clean, identical source identities before and after the run.
The WM phase passes all 320 Nim checks, both eleven-scenario policy corpora and
the five real-Hagia overview/capability controls. Sophia's full default workspace
suite passes 3,781 tests with no failures; its native backend/session suites pass
1,741 with no failures. Strict Clippy, layout and shader checks pass.

Evidence is retained in
`~/.local/state/sophia/development-evidence/rendering-6251aa79/`, including the
checksummed final gate report and owner logs. Original main gate evidence is
`~/dev/sophia/.artifacts/integration-6251aa79-DBHFkhEI/`. The immutable Hagia
binary at `~/.local/state/hagia/development-evidence/h002-12d3142/hagia` has SHA256
`9473f18be1744a353d370cfd1117827ed36f12b60910aecfb592bb435e7b8245`.

The generic session now joins actual retired frames to input. It defers
replacement during existing application captures, refuses targets cropped off
any head before commit, intersects all-head target membership and revokes stale
receipts independently of transport credit. Production controls establish these
joins; the real-Hagia wire tests continue to use synthetic receipt fixtures.
This closes h002's implementation exit and Sophia's paired t241 acceptance.
No live install/reload or physical display acceptance is claimed.

For a live test, the matching binaries must be selected together and Sophia
must use `--native-scanout`. The shipped profile has Super+O; an existing profile
needs the binding documented in the [README](../../../README.md#workspace-overview).
An explicit overview binding without the negotiated action refuses configuration.

## Connections

The [overview plan](../plans/64ac6jf6-workspace-overview-across-hagia-narthex-and-sophia.md)
owns h002 scope and acceptance. [Architecture](../../architecture.md) and
[action vocabulary](../../action-vocabulary.md) state the WM boundary.
Sophia's `docs/wm-presentation.md` owns the paired generic contract; its
`mjnpxubs` plan owns the rendering foundation dependencies.
