//! Real SDK operations stop at Session's typed intent. No executor is called.
//! Disconnects terminate only this fixture's protected child.
use super::*;
use sophia_protocol::*;

fn action(run: &mut Lifecycle) -> (LiveWmProposal, u64) {
    let public = run.wm.public.as_ref().unwrap();
    let operation = public
        .session_operations
        .iter()
        .find(|o| o.slot == 1)
        .unwrap();
    assert!(!operation.permits_surface_target);
    assert_eq!(
        public.operation_actions[&operation.token],
        WmSessionAction::LaunchApplication {
            application: SessionApplicationId::from_raw(1),
        }
    );
    let action = public
        .actions
        .iter()
        .find(|a| a.session_operation_slot == Some(1))
        .unwrap()
        .action;
    assert!(matches!(
        run.wm
            .enqueue_action(action, &run.layout, run.output)
            .unwrap(),
        LiveOrderedWmActionAdmission::Admitted { .. }
    ));
    let proposal = run.proposal();
    assert_eq!(proposal.source, Some(LiveWmProposalSource::Action(action)));
    let identity = proposal.policy_settlement.unwrap();
    assert!(identity.expect_session_operation && !identity.session_operation);
    let public = run.wm.public.as_ref().unwrap();
    let serial = match public.in_flight_request.as_ref().unwrap().cause {
        PolicyRequestCause::Action {
            activation_serial,
            action: actual,
        } => {
            assert_eq!(actual, action);
            activation_serial
        }
        ref cause => panic!("expected action, got {cause:?}"),
    };
    assert!(serial > 0);
    assert_ne!(
        serial, identity.request_id,
        "fixture distinguishes identity namespaces"
    );
    assert_eq!(public.expected_operation_slot, Some(1));
    assert!(public.pending_operation.is_none());
    (proposal, serial)
}

fn refuse(run: &mut Lifecycle, proposal: LiveWmProposal) {
    let result = LiveWmCommitResult {
        update: WmTransactionUpdate {
            commit: TransactionCommit {
                transaction: proposal.transaction,
                outcome: TransactionOutcome::TimedOut,
                applied_surfaces: vec![],
            },
        },
        source: proposal.source,
        policy_settlement: proposal.policy_settlement,
    };
    let result = run
        .wm
        .apply_commit_result(result, occupied::focus(run), run.output.id)
        .unwrap();
    assert!(
        result.session_action.is_none(),
        "refusal must not return an executable intent"
    );
}

