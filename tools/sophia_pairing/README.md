# Optional Sophia pairing

These are Hagia-owned integration assertions. They exercise real Sophia owners
against a frozen normal Hagia executable, including Hagia's action vocabulary,
camera rules and checkpoint format. They are not part of Sophia's required
tests or Hagia's ordinary `nimble test`; neither product build depends on the
other source tree.

The runner accepts a clean Sophia checkout at the exact revision in
`compatibility.json`. It creates a detached scratch checkout under the fresh
evidence directory, copies the embedded fixtures and adds two test mounts:

- `desktop_launch_reload.rs` mounts the fixture tree as private descendants of
  Session's existing test module.
- `policy_transport_worker/ninep.rs` mounts a read-only allocator observer. Its
  source has `#![cfg(test)]`; it neither allocates Qids nor proves held-fid wire
  behavior.

The older interoperability fixtures are also external, under `legacy/`.
Their seven copy/mount recipes in `legacy/MOUNTS.tsv` have exact base-file hashes
and unique anchors. The same Rust runner installs them into the scratch tree;
there is no separate installer. It lists and runs thirteen named legacy cases:
pointer focus, reducer-level presentation, protected profile admission, real X
launch origin, output bookmarks, partial projections and targeted clicks.
Each family records and executes its listed test binary directly. The two
integration cases historically marked ignored are invoked explicitly. The
reducer-only old-epoch presentation boundary stays ignored and is checked only
in the ignored-test listing; it is not acceptance evidence.

No source in the supplied checkout is modified. The overlay preserves private
Session access without a public test API or an environment-driven include hook
in Sophia. This deliberately couples the optional tests to one Sophia version.
An internal refactor requires an explicit rebase and new validation, not an
automatic mount fallback.

Run from the Hagia repository, with an exclusive disk cache:

```sh
cargo +1.96.1 run --offline --locked --manifest-path tools/sophia_pairing/runner/Cargo.toml -- \
  --sophia-root=/absolute/clean/sophia-checkout \
  --hagia-bin=/absolute/frozen/hagia \
  --hagia-sha256=0419e09e224676c4d925438f80b22df9532c1653ec339507637edbe01ea52f5f \
  --output=/absolute/fresh/evidence \
  --target-dir=/absolute/exclusive/cargo-cache
```

The current fixture pins Hagia source `7455c3e` and its retained executable;
there is no automatic build or replacement of that artifact. The runner needs
Rust 1.96.1 (Sophia's pinned toolchain), cached Cargo dependencies, Git,
bubblewrap and GNU timeout. `nimble pairing` is the short launcher; it requires
`SOPHIA_ROOT`, `HAGIA_PAIRING_BIN`, `HAGIA_PAIRING_SHA256`,
`HAGIA_PAIRING_EVIDENCE` and `HAGIA_PAIRING_TARGET`. It hides
devices, removes live-session variables, uses nice 19/jobs 2, runs cases
serially and gives isolated phases one shared deadline; source Git commands have
separate 60-second process limits. This is device hiding, not read-only filesystem
confinement: the bubblewrap root bind remains writable. Log reads are bounded
after a phase exits; log-file growth is bounded by phase time, not a byte quota.
It does not mount 9P or touch a live desktop. Missing inputs, a mismatched revision/hash, missing required tests
or a zero-test run fail.

Evidence identifies **Sophia base + Hagia test overlay**, never an unmodified
Sophia source tree. `overlay.json` and `overlay.patch` identify the injected
bytes; `report.json` records the base, overlay, runner and executable hashes;
`test-binary.json` pins the Session test executable. Individual case evidence
retains supplied facts and source-specific qualifications. Logs and the scratch
checkout remain on failure. Before/after path hashing does not remove the
hash-then-exec window and is not descriptor-pinned execution.
Each case executes that listed binary directly, with its hash checked before
and after. Direct rustfmt checks cover every injected Rust fixture; `cargo fmt`
alone does not inspect included support modules. Existing mount-file bodies keep
their pinned base formatting, including any pre-existing formatting debt; the
recorded patch and whitespace check cover the added mount lines.
Legacy families retain their own test-binary records and logs. Their older
receipt fixtures remain synthetic; their runtime reducer checks do not become
Session layout or physical-presentation evidence by moving here.

The normal Session, managed layout and CPU joins use supplied historical
admission, frontend acknowledgements and CPU pixels. The presentation case uses
a generic backend `test-support` target with simulated device/copy/flip
completion; receipts still come from the production retired-frame owners.
Its two transports run the same assertions; it does not assert full result
equality. Hagia treats Presented as a model no-op; receipt delivery and ordered
application do not prove a receipt-dependent model transition. No physical
presentation, application execution or performance acceptance is claimed.

The profile-replacement fixture additionally overlays a Session dev-dependency
on the already-locked serde_json package, solely to inspect Hagia's checkpoint.
Both Cargo files are context-pinned and hashed; every Cargo phase uses --locked.
This is part of the test overlay, not a production dependency change.

For captured WM records, the pinned Sophia source also supplies the WM-neutral
`sophia-protocol` example `wm_file_inspect`. It renders a validated Snapshot or
bounded contiguous event capture with explicitly supplied epoch/capabilities.
It opens no live endpoint and acknowledges nothing; it is separate from this
Hagia-specific acceptance runner. Sophia's `sophia-wm-files.md` documents usage.
