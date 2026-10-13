//! Profile-gated Session pointer focus with real Hagia. Production routing
//! derives hover from supplied input/layers; layout completion is supplied.
use super::pointer::PointerRouting;
use super::*;
use crate::live_session::PresentedPointerFocus;

const DESKTOP: &str = "schema 1\nshell { enabled #false; }\nsession { terminal \"terminal\"; browser \"brave-origin\"; startup \"panel\"; }\nshortcut { profile \"default\"; }\npolicy { focus-follows-mouse #true; }\n";

fn refused(run: &mut Lifecycle, observation: PresentedPointerFocus, message: &str) {
    let public = run.wm.public.as_ref().unwrap();
    assert!(public.queue.is_empty() && public.in_flight_request.is_none());
    let requests = run.wm.requests;
    let committed = public.reducer.committed();
    let saved = run.checkpoint();
    assert_eq!(
        run.wm.enqueue_pointer_focus(observation),
        LiveWmRequestAdmission::Duplicate,
        "{message}"
    );
    let public = run.wm.public.as_ref().unwrap();
    assert!(public.queue.is_empty() && public.in_flight_request.is_none());
    assert_eq!(run.wm.requests, requests);
    assert_eq!(public.reducer.committed(), committed);
    assert_eq!(run.checkpoint(), saved);
}

fn hover(
    run: &mut Lifecycle,
    routing: &mut PointerRouting,
    target: SurfaceId,
) -> Option<PresentedPointerFocus> {
    routing.target = target;
    let geometry = run.layout.layers[&target].geometry;
    let point = Point {
        x: f64::from(geometry.x + geometry.width / 2),
        y: f64::from(geometry.y + geometry.height / 2),
    };
    let report = routing.route(run, InputEventKind::PointerMotion, point);
    let expected = PresentedPointerFocus {
        output: run.output.id,
        target: Some(target),
    };
    assert_eq!(
        report.policy_inputs,
        vec![PhysicalPolicyInput::Hover(expected)],
        "routed motion must identify the exact hovered output and surface"
    );
    assert!(report.wm_pointer_interactions.is_empty());
    // Same admission and dispatch owners as the guarded production macro.
    let mut queue = PhysicalPolicyInputQueue::default();
    queue.synchronize(Some(run.wm.public.as_ref().unwrap().connection_epoch));
    let enabled = run.wm.pointer_focus_enabled();
    for input in report.policy_inputs {
        assert!(queue.admit(input, enabled, run.wm.shortcuts.as_mut()));
    }
    let observation = match queue.next(run.wm.pointer_focus_pending()) {
        Some(PhysicalPolicyInput::Hover(observation)) => Some(observation),
        None => None,
        other => panic!("unexpected routed policy input: {other:?}"),
    };
    assert!(queue.next(false).is_none());
    observation
}

fn answer(run: &mut Lifecycle, routing: &mut PointerRouting, target: SurfaceId) -> LiveWmProposal {
    let observation = hover(run, routing, target).expect("enabled hover reaches admission");
    let before = focus(run);
    let saved = run.checkpoint();
    let layers = run.layout.layers.clone();
    assert_eq!(
        run.wm.enqueue_pointer_focus(observation),
        LiveWmRequestAdmission::Admitted,
        "fresh pointer focus must be admitted"
    );
    assert!(run.wm.pointer_focus_pending());
    assert_eq!(
        run.wm.enqueue_pointer_focus(observation),
        LiveWmRequestAdmission::Duplicate
    );
    assert_eq!(run.wm.public.as_ref().unwrap().queue.len(), 1);
    let proposal = run.proposal();
    let public = run.wm.public.as_ref().unwrap();
    assert_eq!(
        public.in_flight_source,
        Some(LiveWmProposalSource::PointerFocus)
    );
    assert!(
        matches!(public.in_flight_request.as_ref().unwrap().cause,
        PolicyRequestCause::PointerFocus { output, target: Some(t) }
        if output == run.output.id && t == target),
        "peer answer must name the admitted hover"
    );
    assert_eq!(
        proposal.focus,
        Some(target),
        "real Hagia must propose the hovered focus"
    );
    assert_eq!(
        focus(run),
        before,
        "hover cannot publish focus before commit"
    );
    assert_eq!(run.layout.layers, layers);
    assert_eq!(
        run.checkpoint(),
        saved,
        "hover cannot save an uncommitted candidate"
    );
    proposal
}

