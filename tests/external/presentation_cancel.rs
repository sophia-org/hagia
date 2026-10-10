//! Cancelling a presented held chord at Session's keyboard-matching boundary.
//! The matching transition is supplied; no seat lock or physical mode change
//! is performed. Content, completion and routing retain the parent's limits.
use super::*;

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_presented_cancel_preserves_focus() {
    let Held {
        mut run,
        mut content,
        mut routing,
        first,
        next,
        candidates,
        expected,
        ..
    } = held("presented-cancel");
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
    run.wm.observe_keyboard_matching(false);
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
        "matching transition must cancel the held chord once"
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
    let (report, _) = routing.route(&mut run, &replaced, &[(ALT, false)], 1400);
    assert!(
        report.policy_inputs.is_empty(),
        "release after cancellation must not end the old chord again"
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());

    // A new chord has its own token and can commit the expected W2 selection.
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
