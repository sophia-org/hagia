//! Presented and Withdrawn receipts from frames the production backend
//! composed and retired on every mirror head of one output. The backend's
//! test-support target supplies only the worker/device submit and page-flip
//! edges; no input projection, stamp or receipt is supplied here. The CPU
//! sources remain supplied, and `service` mirrors the frame-service order of
//! `service_presented_policy` without its native-target selection tail. One
//! output with two mirror heads; no physical display.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;

/// The production install owner against the target's actual heads. `true`
/// declares the fixture's simulated retirement, never a detected device.
fn install_on(
    run: &mut Lifecycle,
    content: &mut Content,
    target: &SessionPolicyPresentationFixture,
) {
    run.wm
        .install_committed_policy_presentation(
            &mut content.runtime,
            &content.scene,
            true,
            false,
            None,
            &target.heads(),
        )
        .unwrap();
}

/// One head retires its submitted frame; Session then services the input
/// projections the runtime derived from the retired frame lists, which are
/// returned for diagnosis after the behavioral checks.
fn retire(
    run: &mut Lifecycle,
    content: &mut Content,
    target: &mut SessionPolicyPresentationFixture,
    head: usize,
) -> Vec<LivePresentedInputProjection> {
    let output = run.output.id;
    target.simulate_head_completion(&mut content.runtime, output, head);
    let projections = content.runtime.input_projections().to_vec();
    service(run, &projections);
    projections
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_presented_receipts_require_all_heads() {
    let Held {
        mut run,
        mut content,
        mut routing,
        first,
        next,
        candidates,
        expected,
        ..
    } = held("presented-consensus");
    let w1 = expected[0];
    let output = first.outputs[0];

    log(
        &run,
        "presentation_completion=simulated_per_head receipts=backend_derived heads=target_mirrored",
    );
    // The inherited prefix installed and preflighted this publication against
    // one supplied head and completed nothing. It is validated here, read-only,
    // against the target's actual heads. The repeated install below skips the
    // runtime's set branch (the publication is unchanged) and issues no
    // receipt; queueing and retirement below use the target's heads.
    let mut target = SessionPolicyPresentationFixture::new(&[run.output]);
    let heads = target.heads();
    assert_eq!(heads.len(), 2, "one output with two mirror heads");
    assert!(
        content
            .runtime
            .validate_policy_presentation_on_heads(
                &LivePolicyPresentation {
                    owner_epoch: 1,
                    presentation: first.clone(),
                },
                &heads,
            )
            .is_ok()
    );
    install_on(&mut run, &mut content, &target);
    assert!(receipts(&run).is_empty());
    assert_eq!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .presentation_input
            .publication(),
        Some((1, &first))
    );

    // Production composition of the retained switcher, submitted to both.
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    let one = retire(&mut run, &mut content, &mut target, 0);
    assert!(
        receipts(&run).is_empty()
            && run
                .wm
                .public
                .as_ref()
                .unwrap()
                .presentation_input
                .output_receipt(output.output)
                .is_none(),
        "a publication retired by one mirror head must not be Presented"
    );
    // Diagnostic only, after the receipt behavior: no output-wide stamp yet.
    assert!(!one[0].frame_completed && one[0].policy_publication.is_none());
    retire(&mut run, &mut content, &mut target, 1);
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(output.output)
        .expect("every mirror head retired the publication");
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
    // Republishing the same retired frames is not another presentation.
    target.publish(&mut content.runtime);
    let projections = content.runtime.input_projections().to_vec();
    service(&mut run, &projections);
    assert_eq!(
        receipts(&run),
        vec![receipt],
        "one Presented per completion"
    );
    drain(&mut run);

    // Close through the exact chord: Session cancels it at matching loss.
    let (&token, &record) = run.wm.chord_ledger.iter().next().unwrap();
    assert_eq!(record.action, next);
    run.wm.observe_keyboard_matching(true);
    run.wm.observe_keyboard_matching(false);
    let mut report = PhysicalInputRouteReport::default();
    report.policy_inputs.extend(
        run.wm
            .service_shortcuts(1300)
            .into_iter()
            .map(PhysicalPolicyInput::from_shortcut),
    );
    assert!(matches!(
        report.policy_inputs[..],
        [PhysicalPolicyInput::Chord(sophia_engine::WmChordEvent::Ended {
            token: actual,
            end: PolicyChordEnd::Cancelled,
        })] if actual == token
    ));
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::ActionLifecycle {
            activation_serial,
            action,
            count,
            phase: PolicyChordPhase::Ended(PolicyChordEnd::Cancelled),
        } if activation_serial == record.serial && action == record.action && count == record.count
    ));
    assert!(staged_publication(&run).is_none());
    assert_eq!(proposal.focus, Some(w1));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());

    // Commit, then install the closed state at the production boundary.
    let previous = run.checkpoint().1;
    let result = run.layout.commit_proposal(proposal);
    assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
    run.wm
        .apply_commit_result(result, None, run.output.id)
        .unwrap();
    install_on(&mut run, &mut content, &target);
    let revoked = PolicyPresentationReceipt {
        outcome: PolicyPresentationOutcome::Revoked,
        ..receipt
    };
    assert_eq!(
        receipts(&run),
        vec![revoked],
        "Revoked precedes replacement retirement"
    );
    settle(&mut run, previous);
    drain(&mut run);

    // The ordinary replacement must retire on both heads before Withdrawn.
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    let one = retire(&mut run, &mut content, &mut target, 0);
    assert!(
        receipts(&run).is_empty(),
        "a replacement retired by one mirror head must not withdraw the publication"
    );
    // Diagnostic only: the mirror still shows the stamped frame.
    assert!(!one[0].frame_completed && one[0].policy_visible);
    retire(&mut run, &mut content, &mut target, 1);
    let withdrawn = PolicyPresentationReceipt {
        outcome: PolicyPresentationOutcome::Withdrawn,
        ..receipt
    };
    assert_eq!(receipts(&run), vec![withdrawn]);
    target.publish(&mut content.runtime);
    let projections = content.runtime.input_projections().to_vec();
    service(&mut run, &projections);
    assert_eq!(
        receipts(&run),
        vec![withdrawn],
        "one Withdrawn per replacement"
    );
    drain(&mut run);

    assert_eq!(focus(&run), Some(w1));
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[0])
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(!owes(&run, RIGHT));
    log(
        &run,
        &format!("phase=withdrawn heads=2 presented={receipt:?} focus={w1:?}"),
    );
    run.record("consensus-withdrawn");
    run.stop();
}
