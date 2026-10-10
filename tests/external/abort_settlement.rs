//! Lost peer with a real pending layout settlement. Surface facts and the
//! long initial deadline are supplied; frontend controls are queued locally,
//! never sent to an application. Native pixels and rollback ACKs are absent.
use super::*;

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_disconnect_aborts_pending_settlement() {
    let mut run = Lifecycle::new("abort-settlement");
    populate(&mut run);
    let saved = run.checkpoint();
    let committed = run.wm.public.as_ref().unwrap().reducer.committed();
    let layers = run.layout.layers.clone();
    let states = run.layout.committed_policy_presentations.clone();
    let before = focus(&run);
    let mut proposal = action(&mut run, "toggle-fullscreen");
    let identity = proposal.policy_settlement.unwrap();
    let desired = proposal.presentation_states.clone();
    assert!(desired.values().any(|state| state.fullscreen));
    assert_ne!(
        desired, states,
        "fullscreen must require a frontend state change"
    );
    // Distinguish forced abort from expiry of the ordinary short deadline.
    proposal.timeout = Duration::from_secs(30);
    let mut controls = crate::session_control::SessionControlQueue::default();
    assert!(
        run.layout.stage(proposal, &mut controls).unwrap().is_none(),
        "fullscreen must enter the production pending owner"
    );
    let pending = run.layout.pending.as_ref().unwrap();
    assert_eq!(pending.policy_settlement, Some(identity));
    assert!(
        !pending.presentation_settlements.is_empty(),
        "frontend state ACK must be owed"
    );
    let original_deadline = pending.deadline;
    assert!(run.layout.resolve_pending().is_none());
    assert!(run.layout.expire_pending(&mut controls).unwrap().is_none());
    assert_eq!(run.checkpoint(), saved);
    let restarts = run.wm.restarts;
    let peer = run.wm.supervisor.peer_id();
    run.wm.supervisor.request_termination().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        assert!(
            run.wm
                .poll_public_restart(&mut run.layout, run.output)
                .unwrap()
                .is_none()
        );
        let public = run.wm.public.as_ref().unwrap();
        assert_eq!(
            public.connection_epoch, identity.connection_epoch,
            "replacement must wait for pending settlement"
        );
        assert_eq!(run.wm.restarts, restarts);
        assert!(!run.wm.degraded);
        if public.transport_unavailable {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "AbortSettlement detection deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
    let public = run.wm.public.as_ref().unwrap();
    assert!(public.worker.is_none() && public.deferred_command.is_none());
    assert!(run.wm.force_transport_restart);
    assert!(public.staged.is_some());
    assert_eq!(
        public.in_flight_request.as_ref().unwrap().request_id,
        identity.request_id
    );
    let pending = run.layout.pending.as_ref().unwrap();
    assert_eq!(pending.policy_settlement, Some(identity));
    assert!(
        Instant::now() < original_deadline,
        "natural expiry must not mask forced abort"
    );
    assert!(
        pending.deadline < original_deadline && pending.deadline <= Instant::now(),
        "AbortSettlement must force the pending deadline"
    );
    assert_eq!(run.layout.layers, layers);
    assert_eq!(run.layout.committed_policy_presentations, states);
    assert_eq!(public.reducer.committed(), committed);
    assert_eq!(run.checkpoint(), saved);

    // A second restart poll cannot admit a successor while settlement remains.
    assert!(
        run.wm
            .poll_public_restart(&mut run.layout, run.output)
            .unwrap()
            .is_none()
    );
    assert_eq!(
        run.wm.public.as_ref().unwrap().connection_epoch,
        identity.connection_epoch
    );
    assert_eq!(run.wm.restarts, restarts);
    let result = run
        .layout
        .expire_pending(&mut controls)
        .unwrap()
        .expect("forced pending settlement must expire immediately");
    assert_eq!(result.policy_settlement, Some(identity));
    assert_eq!(result.update.commit.transaction, identity.transaction);
    assert_eq!(result.update.commit.outcome, TransactionOutcome::TimedOut);
    assert!(result.update.commit.applied_surfaces.is_empty());
    assert!(run.layout.pending.is_none());
    run.wm
        .apply_commit_result(result, before, run.output.id)
        .unwrap();
    assert_eq!(
        run.wm.public.as_ref().unwrap().connection_epoch,
        identity.connection_epoch
    );
    assert_eq!(
        run.wm.public.as_ref().unwrap().reducer.committed(),
        committed
    );
    assert_eq!(run.layout.layers, layers);
    assert_eq!(run.layout.committed_policy_presentations, states);
    assert_eq!(
        run.checkpoint(),
        saved,
        "abort cannot promote fullscreen in the peer"
    );
    assert!(run.layout.expire_pending(&mut controls).unwrap().is_none());

    assert!(
        run.wm
            .poll_public_restart(&mut run.layout, run.output)
            .unwrap()
            .is_none()
    );
    assert_eq!(
        run.wm.public.as_ref().unwrap().connection_epoch,
        identity.connection_epoch + 1
    );
    assert_eq!(run.wm.restarts, restarts + 1);
    assert_ne!(run.wm.supervisor.peer_id(), peer);
    run.ready(true);
    assert_eq!(run.checkpoint(), saved);
    for _ in 0..2 {
        let proposal = run.proposal();
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
        run.commit(proposal);
        assert_eq!(
            run.wm.public.as_ref().unwrap().reducer.committed(),
            committed,
            "replacement must restore the pre-fullscreen policy"
        );
    }
    assert_checkpoint(&run);
    let proposal = action(&mut run, "toggle-fullscreen");
    assert_eq!(
        proposal.presentation_states, desired,
        "fresh fullscreen must still toggle from the uncommitted baseline"
    );
    run.commit(proposal); // Supplied completion, not a frontend ACK.
    assert_eq!(run.layout.committed_policy_presentations, desired);
    assert_checkpoint(&run);
    run.record("abort-settlement-recovered");
    run.stop();
}