fn operation(run: &mut Lifecycle) -> LiveWmProposal {
    let (proposal, serial) = action(run);
    let identity = proposal.policy_settlement.unwrap();
    let checkpoint = run.checkpoint();
    let result = run.layout.commit_proposal(proposal);
    let result = run
        .wm
        .apply_commit_result(result, occupied::focus(run), run.output.id)
        .unwrap();
    assert!(
        result.session_action.is_none(),
        "projection is not operation acceptance"
    );
    let deadline = Instant::now() + Duration::from_secs(5);
    let proposal = loop {
        if let Some(proposal) = run
            .wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap()
        {
            break proposal;
        }
        assert!(!run.wm.degraded && !run.wm.force_transport_restart);
        assert!(Instant::now() < deadline, "actual SDK operation deadline");
        std::thread::sleep(Duration::from_millis(2));
    };
    let operation = proposal.policy_settlement.unwrap();
    assert!(operation.session_operation && !operation.expect_session_operation);
    assert_eq!(operation.connection_epoch, identity.connection_epoch);
    assert_eq!(
        operation.request_id, serial,
        "operation names activation, not projection request"
    );
    assert_ne!(operation.transaction, identity.transaction);
    let public = run.wm.public.as_ref().unwrap();
    let (transaction, request) = public.pending_operation.as_ref().unwrap();
    assert_eq!(*transaction, operation.transaction);
    assert_eq!(request.request_id, serial);
    assert_eq!(request.connection_epoch, identity.connection_epoch);
    assert_eq!(request.target, None);
    assert_eq!(
        request.operation,
        public
            .session_operations
            .iter()
            .find(|o| o.slot == 1)
            .unwrap()
            .token
    );
    assert!(public.expected_operation_slot.is_none());
    assert_ne!(
        run.checkpoint().1,
        checkpoint.1,
        "checkpoint precedes operation send"
    );
    std::fs::write(run.evidence.join(format!("operation-{}.txt", operation.transaction.raw())),
        format!("projection={identity:?}\nactivation_serial={serial}\noperation={operation:?}\nrequest={request:?}\nexecutor_called=false\n")).unwrap();
    proposal
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_operation_settlement() {
    let mut run = Lifecycle::new("operation-settlement");
    occupied::populate(&mut run);
    let peer = run.wm.supervisor.peer_id();
    for accepted in [true, false] {
        let proposal = operation(&mut run);
        let identity = proposal.policy_settlement.unwrap();
        let saved = run.checkpoint();
        let layers = run.layout.layers.clone();
        let committed = run.wm.public.as_ref().unwrap().reducer.committed();
        if accepted {
            let result = run.layout.commit_proposal(proposal);
            let result = run
                .wm
                .apply_commit_result(result, occupied::focus(&run), run.output.id)
                .unwrap();
            // Keep the typed intent here. Neither queue nor executor receives it.
            assert_eq!(
                result.session_action,
                Some((
                    identity.transaction,
                    WmSessionAction::LaunchApplication {
                        application: SessionApplicationId::from_raw(1)
                    },
                    None
                ))
            );
            assert!(result.physical_action.is_none());
        } else {
            refuse(&mut run, proposal);
        }
        assert!(run.wm.public.as_ref().unwrap().pending_operation.is_none());
        assert_eq!(run.layout.layers, layers);
        assert_eq!(
            run.wm.public.as_ref().unwrap().reducer.committed(),
            committed
        );
        run.ready(false);
        run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
        let next = run.proposal();
        assert!(!next.policy_settlement.unwrap().session_operation);
        assert!(next.transaction.raw() > identity.transaction.raw());
        assert_eq!(
            run.checkpoint(),
            saved,
            "operation outcome cannot save policy state"
        );
        assert_eq!(run.wm.supervisor.peer_id(), peer);
        run.commit(next);
        occupied::assert_checkpoint(&run);
        run.record(if accepted {
            "operation-accepted"
        } else {
            "operation-refused"
        });
    }
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_operation_refused_action() {
    let mut run = Lifecycle::new("operation-refused-action");
    occupied::populate(&mut run);
    let saved = run.checkpoint();
    let (proposal, _) = action(&mut run);
    refuse(&mut run, proposal);
    run.ready(false); // An unsolicited operation proposal fails this wait.
    let public = run.wm.public.as_ref().unwrap();
    assert!(public.pending_operation.is_none() && public.expected_operation_slot.is_none());
    let next = run.proposal();
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
    assert!(!next.policy_settlement.unwrap().session_operation);
    assert_eq!(
        run.checkpoint(),
        saved,
        "refused action cannot save or launch"
    );
    run.commit(next);
    // A new explicit action works after the refusal; the old one is not replayed.
    let proposal = operation(&mut run);
    refuse(&mut run, proposal);
    run.ready(false);
    run.record("refused-action-recovered");
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_operation_disconnect() {
    let mut run = Lifecycle::new("operation-disconnect");
    occupied::populate(&mut run);
    for pending_operation in [false, true] {
        let proposal = if pending_operation {
            operation(&mut run)
        } else {
            action(&mut run).0
        };
        let identity = proposal.policy_settlement.unwrap();
        let saved = run.checkpoint();
        let committed = run.wm.public.as_ref().unwrap().reducer.committed();
        let peer = run.wm.supervisor.peer_id();
        assert_eq!(
            run.wm.public.as_ref().unwrap().pending_operation.is_some(),
            pending_operation
        );
        run.wm.supervisor.request_termination().unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while run.wm.public.as_ref().unwrap().connection_epoch == identity.connection_epoch {
            assert!(
                run.wm
                    .poll_public_restart(&mut run.layout, run.output)
                    .unwrap()
                    .is_none()
            );
            assert!(Instant::now() < deadline, "disconnect restart deadline");
            std::thread::sleep(Duration::from_millis(2));
        }
        // The obsolete proposal is not settled into the successor owner.
        drop(proposal);
        run.ready(true);
        let public = run.wm.public.as_ref().unwrap();
        assert!(public.staged.is_none() && public.prepared.is_none());
        assert!(
            public.pending_operation.is_none(),
            "disconnected operation must lose its authority"
        );
        assert!(
            public.expected_operation_slot.is_none(),
            "disconnected action cannot owe an operation"
        );
        assert_eq!(public.connection_epoch, identity.connection_epoch + 1);
        assert_ne!(run.wm.supervisor.peer_id(), peer);
        assert_eq!(
            run.checkpoint(),
            saved,
            "disconnect cannot promote unsettled work"
        );
        for _ in 0..2 {
            let next = run.proposal();
            assert!(!next.policy_settlement.unwrap().session_operation);
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
            run.commit(next);
            assert_eq!(
                run.wm.public.as_ref().unwrap().reducer.committed(),
                committed
            );
        }
        occupied::assert_checkpoint(&run);
        run.record(if pending_operation {
            "disconnected-operation"
        } else {
            "disconnected-projection"
        });
    }
    let proposal = operation(&mut run);
    refuse(&mut run, proposal);
    run.ready(false);
    run.stop();
}
