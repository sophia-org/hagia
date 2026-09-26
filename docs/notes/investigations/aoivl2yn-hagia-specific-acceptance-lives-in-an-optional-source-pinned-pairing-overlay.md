---
id: aoivl2yn
date: 2026-09-26
kind: investigation
status: investigating
tags: [validation, tooling]
---
# Hagia-specific acceptance lives in an optional source-pinned pairing overlay

## Question

niltempus corrected the ownership of the development acceptance fixtures:
Sophia is WM-neutral. Hagia action names, camera rules, checkpoint JSON and
frozen executable assertions belong to Hagia, even when the test exercises
Sophia's real Session owners. h006 retains those joins as an optional external
pairing gate rather than requiring Hagia in Sophia's ordinary test suite.


## Evidence

Sophia base `0319356db2671f7af3da3bcfaa2300ded3d553a4` removes the new
Hagia Session family and its allocator-only observer. The source copies were
hashed before removal; earlier signed branches and their evidence remain.
Generic driver/P1/replay tests stay in Sophia. Existing mirrored target tests
share a generic backend `test-support` fixture, excluded from ordinary release
dependencies. Sophia's focused restored checks pass 51 worker tests (three
explicitly ignored) and 32 mirrored controls, plus strict native Session and
backend checks and fresh layout/format checks.

`tools/sophia_pairing` embeds the external fixture bytes and checks a clean
exact Sophia base, both private mount contexts and the frozen normal Hagia
executable (source `7455c3e`, SHA256 `0419e09e…52f5f`). It copies into a fresh
scratch checkout and records the base plus overlay hash/patch. The helper
mounts as a private test descendant; no public Session API is added.

Initial external evidence is `.artifacts/h006-pairing/run-1`: eleven required
cases passed individually, including the new mirrored-presentation pair,
followed by strict native Session, fresh xtask layout, format and diff checks.
Before/after source and executable identities agree. This run preceded the
runner review refinements and excluded profile replacement. It remains separate
from subsequent runs.

## Finding and resolution

The public conformance host cannot exercise Session's private restart/layout
owners. A pinned test-only overlay keeps that access explicit and external.
Evidence describes "Sophia base plus Hagia overlay", never an unmodified Sophia
checkout. Private source coupling is deliberate and fails on an unreviewed base.

Independent review found two runner evidence weaknesses: re-running Cargo could
select a different executable while the old path's hash stayed unchanged, and
`cargo fmt` alone skips included support modules. The corrected runner executes
the listed binary directly with before/after hash checks and invokes rustfmt
directly on every injected Rust fixture. Missing/duplicate tests and zero-test
summaries fail unit controls. Wrong executable hash and dirty base fail before
creating evidence or acquiring the target cache.

The profile child was copied byte-for-byte from preserved uncompiled WIP
(`c5ab3af6…38ba`). Its serde_json dev-dependency and lock entry are applied only
to scratch source with exact context hashes and locked Cargo commands. In
`run-2`, all twelve required cases passed, including the first real profile pair:
view-count 8 was accepted, 10 was rejected by Hagia, and Session's existing reload
owners restored the prior immutable profile at a fresh epoch. Strict Clippy then
refused two fixture-only patterns. The narrow if-let/record cleanup changed no
assertions; the original child and failed strict log remain preserved.

`run-3` passed all twelve cases, strict checks and layout, then direct rustfmt
found existing formatting debt in Sophia's mount-file body. No base source was
reformatted. Direct formatting now covers injected fixture files; the two mount
contexts remain hash-pinned and their added lines are recorded in the overlay
patch and checked for whitespace errors. This distinction avoids treating
`cargo fmt` as coverage of included fixtures without rewriting unrelated base
tests.

The restored gate `run-4` passes all twelve individually listed owner cases,
protocol tests, strict native Session checks, freshly built xtask layout,
workspace format, direct fixture format and whitespace checks. Before/after
identities agree. Its overlay manifest is
`3f4c87f34c2ec3fbbca466966bee2f21dcbe17aa3470f139b485d4ee3ca2e8ab`,
and runner executable is
`5ad0bd8b54e93ac52ce9589014ae79d3e2df06a8af2bce2002636c6faca46aa9`.
The profile child after the lint-only cleanup is `4dfcc3bb…fbfa`. The selected
Session test executable is recorded separately in `test-binary.json`; every
case ran that executable directly with matching hashes before and after.

## Validation and remaining work

The presentation pair derives receipts through actual backend retired-frame
owners, with simulated device/copy/flip completion. Both transports satisfy the
same assertions; no full observation equality is claimed. Presented is a no-op
in Hagia's model and the Withdrawn receipt follows an already-closed publication;
ordered delivery does not establish a receipt-dependent model transition.

Other supplied facts remain historical managed admission, CPU pixels and exact
frontend acknowledgements. Timeout rollback is issued but unanswered. The
accepted terminal intent is retained without executor invocation. No physical
presentation, application execution or performance result follows from these
tests. Hashing paths before/after retains a hash-then-exec window.

The isolation uses a writable root bind with hidden devices and cleared session
variables; it is not read-only filesystem confinement. Isolated phases share
one deadline; Git source operations have separate process limits. The log read
limit is not a write quota. The initial runner unit compile used nice 19/jobs 2
without device isolation; its two controls were repeated under isolation before
the real pairing. No live process was launched by that initial compile.

