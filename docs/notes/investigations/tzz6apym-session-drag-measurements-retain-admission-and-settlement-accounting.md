---
id: tzz6apym
date: 2026-09-26
kind: investigation
status: investigating
tags: [investigation]
---
# Session drag measurements retain admission and settlement accounting

## Question

Can the same protected normal Hagia be compared over current IPC and files
through Session's real interaction queue and layout settlement, without
counting coalesced work as fast completion or timing supplied fixture setup?

This is h006/Sophia t249 control-path evidence. It is not input-to-photon or
physical acceptance, and leaves the installed transport unchanged.

## Evidence

The optional pairing overlays the exact Sophia base
`28eed9742776f2ae2bb84336528790924220adc5`. Normal Hagia remains the frozen
`7455c3e` executable, SHA256
`0419e09e224676c4d925438f80b22df9532c1653ec339507637edbe01ea52f5f`.
The unchanged binary and protected launch helper are used for both wires.
No Hagia policy assertion enters Sophia's ordinary tests.

The first compile (`.artifacts/measure/pair-first/required-list.log`) refused
a fixture `u32` geometry step added to Sophia's signed `Rect` extents. The
correction uses `i32` throughout that bounded step. The next run
(`pair-second/measure-01.log`) stopped during untimed setup: the offered outer
allocation was 96,96 at 320x240, while the content layer was 97,97 at 318x238.
Session's existing Engine chrome conversion explains that difference. The
fixture now separately requires the committed reducer's exact offered outer
geometry and `content_surface_geometry` for the actual layer, with stable
candidate chrome throughout measurement. No proposal or production behavior
was changed. Both first failures remain separate from measured results.

## Finding and resolution

The fixture uses absolute 60/120 Hz offer times and offers every overdue slot.
It observes the actual queue before and after enqueue: only an exact queued
replacement counts as coalescing; `Duplicate` alone proves nothing. Dispatch
binds the request ID, and the unchanged returned proposal binds its separate
domain transaction. A successful sample ends after actual layout apply and
reducer advancement. Replaced updates have no settlement sample.

Historical managed admission, frontend delivery acknowledgements and CPU
size observations are supplied. Geometry stays with the existing owners;
readiness, preparation, resolution and apply remain production methods.
Normal checkpoint persistence stays enabled and backpressures subsequent
cycles. Setup, Begin and End are untimed. No Present, native receipt, GPU
completion, application executor or whole-owner-loop claim follows.

Failures preserve raw counters and unresolved identities; an unwinding
assertion writes the partial capture before resuming. A process abort or hard
runner timeout may leave only logs. The strict report refuses inconsistent
accounting instead of repairing it. Per-run load records, captures, overlay,
machine description and executable identities are hash-bound. Hashing paths
before and after execution does not remove the hash-then-exec interval.

## Validation and remaining work

The debug smoke at `.artifacts/measure/pair-third` completes all sixteen
fixture invocations. Its 256 offers are admitted: 235 settle and 21 are
coalesced, with no rejection, timeout, disconnect or unresolved work. The
overlay manifest SHA256 is
`c926c13c5a3f49c704bf932d7306b4759ef7e51f79b6f67b3c4f5ccad0c58dac`;
the listed and repeatedly checked test-binary SHA256 is
`0d852f88d37f65aeb136ae0f1bb845dfbb66d951827df67fd0bd7d4f31749d13`.

The campaign deliberately exits 1: every pair refuses one or more declared
budgets. At 60 Hz, current-IPC p95 ranges from 6.153 to 10.338 ms and files
from 15.279 to 17.020 ms in these sixteen-sample runs. All four 120 Hz pairs
retain different offer sets, so they cannot establish comparative survivor
latency; files also exceed one update interval. These are small debug runs,
not release regressions or daily-driver acceptance. The thresholds and
accounting were not relaxed or rerun until green. Offline reporting reproduces
the same decoded JSON and refusal. A too-short acceptance timeout refuses
before creating any scratch checkout.

Read-only triage identifies a concrete scheduling difference in this Sophia
base. The driver waits up to 10 ms on its command channel before calling
`try_receive`; that call drives the 9P reactor. A file ProjectionOutcome send
appends an event and wakes the reactor but does not turn it, while current IPC
writes its outcome immediately. A Cycle does enter receive immediately. This
can defer outcome delivery, checkpoint work and follow-up file requests until
the next Cycle or idle timeout. The 60 Hz file medians show a periodic beat
consistent with this path. Its contribution to the observed latency remains a
hypothesis until a controlled scheduling change and release measurement; the
smoke does not establish byte-copy cost or justify reducing a timeout by fiat.

The runner's eighteen controls pass, including malformed partial accounting,
identity/timing, paired workload and load-artifact refusal cases. The first
strict run's three expression-style lint failures are retained separately;
the corrected runner passes strict Clippy. These checks establish the
measurement tool, not the performance gate.

