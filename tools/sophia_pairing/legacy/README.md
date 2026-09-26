# Legacy Sophia pairing (Hagia-owned)

These are Hagia interoperability cases that used to live inside Sophia's test tree. Sophia's own tree is WM-neutral, so they now live here as an opt-in overlay. The maintained runner (root's Rust pairing runner) installs them into an isolated scratch Sophia checkout. `MOUNTS.tsv` and the commands below are its review and provenance inputs, not a separately maintained installer. The original shell recipes are kept in commit 69fa0c2 for provenance.

An overlaid checkout is "Sophia <commit> + Hagia legacy overlay <manifest sha256>", not exact Sophia source. The overlay drives Sophia's real owners through the same private module access the cases had in place; it adds no Sophia API and duplicates no Sophia runtime owner.

## Provenance (Sophia 0319356db; blob ids in `PROVENANCE.blobs`)

| Overlay file | Came from | Change |
| --- | --- | --- |
| `runtime/pointer_focus_hagia.rs` | `crates/sophia-runtime/tests/support/pointer_focus_hagia.rs` | byte-identical |
| `runtime/presentation_hagia.rs` | `crates/sophia-runtime/tests/support/presentation_hagia.rs` | byte-identical |
| `session/delegated_policy.rs` | `crates/sophia-session/tests/support/delegated_policy.rs` | byte-identical |
| `session/targeted_policy.rs` | `crates/sophia-session/tests/support/content_actions/targeted_policy.rs` | byte-identical |
| `session/policy_partial_projection_socket.rs` | `crates/sophia-session/tests/support/policy_partial_projection_socket.rs` | byte-identical |
| `session/pregraphics_activation.rs` | `hagia_pregraphics_profile_admission_activates_every_owner` in `live_session/profile_preparation_tests.rs` | one module level deeper, so `super::super::session_config_tests` |
| `session/hagia_launch_origin.rs` | the Hagia parts of `launch_origin_socket.rs` (`PolicyFixture`, both `hagia_*` cases, `exercise_output_bookmark`) | the post-map Hagia block becomes `OriginPolicy::place_child` for `PolicyFixture`, with needless borrows removed; test bodies and assertions unchanged |

Sophia keeps the real X child, the production admission policy and a generic `exercise_x_origin` behind the test-local `OriginPolicy` hook. Its own case runs with no policy client.

## Mounts (`MOUNTS.tsv`)

Each row is: overlay file, destination in the Sophia checkout, the file that receives the mount, an anchor line that must occur exactly once in that file, and the mount lines to append at the end of that file. A runner must refuse a checkout that isn't clean, an existing destination, or a missing or ambiguous anchor. It must also record the base commit and a manifest of the overlay files.

## Commands (moved from `tools/check_sophia_policy.sh`, plus the two later moves)

Each command runs in the overlaid checkout, with `SOPHIA_HAGIA_BIN` set to the built Hagia and `XDG_CONFIG_HOME` set to an empty 0700 directory, inside the runner's device-hidden, private-target isolation. A filter that matches nothing exits zero, so every case is first named in a `--list`.

- Pregraphics profile admission:
  `cargo test --offline -q -p sophia-session --features atomic-scanout-live hagia_pregraphics_profile_admission_`.
  The listing must contain `delegated_policy::hagia_pregraphics_profile_admission_rejects_invalid_policy_values` and `hagia_pregraphics_activation::hagia_pregraphics_profile_admission_activates_every_owner`. The original gate had no listing for this filter.
- Pointer focus:
  `cargo test --offline -q -p sophia-runtime --test policy_transport hagia_pointer_focus_`.
  The listing must contain `pointer_focus_hagia::hagia_pointer_focus_real_socket_commits_rejects_and_retries` and `pointer_focus_hagia::hagia_pointer_focus_old_server_reports_the_setting_before_admission`.
- Presentation:
  `cargo test --offline -q -p sophia-runtime --test policy_transport presentation_hagia`.
  The listing must contain the five `presentation_hagia::hagia_*` cases (without presentation actions; overview publishes; timeout retains; revoked closes; reconnect starts closed). `hagia_overview_old_epoch_identity_is_refused_after_reconnect` also runs under this filter, but the original gate did not name it.
- Launch origin:
  `cargo test --offline -q -p sophia-session --features native-session --lib launch_origin_socket`.
  The listing must contain `hagia_launch_origin::hagia_real_x_child_origin_survives_monitor_switch_and_rejection`. `hagia_launch_origin::hagia_output_bookmark_places_empty_output_after_focus_switch_and_rejected_cycle` stays `#[ignore]` and needs `-- --ignored` to run.
- Partial pointer projection (not previously in the gate):
  `cargo test --offline -q -p sophia-session --features native-session --lib hagia_real_partial_pointer_projection_preserves_untouched_output`.
- Two-output targeted click (not previously in the gate; `#[ignore]`, needs an explicit binary):
  `cargo test --offline -q -p sophia-session --features native-session --lib two_output_click_queue_reaches_hagia_without_active_output_retargeting -- --ignored`.

## Retained qualifications

- The presentation receipts are explicit transport fixtures, not evidence of an actual presented frame. Completion from retired frames belongs to Session.
- Pointer focus and presentation drive `PolicyWmSessionTransport` against the Engine reducer, not Session's live owner loop.
- Launch origin uses a real X child and Sophia's production admission policy. The Hagia client runs over current IPC with a focus-follows-mouse profile.
- The two-output targeted click case and the output bookmark case stay `#[ignore]`. The partial pointer projection case skips without `SOPHIA_HAGIA_BIN`.
