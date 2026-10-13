//! Session-initiated revocation of the presented switcher reaching Hagia's
//! model, with the parent case's supplied boundaries. The revoking input is a
//! supplied completed frame that still shows policy content but carries no
//! publication stamp. Session exposes no refusal-reason record when it
//! rejects a staged projection, so the cause of such a refusal (for example a
//! stale presentation generation) is a source inference, not an observation.
//! Only scene-advanced staleness has diagnostic accounting.
use super::*;

/// How the one request admitted after the revocation was answered.
pub(super) enum Answer {
    /// The peer's proposal for exactly that request, staged by Session.
    Proposal(Box<LiveWmProposal>),
    /// The request settled without a staged proposal, transport healthy.
    Settled,
}

/// Admit exactly one cycle and capture its full request at admission, then
/// poll without admitting any other until that request is answered. Every
/// later poll refuses new cycles, so no other request can be the answer.
pub(super) fn first_answer(run: &mut Lifecycle) -> (PolicyProjectionRequest, Answer) {
    let deadline = Instant::now() + Duration::from_secs(5);
    let epoch = {
        let public = run.wm.public.as_ref().unwrap();
        assert!(
            public.in_flight_request.is_none(),
            "a request is already in flight"
        );
        assert!(public.staged.is_none(), "a proposal is already staged");
        assert!(!public.cycle_submitted, "a cycle is already submitted");
        public.connection_epoch
    };
    let healthy = |run: &Lifecycle| {
        let public = run.wm.public.as_ref().unwrap();
        assert!(
            !run.wm.degraded && !run.wm.force_transport_restart && !public.transport_unavailable,
            "transport failed before the first answer"
        );
        assert_eq!(public.connection_epoch, epoch, "the peer was replaced");
    };
    let request = loop {
        assert!(
            run.wm
                .poll_public_request(&mut run.layout, run.output, true)
                .unwrap()
                .is_none(),
            "a proposal arrived with no request outstanding"
        );
        healthy(run);
        if let Some(request) = run.wm.public.as_ref().unwrap().in_flight_request.clone() {
            break request;
        }
        assert!(
            Instant::now() < deadline,
            "revocation cycle admission deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    };
    assert_eq!(request.connection_epoch, epoch);
    let answer = loop {
        let proposal = run
            .wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap();
        healthy(run);
        let public = run.wm.public.as_ref().unwrap();
        if let Some(proposal) = proposal {
            let identity = proposal.policy_settlement.unwrap();
            assert_eq!(
                (
                    identity.connection_epoch,
                    identity.request_id,
                    identity.scene_generation
                ),
                (
                    request.connection_epoch,
                    request.request_id,
                    request.scene_generation
                ),
                "the proposal answers another request"
            );
            assert_eq!(public.in_flight_request.as_ref(), Some(&request));
            assert!(public.staged.is_some());
            break Answer::Proposal(Box::new(proposal));
        }
        match public.in_flight_request.as_ref() {
            Some(current) => assert_eq!(current, &request, "another request was admitted"),
            None => {
                assert!(public.staged.is_none() && !public.cycle_submitted);
                break Answer::Settled;
            }
        }
        assert!(Instant::now() < deadline, "first answer deadline");
        std::thread::sleep(Duration::from_millis(2));
    };
    (request, answer)
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_presented_revocation_closes_switcher() {
    let Held {
        mut run,
        mut content,
        mut routing,
        first,
        candidates,
        expected,
        ..
    } = held("presented-revocation");
    let output = first.outputs[0];
    let w1 = expected[0];

    // Supplied completion: one Presented receipt. No key is captured, so
    // nothing is owed.
    let presented = completed(&content, &first);
    service(&mut run, &presented);
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(output.output)
        .unwrap();
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
    assert!(!owes(&run, RIGHT));
    drain(&mut run);

    // A supplied completed frame that still shows policy content without the
    // publication's stamp. Policy stays visible, so this is not a replacement
    // frame and cannot settle a withdrawal.
    let mut unstamped = presented.clone();
    let projection = unstamped
        .iter_mut()
        .find(|p| p.output == output.output)
        .unwrap();
    assert!(projection.frame_completed && projection.policy_visible);
    projection.policy_publication = None;
    service(&mut run, &unstamped);
    let revoked = PolicyPresentationReceipt {
        outcome: PolicyPresentationOutcome::Revoked,
        ..receipt
    };
    assert_eq!(
        receipts(&run),
        vec![revoked],
        "Session revokes the presented identity"
    );
    {
        let public = run.wm.public.as_ref().unwrap();
        assert!(public.presentation_input.publication().is_none());
        assert!(public.reducer.presentation_publication().is_none());
    }
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);

    // Revoked leaves before the cycle; the first answer must already close
    // the switcher. Withdrawn is not supplied until after this answer.
    let stale = run.wm.stale_responses;
    let (request, answer) = first_answer(&mut run);
    assert!(
        matches!(request.cause, PolicyRequestCause::SceneChanged),
        "{:?}",
        request.cause
    );
    assert!(receipts(&run).is_empty(), "Revoked left before the cycle");
    log(
        &run,
        &format!(
            "phase=first-answer request={request:?} proposal={} stale_responses_delta={}",
            matches!(answer, Answer::Proposal(_)),
            run.wm.stale_responses - stale
        ),
    );
    let Answer::Proposal(proposal) = answer else {
        panic!(
            "revoked switcher: the first SceneChanged answer was refused, not a closed switcher"
        );
    };
    assert!(
        staged_publication(&run).is_none(),
        "revoked switcher: the first SceneChanged answer still draws the switcher"
    );
    assert_eq!(
        proposal.focus,
        Some(w1),
        "revoked switcher: the first SceneChanged answer changed focus"
    );
    let previous = commit_installed(&mut run, &mut content, *proposal);
    settle(&mut run, previous);
    assert_eq!(focus(&run), Some(w1));
    assert!(receipts(&run).is_empty());

    // Only now the replacement frame: the revoked identity is Withdrawn.
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
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);
    assert_eq!(run.wm.chord_ledger.len(), 1);

    // Alt's release ends the chord: credit returns, focus does not change.
    let (report, ingress) = routing.route(&mut run, &replaced, &[(ALT, false)], 1400);
    assert!(
        matches!(
            report.policy_inputs[..],
            [PhysicalPolicyInput::Chord(
                sophia_engine::WmChordEvent::Ended {
                    end: PolicyChordEnd::Released,
                    ..
                }
            )]
        ),
        "{:?}",
        report.policy_inputs
    );
    assert_eq!(ingress, 0);
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::ActionLifecycle {
            phase: PolicyChordPhase::Ended(PolicyChordEnd::Released),
            ..
        }
    ));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    assert_eq!(
        proposal.focus,
        Some(w1),
        "Ended after revocation must not commit a selection"
    );
    assert!(staged_publication(&run).is_none());
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    drain(&mut run);
    assert_eq!(focus(&run), Some(w1));
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[0])
    );
    assert!(!owes(&run, RIGHT));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    log(
        &run,
        &format!("phase=committed focus={w1:?} presented={receipt:?}"),
    );
    run.record("revocation-committed");
    run.stop();
}