fn healthy(run: &mut Lifecycle) {
    assert!(
        run.wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap()
            .is_none()
    );
    let public = run.wm.public.as_ref().unwrap();
    assert!(
        !run.wm.degraded
            && !run.wm.force_transport_restart
            && !public.transport_unavailable
            && public.connection_epoch == 1
            && public.queue.is_empty()
            && public.in_flight_request.is_none(),
        "peer healthy before pointer-focus teardown"
    );
    assert!(run.wm.supervisor.poll().unwrap().is_none());
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_pointer_focus_requires_profile_and_commit() {
    let mut disabled = Lifecycle::new("pointer-focus-disabled");
    populate(&mut disabled);
    let target = SURFACES
        .into_iter()
        .find(|s| Some(*s) != focus(&disabled))
        .unwrap();
    assert!(!disabled.wm.pointer_focus_enabled());
    let mut routing = PointerRouting::new(disabled.output);
    assert_eq!(
        hover(&mut disabled, &mut routing, target),
        None,
        "unnegotiated hover must be discarded by the physical-input queue"
    );
    let observation = PresentedPointerFocus {
        output: disabled.output.id,
        target: Some(target),
    };
    refused(
        &mut disabled,
        observation,
        "unnegotiated pointer focus must not enter the owner queue",
    );
    healthy(&mut disabled);
    disabled.record("pointer-focus-disabled");
    disabled.stop();

    let mut run = Lifecycle::with_profile("pointer-focus-enabled", DESKTOP);
    populate(&mut run);
    assert!(run.wm.pointer_focus_enabled());
    let mut routing = PointerRouting::new(run.output);
    let before = focus(&run).unwrap();
    let target = SURFACES.into_iter().find(|s| *s != before).unwrap();
    let output = run.output.id;
    refused(
        &mut run,
        PresentedPointerFocus {
            output,
            target: Some(SurfaceId::new(target.index(), target.generation() + 1)),
        },
        "stale hover identity must not target a current numeric surface",
    );
    refused(
        &mut run,
        PresentedPointerFocus {
            output: OutputId::from_raw(99),
            target: None,
        },
        "hover on a departed output must be refused",
    );
    refused(
        &mut run,
        PresentedPointerFocus {
            output,
            target: Some(before),
        },
        "already focused hover must not start a cycle",
    );
    refused(
        &mut run,
        PresentedPointerFocus {
            output,
            target: None,
        },
        "empty hover on the active output must not start a cycle",
    );

    let saved = run.checkpoint();
    let committed = run.wm.public.as_ref().unwrap().reducer.committed();
    let proposal = answer(&mut run, &mut routing, target);
    let refused_identity = proposal.policy_settlement.unwrap();
    run.wm
        .apply_commit_result(
            LiveWmCommitResult {
                update: WmTransactionUpdate {
                    commit: TransactionCommit {
                        transaction: proposal.transaction,
                        outcome: TransactionOutcome::TimedOut,
                        applied_surfaces: vec![],
                    },
                },
                source: proposal.source,
                policy_settlement: proposal.policy_settlement,
            },
            Some(before),
            output,
        )
        .unwrap();
    run.ready(false);
    assert!(!run.wm.pointer_focus_pending());
    assert_eq!(
        run.wm.public.as_ref().unwrap().reducer.committed(),
        committed,
        "refused hover must preserve committed focus"
    );
    assert_eq!(run.checkpoint(), saved);
    let recovery = run.proposal();
    assert!(matches!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .in_flight_request
            .as_ref()
            .unwrap()
            .cause,
        PolicyRequestCause::SceneChanged
    ));
    assert_eq!(
        recovery.focus,
        Some(before),
        "recovery must not replay refused hover"
    );
    assert_eq!(
        run.checkpoint(),
        saved,
        "peer recovery confirms the refusal without promotion"
    );
    run.commit(recovery);
    let proposal = answer(&mut run, &mut routing, target);
    let fresh = proposal.policy_settlement.unwrap();
    assert_eq!(fresh.connection_epoch, refused_identity.connection_epoch);
    assert!(fresh.request_id > refused_identity.request_id);
    assert_ne!(fresh.transaction, refused_identity.transaction);
    run.commit(proposal);
    assert_eq!(
        focus(&run),
        Some(target),
        "only committed hover changes focus"
    );
    assert_checkpoint(&run);
    healthy(&mut run);
    run.record("pointer-focus-committed-after-refusal");
    run.stop();
}
