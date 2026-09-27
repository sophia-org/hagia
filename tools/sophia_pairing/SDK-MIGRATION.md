# SDK pairing migration

This update keeps the signed product source at Hagia `b3d84966` and targets
Sophia `3d8c4ac3`. All fixture mount files are byte-identical to the previous
Sophia pin; only the lockfile binding changes. A fresh isolated development executable is bound by SHA-256 in the compatibility
manifest and fixture. Its source is the unchanged product commit. The isolated `hagia-sdk-pairing/run1` passed all 24 phases: the twelve owner
cases, two pregraphics cases, protocol/isolation/list checks, strict Session and
runtime clippy, layout, formatting and whitespace. The runner at `797e8e04`
completed with identical initial and final source/overlay/binary identities.
This is not a reviewed release build.

## Kept assertions

All twelve Session owner cases remain required by exact name. Startup still
uses Session's protected launch plan and checks supervisor peer evidence, the
exact configured environment, profile identity and configuration/catalog
admission. Each case now accepts only WM `9p2000.L`; the old WM socket variable
must be absent. The configured keys are not a capture of the child environment.

The internal assertions of the layout, corpus, action, output-assignment,
pointer-focus, checkpoint/restart, profile replacement/rollback and mirrored
receipt fixtures are retained. Only IPC runs and equality between IPC and file
observations are removed. File Dirty still must consume exactly one domain
transaction for its continuation. The two pregraphics owner cases remain and
explicitly select 9P. No timeout or policy assertion is loosened.

The presentation fixture still supplies simulated output-authority facts to
Sophia; its output transport label is historical metadata, and no real output
peer or physical device is exercised. This does not qualify an output SDK.

## Historical cases and remaining gaps

The seven old runtime and four old native cases use `--socket` and the IPC
transport, so they no longer run against this product. Their source remains
under `legacy/` as historical evidence. IPC wire coverage is retired with the
product backend. Their behavior coverage must not be inferred from transport
retirement:

- Pointer focus and assignment have assertions in the file behavior fixtures.
- Overview receipt/withdrawal is partly covered by the mirrored owner fixture
  and local policy tests; the old exact targeted-action, revoked-receipt and
  reconnect controls are not claimed as new SDK paired evidence.
- Real X child launch origin, output bookmark, partial output projection and
  two-output click-queue behavior remain gaps in SDK paired evidence.
- The comparative IPC/files drag campaign is refused. Historical captures can
  still be parsed, but their results do not qualify the SDK candidate.

The green run proves the named protected owner exchanges with supplied
historical admission, CPU pixels and frontend acknowledgements. It does not
prove physical input, presentation, application execution or performance, and
does not by itself close every h006/t249 acceptance item.

## Follow-up from this run

Policy exchanges showed approximately one-second gaps. SDK submit, snapshot
and consume stage local work, but its poll hints appear to expose only wire
readiness and deadlines. The focused SDK regression reproduced missing wakeups after submit, snapshot
and consume (timeouts 1000/-1/1000 with no socket readiness). SDK `8decca1d`
requests one immediate dispatch after each successful API call; the strict
no-IPC suite and idle no-spin controls pass. Hagia `69f427ab` vendors that fix.
The result above remains evidence for `b3d84966`; the new vendor needs refreshed
pairing evidence and a source-bound dependency manifest. No latency measurement
or release qualification is claimed for the new revision.

## Wakeup-corrected pairing result

The fresh development binary from Hagia `69f427ab`, vendoring C SDK `8decca1d`,
passed all 24 phases in `hagia-sdk-pairing/run2` against Sophia `3d8c4ac3` plus
the recorded overlay. Binding commit `6add5738` names binary SHA-256
`0c38b959688aa51ee4d0adbfecc6d7ec33d1cb0662e96d36eb76868544764bb6`. Initial
and final source, overlay, runner and binary identities match. The twelve
protected owner cases, two pregraphics cases and strict/layout/format checks
passed with unchanged assertions and deadlines.

The action/assignment/pointer corpus phase took 1.073 seconds versus 52.741
seconds before the fix. This is a diagnostic observation from two functional
runs, not a controlled performance measurement. The deterministic C SDK test
establishes the local wakeup correction and return to idle without spinning.

The refreshed reviewed dependency manifest binds source `69f427ab` with SHA-256
`fabc46a9c97091f6738d0ffe1cb04a07d783e61cd1db742667a533f71263e20e`. The
reviewed-manifest release builder has not built this binary. The behavior gaps
above, formal-model rerun, bound release build and installed acceptance remain
open. No live session, device or installation was touched.

## Reviewed-closure artifact qualification

The first dependency-bound WM pair build succeeded under nested Bubblewrap
with network and devices hidden. Its Hagia binary uses the reviewed 13-package
closure and staged compiler/config/stdlib; Narthex uses its reviewed four-package
closure. Sources, package inputs and toolchain identities were checked before
and after. The C toolchain identity remains recorded rather than a complete
reproducible closure.

The exact resulting Hagia SHA-256
`8c2fc4c400b141c9b23ff87a44f2bc80b9c0457bd9c5a550409283f4728ddeae`
passed all 24 phases in `hagia-sdk-pairing/run3-reviewed`, bound by `3653f12f`.
Initial and final identities match. This is evidence for the reviewed artifact,
separate from the development binary in run2. Both use Hagia `69f427ab`,
C SDK `8decca1d` and Sophia `3d8c4ac3` plus the recorded Hagia-owned overlay.
The behavior gaps above, formal-model rerun, full desktop packaging and
installed/physical acceptance remain open. The running session was untouched.
