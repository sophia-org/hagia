//! Route a focused client's complete key sequence before allowing a real
//! Hagia Held publication to capture. The ingress is local: no X client
//! delivery or hardware input is claimed. Mirror completion is simulated.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;

/// Calls the production router with Engine focus and committed CPU sources.
/// The client-key ledger is populated only by successful routing, never by
/// fixture insertion. Keep ingress records so target and key correlation are
/// observations rather than an inferred count.
fn route_focused(
    routing: &mut Routing,
    run: &mut Lifecycle,
    content: &Content,
    projections: &[LivePresentedInputProjection],
    keys: &[(u32, bool)],
    now: u64,
) -> (
    PhysicalInputRouteReport,
    Vec<sophia_x_authority::XAuthorityRoutedInput>,
) {
    let committed = content.runtime.committed_surfaces();
    let mut input_focus = InputFocusState::new();
    assert_eq!(
        input_focus.focus_surface(SeatId::from_raw(1), focus(run).unwrap(), committed),
        sophia_engine::InputFocusDecision::Focused
    );
    let events = keys
        .iter()
        .map(|&(keycode, pressed)| {
            routing.serial += 1;
            InputEventPacket {
                serial: routing.serial,
                seat: SeatId::from_raw(1),
                device: DeviceId::from_raw(1),
                time_msec: now,
                kind: InputEventKind::Key { keycode, pressed },
                global_position: Some(Point { x: 10.0, y: 10.0 }),
                target_surface: None,
                local_position: None,
            }
        })
        .collect();
    let (sender, receiver) = std::sync::mpsc::sync_channel(64);
    let public = run.wm.public.as_mut().unwrap();
    let protected_actions = public
        .actions
        .iter()
        .filter(|action| action.session_operation_slot.is_some())
        .map(|action| action.action)
        .collect();
    let report = route_input_events_with_launcher(
        events,
        &input_focus,
        committed,
        &[],
        &Default::default(),
        &Default::default(),
        &sender,
        &mut routing.mapper,
        &mut routing.repeat,
        &routing.keymap,
        &mut routing.client_keys,
        &mut routing.emergency,
        &mut routing.terminal,
        &mut routing.coverage,
        run.wm.shortcuts.as_mut(),
        &mut routing.pointer,
        true,
        false,
        false,
        PhysicalInputRoutingMode::Full,
        &mut routing.delivery,
        now,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        None,
        Some(projections[0].output),
        projections[0].epoch,
        Some(projections),
        None,
        None,
        None,
        None,
        &mut routing.coalescer,
        true,
        &mut routing.motion,
        Duration::ZERO,
        Some(PolicyPresentedInputRouting {
            state: &public.presentation_input,
            capture: &mut public.presentation_capture,
            protected_actions,
        }),
    )
    .unwrap();
    (report, receiver.try_iter().collect())
}