### Completed legacy relocation and combined gate

Sophia `8bc5da5aa` and `6991101b4` remove the remaining real-Hagia runtime and
Session pairings while retaining generic X-origin and owner controls. Hagia's
`69fa0c2`, `30d7b8f` and README correction `06ab32d5` supply the external legacy
fixtures and move their ordinary gate references in the same change. The final
legacy installation recipe is data (`MOUNTS.tsv`), consumed by the one Rust
runner; no separate maintained shell installer remains. Five source files are
byte-identical to Sophia's originals, with the extracted activation and
launch-origin hook adaptations recorded in `legacy/PROVENANCE.blobs` and README.

The neutral Sophia listing loses exactly eight runtime and six Session cases,
plus three name-only generic renames. Restored generic checks pass runtime 6/0
and Session 667/0 with 21 ignored, strict checks, layout and format. The first
Session run failed three reconnect cases (664/3/21); focused and full reruns did
not reproduce them. They remain intermittent/unresolved. Untouched source and
green reruns do not establish that the failures predate relocation. The first
listing comparison reused a stale shared-target binary and is discarded;
independent base/head targets establish the final listing. All logs remain in
`sophia-legacy/.artifacts/neutral-validation` and the combined durable bundle.

`run-5` is the final combined optional gate on Sophia
`81e9826a662dfcc34fe91e8e42309cb064ac5bca` plus overlay
`d4b330dfb325ddee2567892b338a0b634409b1644ef158e1cc318998938c9222`.
All 25 named pairing cases pass: twelve Session-owner cases and thirteen legacy
cases, including explicitly selected targeted-click and output-bookmark tests.
The reducer-only old-epoch presentation case is verified in the ignored listing
and is not executed or counted as accepted. Protocol checks pass 251/0; strict
native Session and runtime all-target checks, fresh xtask layout, workspace and
direct fixture formatting, and whitespace checks pass. Before/after identities
match. The runner executable hash is
`1cf6246b02b998b1160688de9824fefaff4339f1ac0f3c9fcb238ef54304023a`.

Independent runner review caught an integration-test listing mismatch before
the combined run: Cargo labels the runtime target `Running tests/...`, whereas
the original parser accepted only `Running unittests ...`. The parser now
requires the exact expected launch kind and exactly one executable under the
private target. Four runner controls and strict Clippy pass, including wrong
launch kind, ambiguous/missing cases and zero-test refusal.

The pinned Sophia source includes its generic captured-record inspector, with
eight controls and a CLI malformed-suffix/empty-stdout check; it is not a live
reader. h006/t249 remain open for the remaining lifecycle and measurement exits
and explicitly approved physical/default-switch gates. No new default or live
desktop change follows from these results.

## First attended live 9P trial, 2026-09-26

After niltempus authorized the trial and logged out of the daily desktop,
release builds of Sophia `81e9826a662dfcc34fe91e8e42309cb064ac5bca` and Hagia
`1f24fbc1b569cc49a1bc46c31929f3654ba1281a` ran on tty4/display `:90` through
the existing guarded launcher, explicitly selecting `--wm-transport=9p2000.L`.
These were production builds without the acceptance overlay. The running
executables matched SHA256 `62111c72…a572f` (Sophia) and `f10afbac…c1788`
(Hagia). The live Hagia environment contained `SOPHIA_WM_9P_SOCKET` and the
separate existing output socket, with no `SOPHIA_WM_SOCKET`.

The copied desktop profile changed only the WM executable; the core profile
and installed shell components retained their settings and identities. Session's
actual policy-fragment preflight, generated launch vector and prebuilt xtask
profile checks passed before takeover. An unnecessary initial whole-desktop
Hagia check refused a Sophia-owned shell setting; its log is retained. The
correct Session-owned fragment validation passed without relaxing the profile.
No installed release, login entry or default transport was changed.

niltempus reported normal behavior, including overview. Logs record WM epoch 1
with no restart during the observation, committed configuration, checkpoints
and native frame retirement. Normal logout completed after 246,261 ms with
exit status 0, `emergency=false`, `wm_degraded=false`, no native frame in flight
and no native cleanup pending. No trial processes remained. The origin tty
state was restored. Exact greetd tty termios restoration differed; the existing
safe-baseline fallback passed its checks and returned to a ready greeter on tty7.
This is an attended smoke result, not completion of all physical acceptance rows.

The operator also observed lower Sophia CPU use. A five-second uncontrolled
sample measured 22.6% of one CPU core for Sophia; there is no matched IPC sample
and therefore no measured transport improvement. The normal diagnostic budget
suppressed 42,456 records, with zero storage errors; the capture is not a full
event transcript. Pointer latency/default-switch gates and the earlier
intermittent reconnect failures remain open.

The private durable bundle is
`~/.local/state/hagia/development-evidence/h006-live-9p-20260926`: 47 checksummed
files, including release binaries, preparation and first-failure logs, live
process identities, operator observations, CPU sample and shutdown evidence.
Its verified `SHA256SUMS` digest is
`f32b1f39850b672c8bf5512ca335fd158706807d8297308307878c6c8917cc7e`.

## Connections

The [h006 plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
owns the client milestone. [Pairing usage](../../../tools/sophia_pairing/README.md)
names prerequisites and the exact source-overlay boundary. Sophia's
`uf2wya88` investigation retains the generic owner and prior checkpoint evidence.
