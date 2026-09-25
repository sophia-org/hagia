---
id: knylvwd5
date: 2026-09-25
kind: investigation
status: investigating
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

The actual Hagia subprocess-to-Rust transport/reducer control and the generic
session's actual-frame/input join are still being integrated under Sophia t241
and t245. Full paired gates remain required; h002 is open in [the queue](../../../todo.md).
No Hagia live install/reload or physical acceptance was performed.

The Sophia renderer agent separately reported two unintended real-card smoke
runs caused by an inherited environment flag. Both refused submission; full
logs were not saved. Its owning investigation `a16e9iwc` records this incident,
the captured refusal and subsequent device-hidden reruns. It provides no
physical acceptance for this feature.

## Connections

The [overview plan](../plans/64ac6jf6-workspace-overview-across-hagia-narthex-and-sophia.md)
owns h002 scope and acceptance. [Architecture](../../architecture.md) and
[action vocabulary](../../action-vocabulary.md) state the WM boundary.
Sophia's `docs/wm-presentation.md` owns the paired generic contract; its
`mjnpxubs` plan owns the rendering foundation dependencies.
