#[allow(dead_code)]
#[path = "../src/overlay.rs"]
mod overlay;
#[allow(dead_code)]
#[path = "../src/acceptance.rs"]
mod wm_file_acceptance;

// These tests import the tool modules directly, without launching Cargo or a
// paired process. Production orchestration uses the same validation helpers.
use wm_file_acceptance as acceptance;
#[allow(dead_code)]
#[path = "../src/legacy.rs"]
mod legacy;

#[test]
fn absent_feature_or_filtered_owner_fixture_cannot_pass() {
    for log in [
        "",
        "test result: ok. 0 passed; 0 failed; 0 ignored; 8 filtered out;",
        "test result: ok. 0 passed; 0 failed; 1 ignored; 0 filtered out;",
        "test result: FAILED. 0 passed; 1 failed; 0 ignored;",
        "test result: ok. 2 passed; 0 failed; 0 ignored;",
        "test result: ok. 1 ignored; 0 failed; 0 passed;",
        "test result: ok. 1 passed; 0 failed; 0 ignored;\ntest result: FAILED. 0 passed; 1 failed; 0 ignored;",
    ] {
        assert!(
            wm_file_acceptance::require_exactly_one(log).is_err(),
            "{log}"
        );
    }
    assert!(
        wm_file_acceptance::require_exactly_one(
            "test result: ok. 1 passed; 0 failed; 0 ignored; 9 filtered out; finished in 0.1s\n"
        )
        .is_ok()
    );
}

#[test]
fn incomplete_or_duplicate_test_listing_is_refused() {
    for listing in ["", "unrelated::case: test\n", "0 tests, 0 benchmarks\n"] {
        assert!(wm_file_acceptance::required_tests(listing).is_err());
    }
    let prefix = "live_session::reload::tests::desktop_launch_reload::policy_hagia_session::";
    let names = [
        "protected_normal_hagia_admits_profile_configuration_and_catalog_over_files",
        "normal_hagia_held_resize_commits_then_answers_a_fresh_request",
        "normal_hagia_timed_out_session_action_keeps_checkpoint_and_answers_next_request",
        "normal_hagia_current_ipc_and_files_preserve_layout_settlement",
        "real_hagia_resize_reaches_cpu_production_engine_commit",
        "real_hagia_timeout_keeps_cpu_production_state",
        "normal_hagia_committed_action_returns_intent_and_answers_next_request",
        "normal_hagia_behavior_corpus_matches_over_current_ipc_and_files",
        "normal_hagia_checkpoint_restore_survives_automatic_and_control_restart_on_both_wires",
        "normal_hagia_behavior_coverage_matches_over_current_ipc_and_files",
        "normal_hagia_receipts_follow_mirrored_backend_completion_on_both_wires",
        "normal_hagia_profile_replacement_and_rejection_roll_back_on_both_wires",
    ];
    let listing: String = names
        .iter()
        .map(|name| format!("{prefix}owner::{name}: test\n"))
        .collect();
    assert_eq!(
        wm_file_acceptance::required_tests(&listing).unwrap().len(),
        names.len()
    );
    assert!(wm_file_acceptance::required_tests(&format!("{listing}{listing}")).is_err());
    assert!(
        wm_file_acceptance::required_tests(&format!(
            "{listing}{prefix}other::{}: test\n",
            names[0]
        ))
        .is_err()
    );
    for missing in names {
        let incomplete = listing
            .lines()
            .filter(|line| !line.contains(missing))
            .collect::<Vec<_>>()
            .join("\n");
        assert!(
            wm_file_acceptance::required_tests(&incomplete).is_err(),
            "{missing}"
        );
    }
}

#[test]
fn legacy_case_must_be_named_exactly_once() {
    let name = "hagia_real_x_child_origin_survives_monitor_switch_and_rejection";
    assert!(legacy::named_test("", name).is_err());
    assert!(legacy::named_test("unrelated: test\n", name).is_err());
    let entry = format!("parent::{name}: test\n");
    assert_eq!(
        legacy::named_test(&entry, name).unwrap(),
        format!("parent::{name}")
    );
    assert!(legacy::named_test(&format!("{entry}{entry}"), name).is_err());
}

#[test]
fn listed_binary_requires_the_expected_cargo_launch_kind() {
    for entry in ["unittests src/lib.rs", "tests/policy_transport.rs"] {
        let line = format!("     Running {entry} (/private/target/test)\n");
        assert_eq!(
            acceptance::listed_path(&line, entry).unwrap(),
            "/private/target/test"
        );
        assert!(acceptance::listed_path(&format!("{line}{line}"), entry).is_err());
        assert!(acceptance::listed_path("unrelated (/private/target/test)", entry).is_err());
        assert!(
            acceptance::listed_path("Running arbitrary (/private/target/test)", entry).is_err()
        );
    }
    assert!(
        acceptance::listed_path(
            "Running tests/policy_transport.rs (/private/target/test)",
            "unittests src/lib.rs"
        )
        .is_err()
    );
}
