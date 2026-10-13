//! Automatic replacement with an unsettled captured action and an owed key
//! release. Uses the parent's supplied presentation and input boundaries.
use super::*;

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_presented_disconnect_preserves_release_debt() {
    let Held {
        mut run,
        mut content,
        mut routing,
        first,
        next,
        candidates,
        expected,
        ..
    } = held("presented-disconnect");
    let w1 = expected[0];
    let presented = completed(&content, &first);
    service(&mut run, &presented);
    let (pointer, ingress) = routing.route_pointer(&mut run, &presented, true, 1290);
    assert!(pointer.policy_inputs.is_empty());
    assert_eq!(
        (ingress, pointer.pointer_buttons_suppressed_no_target),
        (0, 0)
    );
    assert!(
        owes_pointer(&run, 0x110),
        "captured pointer press must owe its release"
    );
    let (report, ingress) = routing.route(&mut run, &presented, &[(RIGHT, true)], 1300);
    let actions = presented_actions(&report);
    assert!(matches!(actions[..], [action] if action.action == next));
    let captured = actions[0];
    assert_eq!((ingress, report.keys_suppressed_no_focus), (0, 0));
    assert!(owes(&run, RIGHT), "captured Right must owe its release");
    routing.dispatch(&mut run, &report);
    drain(&mut run);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::PresentationAction { action, identity, .. }
            if action == next && identity == captured.identity
    ));
    assert!(staged_publication(&run).is_some());
    assert!(
        run.layout.pending.is_none(),
        "this case excludes AbortSettlement"
    );
    let epoch = captured.connection_epoch;
    let peer = run.wm.supervisor.peer_id();
    let saved = run.checkpoint();
    let committed = run.wm.public.as_ref().unwrap().reducer.committed();
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);
    assert_eq!(run.wm.chord_ledger.len(), 1);

    run.wm.supervisor.request_termination().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while run.wm.public.as_ref().unwrap().connection_epoch == epoch {
        assert!(run.poll_restart().unwrap().is_none());
        assert!(!run.wm.degraded);
        assert!(
            Instant::now() < deadline,
            "captured disconnect restart deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
    // The old proposal has no settlement authority in the successor epoch.
    drop(proposal);
    assert!(
        owes(&run, RIGHT),
        "disconnect must preserve captured Right release debt"
    );
    assert!(
        owes_pointer(&run, 0x110),
        "disconnect must preserve captured pointer release debt"
    );
    let public = run.wm.public.as_ref().unwrap();
    assert_eq!(public.connection_epoch, epoch + 1);
    assert_ne!(run.wm.supervisor.peer_id(), peer);
    assert!(public.presentation_input.publication().is_none());
    assert!(public.reducer.presentation_publication().is_none());
    assert!(public.staged.is_none() && public.prepared.is_none());
    assert!(public.in_flight_request.is_none() && !public.cycle_submitted);
    assert_eq!(public.reducer.committed(), committed);
    assert_eq!(
        run.checkpoint(),
        saved,
        "disconnect cannot commit the captured action"
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    log(
        &run,
        "phase=replaced debt=Right credits=full unsettled_action=discarded",
    );

    run.ready(true);
    let queued = run.wm.public.as_ref().unwrap().queue.len();
    run.wm.enqueue_presented_action(captured).unwrap();
    assert_eq!(
        run.wm.public.as_ref().unwrap().queue.len(),
        queued,
        "replacement must reject the old presented identity"
    );

    // No pixels are observed here. Supplied withdrawn projections ensure the
    // only reason to swallow this release is the retained input obligation.
    let replaced = withdrawn(&content);
    let (pointer, ingress) = routing.route_pointer(&mut run, &replaced, false, 1390);
    assert!(pointer.policy_inputs.is_empty());
    assert_eq!(
        (ingress, pointer.pointer_buttons_suppressed_no_target),
        (0, 0),
        "owed pointer release must be swallowed after replacement"
    );
    assert!(!owes_pointer(&run, 0x110));
    let (pointer, ingress) = routing.route_pointer(&mut run, &replaced, false, 1391);
    assert!(pointer.policy_inputs.is_empty());
    assert_eq!(
        (ingress, pointer.pointer_buttons_suppressed_no_target),
        (0, 1),
        "duplicate pointer release must reach ordinary no-target routing"
    );
    let (report, ingress) = routing.route(&mut run, &replaced, &[(RIGHT, false)], 1400);
    assert!(report.policy_inputs.is_empty());
    assert_eq!(
        (ingress, report.keys_suppressed_no_focus),
        (0, 0),
        "owed release must be swallowed before client routing"
    );
    assert!(!owes(&run, RIGHT), "owed release must retire exactly once");
    let (report, ingress) = routing.route(&mut run, &replaced, &[(RIGHT, false)], 1410);
    assert!(report.policy_inputs.is_empty());
    assert_eq!(
        (ingress, report.keys_suppressed_no_focus),
        (0, 1),
        "unowed release must reach the ordinary no-focus path"
    );
    let (report, _) = routing.route(&mut run, &replaced, &[(ALT, false)], 1420);
    assert!(
        report.policy_inputs.is_empty(),
        "old chord must not end in the new epoch"
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);

    // The replacement answers its own scene and checkpoint-refresh requests.
    for _ in 0..2 {
        let proposal = run.proposal();
        assert!(matches!(
            in_flight_cause(&run),
            PolicyRequestCause::SceneChanged
        ));
        assert!(
            staged_publication(&run).is_none(),
            "checkpoint cannot restore modal authority"
        );
        assert_eq!(proposal.focus, Some(w1));
        let previous = commit_installed(&mut run, &mut content, proposal);
        settle(&mut run, previous);
        assert_eq!(
            run.wm.public.as_ref().unwrap().reducer.committed(),
            committed
        );
    }
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[0])
    );
    drain(&mut run);

    // A fresh routed chord remains usable after both old physical keys ended.
    let (report, _) = routing.route(&mut run, &replaced, &[(ALT, true), (TAB, true)], 1500);
    assert!(matches!(
        report.policy_inputs[..],
        [PhysicalPolicyInput::ChordAction(_)]
    ));
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::ChordAction { .. }
    ));
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    let (report, _) = routing.route(&mut run, &replaced, &[(TAB, false), (ALT, false)], 1510);
    assert!(matches!(
        report.policy_inputs[..],
        [PhysicalPolicyInput::Chord(
            sophia_engine::WmChordEvent::Ended {
                end: PolicyChordEnd::Released,
                ..
            }
        )]
    ));
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert_eq!(
        proposal.focus,
        Some(expected[1]),
        "fresh chord must commit W2 after replacement"
    );
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    drain(&mut run);
    assert_eq!(focus(&run), Some(expected[1]));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    assert!(!owes(&run, RIGHT));
    log(
        &run,
        "phase=recovered owed_release=consumed duplicate_release=no_focus fresh_chord=W2",
    );
    run.record("captured-disconnect-recovered");
    run.stop();
}
