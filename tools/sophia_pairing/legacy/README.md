# Legacy Sophia pairing (Hagia-owned)

These are Hagia interoperability cases that used to live inside Sophia's test tree. Sophia's own tree is WM-neutral, so they now live here as an opt-in overlay. It is installed into an isolated scratch Sophia checkout and never into a working tree.

An overlaid checkout is "Sophia <commit> + Hagia legacy overlay <manifest sha256>", not exact Sophia source. The overlay drives Sophia's real owners through the same private module access the cases had in place; it adds no Sophia API and duplicates no Sophia runtime owner.

## Provenance (Sophia 0319356db)

| Overlay file | Came from | Change |
| --- | --- | --- |
| `runtime/pointer_focus_hagia.rs` | `crates/sophia-runtime/tests/support/pointer_focus_hagia.rs` | byte-identical (blob in `PROVENANCE.blobs`) |
| `runtime/presentation_hagia.rs` | `crates/sophia-runtime/tests/support/presentation_hagia.rs` | byte-identical |
| `session/delegated_policy.rs` | `crates/sophia-session/tests/support/delegated_policy.rs` | byte-identical |
| `session/pregraphics_activation.rs` | `hagia_pregraphics_profile_admission_activates_every_owner` in `live_session/profile_preparation_tests.rs` | one module level deeper, so `super::super::session_config_tests` |
| `session/hagia_launch_origin.rs` | the Hagia parts of `launch_origin_socket.rs` (`PolicyFixture`, both `hagia_*` cases, `exercise_output_bookmark`) | the post-map Hagia block becomes `OriginPolicy::place_child` for `PolicyFixture`, with needless borrows removed; test bodies and assertions unchanged |

Sophia keeps the real X child, the production admission policy and a generic `exercise_x_origin` behind the test-local `OriginPolicy` hook. Its own case runs with no policy client.

## Mount recipe (`apply_legacy_overlay.sh SCRATCH`)

The script refuses a checkout that isn't clean, an existing target file, or a missing or ambiguous anchor.

1. It copies `runtime/*.rs` to `crates/sophia-runtime/tests/support/`, and appends to `crates/sophia-runtime/tests/policy_transport.rs`:
   `#[path = "support/pointer_focus_hagia.rs"] mod pointer_focus_hagia;` and `#[path = "support/presentation_hagia.rs"] mod presentation_hagia;`
   (anchor: `fn pointer_focus_is_sent_only_to_a_peer_that_negotiated_it() {`).
2. It copies `session/delegated_policy.rs` to `crates/sophia-session/tests/support/delegated_policy.rs`, and `session/pregraphics_activation.rs` to `crates/sophia-session/tests/support/hagia_pregraphics_activation.rs`. It appends to `crates/sophia-session/tests/support/live_session/profile_preparation_tests.rs`:
   `#[path = "../delegated_policy.rs"] mod delegated_policy;` and `#[path = "../hagia_pregraphics_activation.rs"] mod hagia_pregraphics_activation;`
   (anchor: `fn profile_restart_reattaches_the_exact_key_under_a_fresh_epoch() {`).
3. It copies `session/hagia_launch_origin.rs` to `crates/sophia-session/tests/support/hagia_launch_origin.rs`, and appends to `crates/sophia-session/tests/support/launch_origin_socket.rs`:
   `#[path = "hagia_launch_origin.rs"] mod hagia_launch_origin;`
   (anchor: `trait OriginPolicy {`).
4. It writes `.hagia-legacy-overlay.sha256` (the overlay file manifest) at the checkout root and prints the base commit and the manifest hash.

## Running (`check_legacy_pairing.sh SCRATCH HAGIA_BINARY`)

It runs the commands, filters and name guards moved from `tools/check_sophia_policy.sh`, plus a new listing guard for the pregraphics filter. The caller supplies the isolation: device-hidden, nice, `CARGO_BUILD_JOBS`, and a private `CARGO_TARGET_DIR`. The cases skip when `SOPHIA_HAGIA_BIN` is unset, so the runner always sets it.

## Retained qualifications

- The presentation receipts are explicit transport fixtures, not evidence of an actual presented frame. Completion from retired frames belongs to Session.
- Pointer focus and presentation drive `PolicyWmSessionTransport` against the Engine reducer, not Session's live owner loop.
- Launch origin uses a real X child and Sophia's production admission policy. The Hagia client runs over current IPC with a focus-follows-mouse profile.
- The output-bookmark case stays `#[ignore]`: it needs an explicit, freshly built Hagia.
