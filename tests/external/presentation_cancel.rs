//! Cancelling a presented held chord at Session's matching and lock boundaries.
//! The lock case calls the production keyboard-reset owner with supplied lock
//! entry; it never acquires a lock or changes a physical session. Content,
//! completion and routing retain the parent's limits.
use super::*;

#[derive(Clone, Copy, PartialEq)]
enum CancellationBoundary {
    Matching,
    Lock,
    Registry,
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_presented_cancel_preserves_focus() {
    cancel_preserves_focus(CancellationBoundary::Matching);
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_presented_lock_reset_preserves_focus() {
    cancel_preserves_focus(CancellationBoundary::Lock);
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_presented_registry_replacement_cancels_chord() {
    cancel_preserves_focus(CancellationBoundary::Registry);
}

fn cancel_preserves_focus(boundary: CancellationBoundary) {
    let lock_boundary = boundary == CancellationBoundary::Lock;
    let Held {
        mut run,
        mut content,
        mut routing,
        first,
        next,
        candidates,
        expected,
        ..
    } = held(match boundary {
        CancellationBoundary::Matching => "presented-cancel",
        CancellationBoundary::Lock => "presented-lock-reset",
        CancellationBoundary::Registry => "presented-registry",
    });
    let w1 = expected[0];
    let presented = completed(&content, &first);
    service(&mut run, &presented);
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(first.outputs[0].output)
        .unwrap();
    assert_eq!(receipt.outcome, PolicyPresentationOutcome::Presented);
    assert_eq!(receipts(&run), vec![receipt]);
    drain(&mut run);
    assert!(!owes(&run, RIGHT));
    assert_eq!(run.wm.chord_ledger.len(), 1);
    let (&token, &record) = run.wm.chord_ledger.iter().next().unwrap();
    assert_eq!(record.action, next);
    let epoch = run.wm.public.as_ref().unwrap().connection_epoch;
    let peer = run.wm.supervisor.peer_id();

    // Same owner calls as a turn leaving keyboard matching. No release and
    // no revocation receipt can close the peer's model before Cancelled.
    run.wm.observe_keyboard_matching(true);
    let restore_registry = if boundary == CancellationBoundary::Registry {
        let checkpoint = run.checkpoint();
        let profile = run.profile_key();
        let path = run.source.config.desktop_profile_source.as_ref().unwrap();
        std::fs::write(path, format!("{DESKTOP}\npolicy {{ view-count 8; }}\n")).unwrap();
        assert_eq!(
            run.wm
                .reload_desktop_profile(&mut run.source.config)
                .unwrap(),
            DesktopProfileReloadOutcome::Deferred,
            "held chord must defer desktop profile replacement"
        );
        assert_eq!(run.checkpoint(), checkpoint);
        assert_eq!(run.profile_key(), profile);
        assert!(!run.wm.force_transport_restart && !run.wm.desktop_reload_pending());
        std::fs::write(
            run.source.config.desktop_profile_source.as_ref().unwrap(),
            DESKTOP,
        )
        .unwrap();
        let configuration = run
            .wm
            .public
            .as_ref()
            .unwrap()
            .accepted_configuration
            .as_ref()
            .unwrap()
            .clone();
        let original = resolve_public_shortcuts(
            &run.source.config.shortcut_profile_candidate,
            &configuration,
            configuration.generation,
            &run.wm.command_registry,
        )
        .unwrap();
        let replacement = sophia_engine::WmShortcutRegistry::new(
            &[],
            WmCapabilities::all_supported(),
            configuration.generation + 1,
            configuration.chrome,
        )
        .unwrap();
        run.wm
            .install_shortcuts(replacement, &configuration.action_lifecycles);
        assert_eq!(run.wm.shortcuts.as_ref().unwrap().binding_count(), 0);
        log(
            &run,
            "registry_candidate=supplied registry_replacement=production profile_reload_while_held=deferred",
        );
        Some((original, configuration.action_lifecycles))
    } else {
        run.wm.observe_keyboard_matching(false);
        None
    };
    if lock_boundary {
        let seat = SeatId::from_raw(1);
        assert_ne!(
            run.wm.shortcuts.as_ref().unwrap().modifier_mask(seat).bits,
            0,
            "the occupied chord must enter the lock with a modifier held"
        );
        let mut launcher = sophia_engine::LauncherKeyboard::new(
            "evdev",
            "pc105",
            "us",
            "",
            "",
            std::ffi::OsStr::new("C.UTF-8"),
        )
        .unwrap();
        launcher.observe(ALT, true, false);
        crate::live_session::locked::reset_desktop_keyboard_for_lock(
            seat,
            run.wm.shortcuts.as_mut(),
            &mut routing.mapper,
            &mut launcher,
        );
        assert_eq!(
            run.wm.shortcuts.as_ref().unwrap().modifier_mask(seat).bits,
            0,
            "lock reset must forget the old chord's held modifier"
        );
        assert!(!launcher.command_modifier_active());
        log(
            &run,
            "lock_entry=supplied keyboard_reset=production lock_provider=not_started",
        );
    }
    let mut report = PhysicalInputRouteReport::default();
    report.policy_inputs.extend(
        run.wm
            .service_shortcuts(1300)
            .into_iter()
            .map(PhysicalPolicyInput::from_shortcut),
    );
    assert!(
        matches!(report.policy_inputs[..], [PhysicalPolicyInput::Chord(
        sophia_engine::WmChordEvent::Ended { token: actual, end: PolicyChordEnd::Cancelled }
    )] if actual == token),
        "cancellation boundary must cancel the held chord once"
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);
    run.wm.observe_keyboard_matching(false);
    assert!(
        run.wm.service_shortcuts(1301).is_empty(),
        "repeated nonmatching turn must not cancel twice"
    );
    assert!(receipts(&run).is_empty());
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert!(
        matches!(in_flight_cause(&run), PolicyRequestCause::ActionLifecycle {
        activation_serial, action, count, phase: PolicyChordPhase::Ended(PolicyChordEnd::Cancelled)
    } if activation_serial == record.serial && action == record.action && count == record.count),
        "cancel answer must belong to the exact admitted chord"
    );
    assert_eq!(run.wm.public.as_ref().unwrap().connection_epoch, epoch);
    assert_eq!(run.wm.supervisor.peer_id(), peer);
    assert!(!run.wm.degraded && !run.wm.force_transport_restart);
    assert!(
        staged_publication(&run).is_none(),
        "cancelled chord must close the switcher"
    );
    assert_eq!(
        proposal.focus,
        Some(w1),
        "cancelled chord must not commit the switcher selection"
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    log(
        &run,
        &format!(
            "phase=cancel-answer epoch={epoch} token={token:?} serial={} focus={w1:?}",
            record.serial
        ),
    );

    let previous = commit_installed(&mut run, &mut content, proposal);
    assert_eq!(
        receipts(&run),
        vec![PolicyPresentationReceipt {
            outcome: PolicyPresentationOutcome::Revoked,
            ..receipt
        }]
    );
    settle(&mut run, previous);
    drain(&mut run);
    assert_eq!(focus(&run), Some(w1));
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[0])
    );
    let replaced = withdrawn(&content);
    service(&mut run, &replaced);
    assert_eq!(
        receipts(&run),
        vec![PolicyPresentationReceipt {
            outcome: PolicyPresentationOutcome::Withdrawn,
            ..receipt
        }]
    );
    drain(&mut run);

    // Restore matching before routing the old physical release: cancellation
    // must already have ended that chord, so this cannot emit a second Ended.
    run.wm.observe_keyboard_matching(true);
    if lock_boundary {
        // The lock consumed the old modifier release. A bare Tab after
        // returning to desktop routing must not borrow that old authority.
        let (report, _) = routing.route(&mut run, &replaced, &[(TAB, true), (TAB, false)], 1390);
        assert!(
            report.policy_inputs.is_empty(),
            "input after lock reset must not reopen a chord using the old modifier"
        );
        assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    }
    let (report, _) = routing.route(&mut run, &replaced, &[(ALT, false)], 1400);
    assert!(
        report.policy_inputs.is_empty(),
        "release after cancellation must not end the old chord again"
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());

    // A new chord has its own token and can commit the expected W2 selection.
    if let Some((registry, interests)) = restore_registry {
        let (report, _) = routing.route(
            &mut run,
            &replaced,
            &[(ALT, true), (TAB, true), (TAB, false), (ALT, false)],
            1450,
        );
        assert!(
            report.policy_inputs.is_empty(),
            "removed registry binding must not admit an old action"
        );
        run.wm.install_shortcuts(registry, &interests);
    }
    let (report, _) = routing.route(&mut run, &replaced, &[(ALT, true), (TAB, true)], 1500);
    let [PhysicalPolicyInput::ChordAction(chorded)] = report.policy_inputs[..] else {
        panic!("fresh chord must open after cancellation");
    };
    assert!(chorded.chord.opens && chorded.action == next);
    assert_ne!(chorded.chord.token, token);
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    let (report, _) = routing.route(&mut run, &replaced, &[(TAB, false), (ALT, false)], 1510);
    assert!(
        matches!(report.policy_inputs[..], [PhysicalPolicyInput::Chord(
        sophia_engine::WmChordEvent::Ended { token: actual, end: PolicyChordEnd::Released }
    )] if actual == chorded.chord.token)
    );
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert_eq!(
        proposal.focus,
        Some(expected[1]),
        "fresh released chord must commit W2"
    );
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    drain(&mut run);
    assert_eq!(focus(&run), Some(expected[1]));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    run.record("cancelled-chord-recovered");
    run.stop();
}