The same final fixture source also passes the ordinary pairing at
`.artifacts/measure/retained-first`: twelve owner cases and thirteen legacy
cases, each explicitly named and run once. Strict native Session and runtime
Clippy, freshly compiled layout, workspace formatting, direct overlay
formatting and whitespace checks pass. The timing test appears in the listing
but is excluded from ordinary pairing unless its workload mode is requested.
Hagia's own data-oriented layout check and final runner controls/Clippy pass.

The smoke schedule is sixteen runs: move/resize, 60/120 Hz, idle/two CPU workers,
both wires, sixteen offers each. The acceptance schedule is eighty runs with
five alternating pairs per condition and at least 10,000 admitted updates per
run. Its schedule alone needs 9,999 seconds; smaller declared timeouts refuse.
Smoke can never set `latency_gate_pass=true`.

The report uses nearest-rank distributions, explicit failure counters and
enqueue lateness. Paired comparisons require the same surviving offer IDs and
counts; a transport cannot appear faster by discarding more work. The existing
Sophia p95 +1 ms, p99 +2 ms and one-update-interval budgets are unchanged.
CPU/allocation/copy/wakeup/round-trip accounting, the full paced campaign and
attended daily configuration remain separate requirements.

## Readiness correction and retained failed diagnostic

Sophia's signed `9f03d3e8424184c1ceb4b8c4b51bd1e3a57de6b4`, joined as
`82085333571141eb8662bcf3468877442c72d7dd`, replaces the file driver's idle
command-channel wait with one reactor readiness turn and an accepted-command
bell. DirtyOnly permissions, active response waits and current IPC remain
unchanged. Seven new generic controls pass within the restored worker suite
(59 passed, three explicitly ignored), with strict native Session, fresh
layout and formatting checks. A compiled selector mutant enters the old
fallback and fails with an explicit test marker. This is structural evidence,
not a latency measurement.

The pairing pin moves to this exact Sophia commit. Only the pinned `ninep.rs`
mount context changes; the workload, frozen Hagia, thresholds and checkpoint
behavior are unchanged. `.artifacts/measure/pair-idle-fix` completes sixteen
cases: 256 admitted, 229 settled, 27 coalesced and no rejected, timed-out,
disconnected or unresolved work. Its overlay hash is
`1d353600319ab5cb6f6ca7cad1091e7a482942224765c391efc1f148491ba2eb`;
the checked test-binary hash is
`51465741a8b821320cca31838dfc1a2d63b4b14bf84e37d0dea789d27d58997d`.

The campaign still exits 1: two of eight pairs meet the numerical smoke
budgets, six do not. Three 60 Hz file runs have medians of 1.74–1.85 ms,
instead of the earlier roughly 9 ms. Ordinal 02, **idle** move at 60 Hz, is an
outlier: only offers 1 and 16 survive, with enqueue-to-settlement latencies
647.7 and 722.6 ms. Its load record proves zero load workers. An interim chat
update mislabeled this as CPU load; the manifest and this record correct it.
The 120 Hz results retain interval failures and, in three pairs, different
survivor identities. None of these small debug runs is release acceptance.

The outlier's long settlement gaps coincide with sparse Hagia checkpoint-save
timestamps. Hagia synchronously flushes and fsyncs the file and its directory;
the evidence and build targets share an ext4 filesystem. Storage latency is a
hypothesis, not an attributed cause. Keep the failed case. The next diagnosis
can record bounded per-case I/O pressure and checkpoint durations or use a
declared order control. Do not disable fsync, discard startup samples, change
the filesystem for one wire, or relax budgets after this result. The full
release campaign has not run.

The separate ordinary pairing at `.artifacts/measure/retained-idle-fix`
passes all 25 named owner/legacy cases. Strict native Session and runtime,
fresh layout, workspace formatting, direct overlay formatting and whitespace
checks pass. The compatibility-only rebase also passes all eighteen runner
controls and strict Clippy. These results do not turn the failed timing
campaign into a performance pass.

The original signed tooling and first failures are preserved at
`~/.local/state/hagia/development-evidence/h006-drag-measurement-48fed33`.
Sophia's independent fix evidence is at
`~/.local/state/sophia/development-evidence/t249-wm-idle-9f03d3e8`.

## Connections

- [h006 plan](../plans/i2c2blti-run-the-hagia-wm-role-over-an-independent-9p2000-l-client.md)
  owns the paired milestone and its remaining exit.
- [Pairing ownership](aoivl2yn-hagia-specific-acceptance-lives-in-an-optional-source-pinned-pairing-overlay.md)
  preserves the prior owner, legacy and live evidence.
- [Runner usage](../../../tools/sophia_pairing/README.md#session-drag-measurements)
  specifies invocation, evidence and reporting bounds.
