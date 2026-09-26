//! Moved verbatim from Sophia 0319356db
//! crates/sophia-session/tests/support/live_session/profile_preparation_tests.rs
//! (hagia_pregraphics_profile_admission_activates_every_owner). Mounted by the
//! overlay as a child of that module, so one more `super::` reaches the sibling
//! session_config_tests helpers; nothing else changed.
use super::*;

#[test]
fn hagia_pregraphics_profile_admission_activates_every_owner() {
    let Some(hagia_bin) = std::env::var_os("SOPHIA_HAGIA_BIN") else {
        return;
    };
    let mut config = public_profile_test_config("sophia-hagia-profile-admission-test");
    config.wm_process = Some(hagia_bin.to_string_lossy().into_owned());
    let profile_path = config.wm_socket_path.with_extension("kdl");
    let source = sophia_config::COMPILED_DESKTOP_PROFILE
        .replace("layout \"scroller\"", "layout \"dwindle\"")
        + "\npolicy { scratchpad-size 70 60; floating-size 0 60; preset-column-widths { proportion 0.33; proportion 0.5; proportion 0.67; }; view-name 1 \"code\"; view-name 2 \"web\"; view-layout 1 \"notion\"; view-layout 2 \"split-tree\"; }\n";
    std::fs::write(&profile_path, source).unwrap();
    std::fs::set_permissions(
        &profile_path,
        std::os::unix::fs::PermissionsExt::from_mode(0o600),
    )
    .unwrap();
    let socket_path = config.wm_socket_path.clone();
    config = super::super::session_config_tests::isolated_session_config(&[
        format!("--wm-process={}", hagia_bin.to_string_lossy()),
        "--wm-interface=sophia_wm_v1".to_owned(),
        format!("--desktop-profile={}", profile_path.display()),
    ])
    .unwrap();
    config.wm_socket_path = socket_path;
    std::fs::remove_file(profile_path).unwrap();
    let key = sophia_config::DesktopProfileActivationKey::from(&config.desktop_profile);
    let directory_path = config.wm_socket_path.with_extension("policy");

    let prepared = LiveWmSession::prepare_public_launch(&mut config).unwrap();
    let launch = LiveWmSession::activate_public_launch(&mut config, prepared)
        .unwrap()
        .unwrap();
    let started = &launch;

    assert_eq!(started.profile_key, Some(key));
    assert_eq!(
        config.desktop_profile_activation.phase(),
        sophia_config::DesktopProfileActivationPhase::Idle
    );
    assert_eq!(config.desktop_profile_activation.active(), Some(key));
    for participant in [
        started.policy_profile.slot.participant(),
        started.shell_profile.slot.participant(),
        started.shortcut_profile_slot.participant(),
        config.session_profile.slot().participant(),
        config.input_profile.slot().participant(),
        config.output_profile.slot().participant(),
        started.broker_profile.slot.participant(),
    ] {
        assert_eq!(
            participant.phase(),
            sophia_config::DesktopProfileParticipantPhase::Activated
        );
        assert_eq!(participant.active(), Some(key));
        assert_eq!(participant.candidate(), Some(key));
    }

    drop(launch);
    assert!(!directory_path.exists());
}