fn delivered(
    inputs: &[sophia_x_authority::XAuthorityRoutedInput],
) -> Vec<(SurfaceId, InputEventKind)> {
    inputs
        .iter()
        .map(|input| (input.request.target_surface, input.request.kind))
        .collect()
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_presented_capture_waits_for_focused_application() {
    let Held {
        mut run,
        mut content,
        mut routing,
        idle,
        first,
        next,
        candidates,
        expected,
    } = held("presented-application-capture");
    let w1 = expected[0];
    let key = |keycode, pressed| InputEventKind::Key { keycode, pressed };
    log(
        &run,
        "focus=engine_committed_target application_delivery=local_ingress completion=simulated_per_head receipts=backend_derived",
    );

    // Installation has not presented the capture yet. An actual routed press
    // creates the application-held state before either mirror completes.
    let (report, ingress) =
        route_focused(&mut routing, &mut run, &content, &idle, &[(30, true)], 1200);
    assert_eq!(delivered(&ingress), vec![(w1, key(30, true))]);
    assert!(report.policy_inputs.is_empty());
    assert_eq!(routing.client_keys.pending_non_modifier_len(), 1);

    let mut target = SessionPolicyPresentationFixture::new(&[run.output]);
    assert_eq!(target.heads().len(), 2);
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(first.outputs[0].output);
    for head in 0..2 {
        target.simulate_head_completion(&mut content.runtime, first.outputs[0].output, head);
        service(&mut run, content.runtime.input_projections());
    }
    let presented = content.runtime.input_projections().to_vec();
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(first.outputs[0].output)
        .unwrap();
    assert_eq!(receipt.outcome, PolicyPresentationOutcome::Presented);
    drain(&mut run);
    let requests = run.wm.requests;
    let checkpoint = model(&run);

    let (report, ingress) = route_focused(
        &mut routing,
        &mut run,
        &content,
        &presented,
        &[(RIGHT, true), (RIGHT, false)],
        1300,
    );
    assert!(
        report.policy_inputs.is_empty()
            && delivered(&ingress) == vec![(w1, key(RIGHT, true)), (w1, key(RIGHT, false))],
        "held capture must leave an application-owned key sequence at its focused target"
    );
    assert_eq!(routing.client_keys.pending_non_modifier_len(), 1);
    assert!(!owes(&run, RIGHT));
    let (report, ingress) = route_focused(
        &mut routing,
        &mut run,
        &content,
        &presented,
        &[(30, false)],
        1310,
    );
    assert_eq!(
        delivered(&ingress),
        vec![(w1, key(30, false))],
        "the last application-held key must release to its focused target"
    );
    assert!(report.policy_inputs.is_empty());
    assert_eq!(routing.client_keys.pending_non_modifier_len(), 0);
    assert_eq!(run.wm.requests, requests);
    assert_eq!(model(&run), checkpoint);
    assert!(run.wm.public.as_ref().unwrap().queue.is_empty());

    // Alt remains held by the real switcher's chord. The protected terminal
    // shortcut must bypass that publication's Return binding. Observe the
    // intent only; this fixture does not execute a launch.
    let terminal = run
        .wm
        .command_registry
        .roles
        .get(&TERMINAL_APPLICATION_ID)
        .copied()
        .unwrap_or_else(|| action_id(&run, "spawn-terminal"));
    let (protected, ingress) = route_focused(
        &mut routing,
        &mut run,
        &content,
        &presented,
        &[(28, true)],
        1312,
    );
    assert_eq!(
        protected.policy_inputs,
        vec![PhysicalPolicyInput::Action(terminal)],
        "protected terminal shortcut must bypass the real held publication"
    );
    assert!(ingress.is_empty());
    assert!(
        !owes(&run, 28),
        "protected key must not acquire policy capture debt"
    );
    assert!(is_reserved_session_action(terminal) || run.wm.public.as_ref().unwrap()
        .actions.iter().any(|action| action.action == terminal && action.session_operation_slot == Some(1)));
    let (released, _) = route_focused(
        &mut routing,
        &mut run,
        &content,
        &presented,
        &[(28, false)],
        1313,
    );
    assert!(released.policy_inputs.is_empty());
    assert!(!owes(&run, 28));
    assert_eq!(model(&run), checkpoint);

    let (report, ingress) = route_focused(
        &mut routing,
        &mut run,
        &content,
        &presented,
        &[(RIGHT, true)],
        1320,
    );
    let actions = presented_actions(&report);
    assert!(
        matches!(actions.as_slice(), [action] if action.action == next) && ingress.is_empty(),
        "held capture must resume after the application releases its last key"
    );
    let captured = actions[0];
    assert_eq!(captured.connection_epoch, receipt.connection_epoch);
    assert_eq!(
        captured.identity,
        PolicyPresentationIdentity {
            publication_generation: receipt.publication_generation,
            output: receipt.output,
            output_generation: receipt.output_generation,
            presentation_epoch: receipt.presentation_epoch,
            target_id: 0,
            target_generation: 0,
        }
    );
    assert!(owes(&run, RIGHT));
    routing.dispatch(&mut run, &report);
    let (report, ingress) = route_focused(
        &mut routing,
        &mut run,
        &content,
        &presented,
        &[(RIGHT, false)],
        1330,
    );
    assert!(report.policy_inputs.is_empty() && ingress.is_empty());
    assert!(!owes(&run, RIGHT));
    assert_eq!(routing.client_keys.pending_non_modifier_len(), 0);

    let proposal = run.proposal();
    assert!(
        matches!(in_flight_cause(&run), PolicyRequestCause::PresentationAction { action, identity, .. }
        if action == next && identity == captured.identity)
    );
    assert_eq!(focus(&run), Some(w1));
    let (_, second) = staged_publication(&run).unwrap();
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    drain(&mut run);
    // Supplied completion of the replacement retains the parent's bounded
    // close path. The initial capture above used backend-derived stamps.
    let presented = completed(&content, &second);
    service(&mut run, &presented);
    drain(&mut run);
    let (report, _) = routing.route(&mut run, &presented, &[(ALT, false)], 1400);
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert_eq!(
        proposal.focus,
        Some(expected[2]),
        "the resumed captured action must reach real Hagia"
    );
    let previous = commit_installed(&mut run, &mut content, proposal);
    service(&mut run, &withdrawn(&content));
    settle(&mut run, previous);
    drain(&mut run);
    assert_eq!(focus(&run), Some(expected[2]));
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[2])
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(
        run.wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap()
            .is_none()
    );
    assert!(
        !run.wm.degraded
            && !run.wm.force_transport_restart
            && !run.wm.public.as_ref().unwrap().transport_unavailable,
        "peer healthy before application-capture teardown"
    );
    assert!(run.wm.supervisor.poll().unwrap().is_none());
    run.record("application-capture-committed");
    run.stop();
}
