---
id: vzu831kk
date: 2026-10-01
kind: investigation
status: investigating
tags: [investigation, sdk, 9p]
---
# Repin the C SDK to 0.4.0 for Sophia's output socket retirement

## Question

Sophia t272 retires the output socket. Its WM `api` file now names
`output_transport=9p2000.L`. Which SDK pin and Hagia tests keep Hagia's WM
client strict against that contract, with no fallback?

## Evidence

Sophia contract `b0721d0de6a03cb44e57b0a923c6c385cf40b676` changes the exact
`api` bytes. Sophia's signed integration candidate D,
`ae5a746c553584bff8bb54eeeeee8d2bc63431f8`, serves them. C desktop SDK 0.4.0
(signed `497e7e01531415078a4a3da2455ebe82ec18fd0e`, tag `v0.4.0`) imports that
contract unmodified. It refuses `current_ipc`, a missing newline, a case change
and a missing transport field before negotiation. The SDK no longer builds an
IPC library.

`vendor/sophia-desktop-sdk` holds three things for that commit: its git archive,
a sorted per-file manifest and the raw signed commit object. Manifest
`ab45a6460bef0606210c9dd3da168dafdd9f3f902a639a3cdfaf6bc3945bf5af` equals
Sophia's `vendor/c-desktop-sdk` manifest. The generator first reproduced the
previous `8decca1d` vendor byte for byte.

Evidence is under `~/.local/state/sophia/development-evidence/`:
`t272-hagia-strict-api-01` and `t272-hagia-repin-01`. The latter holds the
generator, the gate logs and the signing summary.

## Finding and resolution

Hagia's production client already uses only the SDK WM session over the
9P2000.L endpoint, so the repin needs no Nim source change.
`sdk_admission_peer` now passes an optional served `api` through to the
pinned SDK's scripted peer. A new `twm_file_client` test serves the retired
`current_ipc` value. Hagia's real file client must raise before any
negotiation offer or configuration. The independent session peer now expects
the 9P2000.L value. The policy gate drops `WITH_IPC=0`, which 0.4.0 no longer
defines.

The optional pairing overlay is pinned to pre-retirement Sophia `be6e5888`.
It compares the retired IPC transport with files, and its runner refuses any
other Sophia revision. It is labelled historical and keeps its logs. It is not
rebased and does not qualify this candidate.

## Validation and remaining work

The contributor gate on the final tree passed:
- formatting and layout;
- 459 Nim checks, including the new negative and the vendored SDK checks;
- the Alloy, Z3 and TLA+ models;
- the pairing runner's 25 tests.

Before the vendor was installed, the same policy gate passed against a private
copy of the 0.4.0 source.

The repin and Sophia must change together. Hagia `b36af295` with SDK `8decca1d`
pairs only with pre-retirement Sophia; this repin pairs only with D or a later
signed successor. Each refuses the other's `api` at bootstrap, so release
rollback restores both together.

`nimble exportProof` against D is pending. Authenticated launch and physical
acceptance remain with Sophia's assembled-candidate gate.

## Connections

- [Independent 9P client plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
  (h006) introduced the vendored SDK and removed Hagia's IPC backend.
- [Pairing overlay](aoivl2yn-hagia-specific-acceptance-lives-in-an-optional-source-pinned-pairing-overlay.md)
  records why the overlay is source-pinned; it is now historical.
- Sophia's retirement record is `docs/notes/investigations/j8jkd97a-retire-the-output-socket-after-native-file-role-acceptance.md`
  in the Sophia repository.
