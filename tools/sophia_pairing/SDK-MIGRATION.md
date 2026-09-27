# SDK pairing migration

This update keeps the signed product source at Hagia `b3d84966` and targets
Sophia `3d8c4ac3`. All fixture mount files are byte-identical to the previous
Sophia pin; only the lockfile binding changes. The executable hash is pending
an isolated fresh build and is deliberately invalid until that binding lands.
No build or paired result is claimed by this code-only update.

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

A green new run would prove the named protected owner exchanges with supplied
historical admission, CPU pixels and frontend acknowledgements. It would not
prove physical input, presentation, application execution or performance, and
would not by itself close every h006/t249 acceptance item.
