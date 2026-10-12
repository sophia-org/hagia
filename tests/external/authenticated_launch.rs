//! Mounted under Sophia's desktop_launch_reload tests by an isolated overlay.
//! Real Hagia, protected launch and Factotum conversation; supplied empty scene
//! and layout completion. No devices or live desktop are involved.
use super::*;
use sha2::{Digest, Sha256};

#[test]
fn hagia_authenticates_startup_and_fresh_restart() {
    let binary = PathBuf::from(std::env::var_os("HAGIA_AUTH_BINARY").unwrap());
    let digest = std::env::var("HAGIA_AUTH_SHA256").unwrap();
    assert_eq!(
        format!("{:x}", Sha256::digest(std::fs::read(&binary).unwrap())),
        digest
    );
    let mut source = ConfigFixture::new(&[]);
    source.config.wm_process = Some(binary.to_str().unwrap().to_owned());
    source.config.wm_process_args.clear();
    source.config.wm_socket_path = source.directory.join("wm.sock");
    source.config.factotum = Some(SessionFactotum {
        agent: "/unused/fixture-agent".into(),
        pam_helper: "/unused/fixture-helper".into(),
        pam_service: "fixture".into(),
        user: "fixture".into(),
    });
    let mut auth = crate::live_session::tests::lock_provider_factotum::Fixture::new();
    let wake = OwnerWake::new().unwrap();
    let prepared = LiveWmSession::prepare_public_launch(&mut source.config).unwrap();
    let started = LiveWmSession::activate_public_launch_authenticated(
        &mut source.config,
        prepared,
        WmStartupContext {
            launches: &mut auth.coordinator,
            namespace: sophia_protocol::NamespaceId::from_raw(2),
            wake: &wake,
            registration: None,
        },
    )
    .expect("Hagia must authenticate before profile admission");
    let output = sophia_engine::HeadlessOutput::deterministic();
    let mut wm = LiveWmSession::from_config(&source.config, &[output], started, None)
        .unwrap()
        .unwrap();
    let mut layout = PersistentLiveLayout::default();
    let first = wm.authentication.as_ref().unwrap().registration.unwrap();
    for epoch in 1..=2 {
        let deadline = Instant::now() + Duration::from_secs(10);
        if epoch == 2 {
            wm.supervisor.request_termination().unwrap();
        }
        let committed_before = wm.committed;
        loop {
            assert!(
                Instant::now() < deadline,
                "Hagia authenticated restart and cycle deadline"
            );
            auth.tick();
            wm.poll_public_restart(&mut layout, output).unwrap();
            wm.poll_wm_authentication(&mut auth.coordinator, wake.notifier(), &mut layout, output)
                .unwrap();
            assert!(!wm.degraded, "authenticated Hagia must remain healthy");
            if wm.public.as_ref().unwrap().connection_epoch != epoch {
                continue;
            }
            if let Some(proposal) = wm.poll_public_request(&mut layout, output, true).unwrap() {
                assert_eq!(proposal.policy_settlement.unwrap().connection_epoch, epoch);
                assert!(proposal.layers.is_empty());
                let result = layout.commit_proposal(proposal);
                assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
                wm.apply_commit_result(result, None, output.id).unwrap();
            }
            wm.settle_desktop_reload(&mut source.config, true).unwrap();
            let public = wm.public.as_ref().unwrap();
            if wm.committed > committed_before
                && public.transport_ready
                && public.in_flight_request.is_none()
                && !wm.desktop_reload_pending()
            {
                assert!(public.configured && public.negotiated);
                assert!(!wm.force_transport_restart && !public.transport_unavailable);
                break;
            }
        }
        let registration = wm.authentication.as_ref().unwrap().registration.unwrap();
        if epoch == 2 {
            assert_ne!(
                registration, first,
                "restarted Hagia must use fresh launch custody"
            );
        }
        assert_eq!(wm.public.as_ref().unwrap().connection_epoch, epoch);
        eprintln!(
            "hagia_authenticated epoch={epoch} committed={} registration={registration:?}",
            wm.committed
        );
    }
    assert_eq!(wm.restarts, 1);
    assert!(
        wm.supervisor.poll().unwrap().is_none(),
        "Hagia alive after authenticated recovery"
    );
    assert_eq!(
        format!("{:x}", Sha256::digest(std::fs::read(&binary).unwrap())),
        digest
    );
    wm.public.as_mut().unwrap().worker.take();
    wm.supervisor.request_termination().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while wm.supervisor.peer_id().is_some() {
        wm.supervisor.poll().unwrap();
        assert!(Instant::now() < deadline, "Hagia teardown deadline");
        std::thread::sleep(Duration::from_millis(2));
    }
}
