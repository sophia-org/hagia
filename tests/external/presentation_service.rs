//! The actual Session presentation-service owner under supplied availability
//! loss. The prefix still installs against a supplied head and observes the
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
        service(&mut run, &projections);
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
    assert_eq!(receipts(&run), vec![receipt]);
    drain(&mut run);

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
