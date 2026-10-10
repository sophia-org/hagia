# Current SDK lifecycle assertions

`lifecycle.rs` is an external test-source overlay, not part of Hagia's Nim
build and not shipped inside Sophia. niltempus's `tools/wm_lifecycle.rs`
mounts it beneath the production Session launch/reload tests in an archived,
explicitly pinned Sophia checkout. This grants test access to private owners;
it does not add a Hagia dependency or special case to Sophia.

The three explicitly ignored cases must be listed and invoked individually:

- `sdk_lifecycle_startup`: ordinary Hagia, protected supervisor launch, exact
  profile activation, nonempty action catalog and capability ceiling. No
  checkpoint is created before a committed cycle.
- `sdk_lifecycle_profile_rollback`: accept view-count 8, then have real Hagia
  reject view-count 10. The Session reload/restart owners preserve the accepted
  profile, catalog and checkpoint until new committed cycles. Both replacements
  answer their own queued scene and checkpoint refresh request.
- `sdk_lifecycle_restart`: terminate the fixture's supervised child and let
  the automatic owner restart it, then invoke the requested restart owner.
  Each successor has a new peer and epoch, retains the profile/catalog and
  checkpoint, and supplies its own post-restore Dirty continuation.

The headless scene is empty. Its committed checkpoints prove this lifecycle,
not restoration of occupied windows, focus, pixels or input. The fixture calls
the real layout settlement owner; it does not run Engine rendering or native
presentation. Protection evidence is the supervisor's observation, not an
independent namespace inventory or a new 9P authentication claim. The requested
restart calls the Session owner directly, not the public control socket.

Each case records its profile, checkpoint where present, negotiated
capabilities, connection epoch and protection evidence. Normal exit checks
child reaping; the external PID namespace and timeout bound failure cleanup.
The SDK vendor manifest, ordinary binary hash, source identities, overlay hash,
tool versions and test list belong to the external runner's records.

The old `tools/sophia_pairing` suite remains historical and unchanged. This
small current-source suite does not qualify all negotiated capabilities,
latency, native receipts, or the rest of h006/Sophia t249.
