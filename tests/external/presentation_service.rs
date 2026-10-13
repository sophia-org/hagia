//! The actual Session presentation-service owner under availability loss and
//! authenticated requested restart. The prefix installs against a supplied head and observes the
//! initial backend-derived Presented through the parent's abbreviated helper.
//! Thereafter only service_presented_policy revokes, removes runtime policy,
//! and settles withdrawal. Target submit/flip and availability are supplied;
//! no device detection, native installation or scheduling is claimed.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;

fn owner(run: &mut Lifecycle, content: &mut Content, available: bool) {
    run.wm
        .service_presented_policy(&mut content.runtime, &content.scene, None, available, false)
        .unwrap();
}

fn presented_on_mirrors(
    run: &mut Lifecycle,
    content: &mut Content,
    first: &PolicyPresentation,
) -> (SessionPolicyPresentationFixture, PolicyPresentationReceipt) {
    let output = first.outputs[0];
    let mut target = SessionPolicyPresentationFixture::new(&[run.output]);
    let heads = target.heads();
    assert_eq!(heads.len(), 2);
    content
        .runtime
        .validate_policy_presentation_on_heads(
            &LivePolicyPresentation {
                owner_epoch: 1,
                presentation: first.clone(),
            },
            &heads,
        )
        .unwrap();
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    for head in 0..2 {
        target.simulate_head_completion(&mut content.runtime, output.output, head);
        let projections = content.runtime.input_projections().to_vec();
        service(run, &projections);
    }
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(output.output)
        .expect("both heads presented the switcher");
    assert_eq!(
        receipt,
        PolicyPresentationReceipt {
            connection_epoch: 1,
            publication_generation: first.generation,
            output: output.output,
            output_generation: output.generation,
            presentation_epoch: receipt.presentation_epoch,
            outcome: PolicyPresentationOutcome::Presented,
        }
    );
    assert_eq!(receipts(run), vec![receipt]);
    drain(run);

    (target, receipt)
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_presented_service_withdraws_when_unavailable() {
    let Held {
        mut run,
        mut content,
        first,
        candidates,
        expected,
        ..
    } = held("presented-service");
    let output = first.outputs[0];
    let w1 = expected[0];
    log(
        &run,
        "service_owner=production availability=supplied completion=simulated_per_head receipts=backend_derived",
    );
    let (mut target, receipt) = presented_on_mirrors(&mut run, &mut content, &first);

    // Supply only availability loss. A healthy transport and no restart
    // ensure the service's other revocation conditions cannot mask it.
    assert!(!run.wm.degraded && !run.wm.force_transport_restart);
    assert!(!run.wm.public.as_ref().unwrap().transport_unavailable);
    owner(&mut run, &mut content, false);
    assert_eq!(
        receipts(&run),
        vec![PolicyPresentationReceipt {
            outcome: PolicyPresentationOutcome::Revoked,
            ..receipt
        }],
        "unavailable service must revoke the presented identity"
    );
    assert!(
        content.runtime.policy_presentation().is_none(),
        "service withdrawal must remove the installed publication"
    );
    {
        let public = run.wm.public.as_ref().unwrap();
        assert!(public.presentation_input.publication().is_none());
        assert!(public.reducer.presentation_publication().is_none());
    }

    // The first correlated real-peer answer must close the switcher, before
    // any replacement frame. Do not call the fixture's install helper here.
    let (request, answer) = revocation::first_answer(&mut run);
    assert!(matches!(request.cause, PolicyRequestCause::SceneChanged));
    assert!(receipts(&run).is_empty(), "Revoked left before the cycle");
    let revocation::Answer::Proposal(proposal) = answer else {
        panic!("service revocation must receive a closed switcher proposal");
    };
    assert!(
        staged_publication(&run).is_none(),
        "service revocation must close the peer switcher"
    );
    assert_eq!(
        proposal.focus,
        Some(w1),
        "service revocation must not commit a selection"
    );
    let previous = run.checkpoint().1;
    let result = run.layout.commit_proposal(*proposal);
    assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
    run.wm
        .apply_commit_result(result, Some(w1), run.output.id)
        .unwrap();
    settle(&mut run, previous);

    // Retirement is driven independently of the supplied service availability.
    // Even completed replacement facts cannot settle while unavailable.
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    for head in 0..2 {
        target.simulate_head_completion(&mut content.runtime, output.output, head);
        owner(&mut run, &mut content, false);
        assert!(
            receipts(&run).is_empty(),
            "unavailable service must defer Withdrawn even after replacement retirement"
        );
    }
    let projection = &content.runtime.input_projections()[0];
    assert!(projection.frame_completed && !projection.policy_visible);
    // Desired publication is already None, so the real owner's headless
    // install tail is safe. This is not a native publication-install proof.
    owner(&mut run, &mut content, true);
    let withdrawn = PolicyPresentationReceipt {
        outcome: PolicyPresentationOutcome::Withdrawn,
        ..receipt
    };
    assert_eq!(
        receipts(&run),
        vec![withdrawn],
        "available service must settle the retired replacement"
    );
    owner(&mut run, &mut content, true);
    assert_eq!(
        receipts(&run),
        vec![withdrawn],
        "service withdrawal settles once"
    );
    drain(&mut run);
    assert_eq!(focus(&run), Some(w1));
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[0])
    );
    // Availability loss alone does not end the chord; do not silently claim
    // lock cancellation or release handling from this supplied trigger.
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);
    assert_eq!(run.wm.chord_ledger.len(), 1);
    assert!(!owes(&run, RIGHT));
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
            && public.connection_epoch == receipt.connection_epoch
            && public.in_flight_request.is_none()
            && public.queue.is_empty(),
        "peer healthy before service teardown"
    );
    assert!(
        run.wm.supervisor.poll().unwrap().is_none(),
        "peer alive before service teardown"
    );
    run.record("service-withdrawn");
    run.stop();
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_presented_service_revokes_before_requested_restart() {
    let Held {
        mut run,
        mut content,
        first,
        expected,
        ..
    } = held("presented-service-restart");
    let (mut target, receipt) = presented_on_mirrors(&mut run, &mut content, &first);
    let output = first.outputs[0];
    let peer = run.wm.supervisor.peer_id();
    let checkpoint = run.checkpoint();
    let committed = run.wm.public.as_ref().unwrap().reducer.committed();
    let next_epoch = receipt.connection_epoch + 1;

    // Actual requested-restart admission, before the replacement owner polls.
    // Authentication routes this through deliberate restart, not the legacy
    // background control job. It fences inspection but has not revoked input.
    assert!(run.wm.authentication.is_some());
    assert_eq!(
        run.wm.begin_control_restart(run.output).unwrap(),
        next_epoch
    );
    assert!(run.wm.force_transport_restart && !run.wm.degraded);
    assert!(run.wm.control_restart.is_none());
    assert!(!run.wm.authenticated_restart_pending());
    assert!(!run.wm.public.as_ref().unwrap().transport_unavailable);
    assert!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .presentation_input
            .publication()
            .is_some()
    );
    assert!(receipts(&run).is_empty());

    // Available remains true: no availability-loss or transport-unavailable
    // branch can substitute for stopping. The stopping flag also suppresses
    // the no-native installation tail, including in the revocation control.
    owner(&mut run, &mut content, true);
    assert_eq!(
        receipts(&run),
        vec![PolicyPresentationReceipt {
            outcome: PolicyPresentationOutcome::Revoked,
            ..receipt
        }],
        "stopping service must revoke before replacing the peer"
    );
    assert!(content.runtime.policy_presentation().is_none());
    assert_eq!(run.wm.supervisor.peer_id(), peer);
    assert!(run.wm.supervisor.poll().unwrap().is_none());
    assert_eq!(
        run.wm.public.as_ref().unwrap().connection_epoch,
        receipt.connection_epoch
    );
    assert_eq!(run.checkpoint(), checkpoint);

    // The fixture chooses retirement before replacement. Availability permits
    // withdrawal settlement even while stopping; one mirror is insufficient.
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    target.simulate_head_completion(&mut content.runtime, output.output, 0);
    owner(&mut run, &mut content, true);
    let revoked = receipts(&run);
    assert_eq!(revoked.len(), 1);
    assert_eq!(revoked[0].outcome, PolicyPresentationOutcome::Revoked);
    target.simulate_head_completion(&mut content.runtime, output.output, 1);
    owner(&mut run, &mut content, true);
    assert_eq!(
        receipts(&run),
        vec![
            PolicyPresentationReceipt {
                outcome: PolicyPresentationOutcome::Revoked,
                ..receipt
            },
            PolicyPresentationReceipt {
                outcome: PolicyPresentationOutcome::Withdrawn,
                ..receipt
            },
        ],
        "available stopping service must settle the retired replacement"
    );
    owner(&mut run, &mut content, true);
    assert_eq!(receipts(&run).len(), 2, "stopping receipts settle once");
    // Queued receipts are observed locally; no old-peer delivery is claimed.
    run.record("requested-stop-withdrawn");

    run.ready(true);
    assert_eq!(run.wm.public.as_ref().unwrap().connection_epoch, next_epoch);
    assert_ne!(run.wm.supervisor.peer_id(), peer);
    assert_eq!(
        run.checkpoint(),
        checkpoint,
        "requested replacement preserves the committed checkpoint"
    );
    assert_eq!(
        run.wm.public.as_ref().unwrap().reducer.committed(),
        committed
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    for _ in 0..2 {
        let proposal = run.proposal();
        assert!(
            staged_publication(&run).is_none(),
            "replacement must not resurrect the stopped switcher"
        );
        assert_eq!(proposal.focus, Some(expected[0]));
        let previous = commit_installed(&mut run, &mut content, proposal);
        settle(&mut run, previous);
    }
    assert_eq!(focus(&run), Some(expected[0]));
    assert!(content.runtime.policy_presentation().is_none());
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
            && public.connection_epoch == next_epoch
            && public.in_flight_request.is_none()
            && public.queue.is_empty(),
        "replacement healthy before stopping-service teardown"
    );
    assert!(
        run.wm.supervisor.poll().unwrap().is_none(),
        "replacement alive before stopping-service teardown"
    );
    run.record("requested-stop-recovered");
    run.stop();
}
