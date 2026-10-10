//! A surface's numeric index reused with a new generation across an actual
//! supervised WM restart. Surface facts and layout completion are supplied, as
//! in the parent; the removal follows the owner loop's two calls. The claim is
//! Session's exact-identity guard on a focus request and real Hagia accepting
//! fresh authority for the replacement, not every surface-keyed authority.
use super::*;

const REPLACEMENT: SurfaceId = SurfaceId::new(47, 6);

fn key(surface: SurfaceId) -> u64 {
    (u64::from(surface.generation()) << 32) | u64::from(surface.index())
}

fn checkpoint_keys(run: &Lifecycle) -> Vec<u64> {
    let mut keys = model(run)["surfaces"]
        .as_array()
        .unwrap()
        .iter()
        .map(|surface| surface["key"].as_u64().unwrap())
        .collect::<Vec<_>>();
    keys.sort_unstable();
    keys
}

fn focused_key(run: &Lifecycle) -> Option<u64> {
    let model = model(run);
    let focused = model["outputs"][0]["focusedWindow"].as_u64()?;
    model["surfaces"]
        .as_array()
        .unwrap()
        .iter()
        .find(|surface| surface["window"].as_u64() == Some(focused))
        .and_then(|surface| surface["key"].as_u64())
}

/// One focus request through the production owner, answered and committed.
fn focus_on(run: &mut Lifecycle, surface: SurfaceId) {
    assert!(matches!(
        run.wm
            .enqueue_focus(surface, &run.layout, run.output)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    ));
    let proposal = run.proposal();
    assert!(matches!(
        run.wm.public.as_ref().unwrap().in_flight_request.as_ref().unwrap().cause,
        PolicyRequestCause::Focus { target } if target == surface
    ));
    assert_eq!(proposal.focus, Some(surface));
    run.commit(proposal);
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_occupied_reused_surface_generation_after_restart() {
    let [first, old] = SURFACES;
    assert_eq!(old.index(), REPLACEMENT.index());
    assert_ne!(old.generation(), REPLACEMENT.generation());
    let mut run = Lifecycle::new("reused-identity");
    populate(&mut run);
    assert_eq!(checkpoint_keys(&run), {
        let mut keys = vec![key(first), key(old)];
        keys.sort_unstable();
        keys
    });

    // An actual supervised restart: only this fixture's peer is terminated.
    let peer = run.wm.supervisor.peer_id();
    run.wm.supervisor.request_termination().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while run.wm.public.as_ref().unwrap().connection_epoch < 2 {
        assert!(
            run.wm
                .poll_public_restart(&mut run.layout, run.output)
                .unwrap()
                .is_none()
        );
        assert!(!run.wm.degraded);
        assert!(
            Instant::now() < deadline,
            "reused-identity automatic restart deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
    run.ready(true);
    let epoch = run.wm.public.as_ref().unwrap().connection_epoch;
    assert_eq!(epoch, 2);
    assert_ne!(run.wm.supervisor.peer_id(), peer);

    // Before recovery, the old surface leaves and its numeric index returns
    // with a new generation. The removal makes the owner loop's two calls.
    let client = sophia_x_authority::XServerFrontendClientId::from_raw(1);
    let mut removal =
        crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(730));
    removal.client = Some(client);
    removal.removed_surfaces.push(old);
    assert!(
        !run.layout
            .observe_authority_batch(&removal)
            .client_route_invalid
    );
    assert!(!matches!(
        run.wm.enqueue_surface_removed(old).unwrap(),
        LiveWmRequestAdmission::RejectedCapacity
    ));
    let geometry = run.layout.layers[&first].geometry;
    let geometry = Rect {
        x: geometry.x + 200,
        ..geometry
    };
    let mut arrival =
        crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(731));
    arrival.client = Some(client);
    arrival
        .surface_routes
        .push(sophia_x_authority::XAuthoritySurfaceRouteObservation {
            surface: REPLACEMENT,
            client,
            admission: None,
        });
    arrival.surface_presentations.push(
        sophia_x_authority::XAuthoritySurfacePresentationObservation {
            surface: REPLACEMENT,
            role: SurfacePresentationRole::PolicyManaged,
            kind: LayoutNodeKind::Toplevel,
            placement_preference: SurfacePlacementPreference::Default,
            owner: None,
            stack_rank: 1,
            mapped: true,
            geometry,
            constraints: SurfaceConstraints {
                min_size: None,
                max_size: None,
            },
            generation: 20,
        },
    );
    run.layout.layers.insert(
        REPLACEMENT,
        LayerSnapshot {
            input_region: None,
            translation: None,
            output: None,
            surface: REPLACEMENT,
            authority_local_id: None,
            namespace: None,
            stack_rank: 1,
            geometry,
            source_size: Size {
                width: geometry.width,
                height: geometry.height,
            },
            source: BufferSource::None,
            damage: Region::empty(),
            opacity: 1.0,
            crop: None,
            transform: Transform::IDENTITY,
            generation: 1,
            resize_sync: ResizeSyncCapability::ImplicitOnly,
        },
    );
    assert!(
        !run.layout
            .observe_authority_batch(&arrival)
            .client_route_invalid
    );
    assert!(run.layout.layers.contains_key(&REPLACEMENT));
    assert!(!run.layout.layers.contains_key(&old));

    // Real Hagia recovery: the queued scene, then its restore Dirty.
    for _ in 0..2 {
        let proposal = run.proposal();
        assert_eq!(proposal.policy_settlement.unwrap().connection_epoch, epoch);
        run.commit(proposal);
    }
    assert_eq!(checkpoint_keys(&run), {
        let mut keys = vec![key(first), key(REPLACEMENT)];
        keys.sort_unstable();
        keys
    });

    // Focus the surviving surface only if recovery did not already, so the
    // fresh request below must change focus and no commit is a no-op.
    if focus(&run) != Some(first) {
        focus_on(&mut run, first);
    }
    assert_eq!(focus(&run), Some(first));

    // The old identity names a numeric index the replacement now holds.
    let (queued, requests) = {
        let public = run.wm.public.as_ref().unwrap();
        // With nothing queued or in flight, Duplicate can only be the
        // exact-identity refusal; no Focus source for the old id exists.
        assert!(
            public.queue.is_empty() && public.in_flight_request.is_none(),
            "recovery and focus left no queued or in-flight cause"
        );
        (public.queue.len(), run.wm.requests)
    };
    let refused = run.wm.enqueue_focus(old, &run.layout, run.output).unwrap();
    {
        let public = run.wm.public.as_ref().unwrap();
        assert!(
            matches!(refused, LiveWmRequestAdmission::Duplicate)
                && public.queue.len() == queued
                && run.wm.requests == requests
                && public.in_flight_request.is_none(),
            "old surface identity must not target its numeric replacement"
        );
    }

    // Fresh authority for the replacement is correlated and committed.
    assert!(matches!(
        run.wm
            .enqueue_focus(REPLACEMENT, &run.layout, run.output)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    ));
    let proposal = run.proposal();
    assert!(
        matches!(
            run.wm.public.as_ref().unwrap().in_flight_request.as_ref().unwrap().cause,
            PolicyRequestCause::Focus { target } if target == REPLACEMENT
        ) && proposal.focus == Some(REPLACEMENT),
        "the replacement accepts fresh focus authority"
    );
    run.commit(proposal);
    assert_eq!(focus(&run), Some(REPLACEMENT));
    assert_eq!(focused_key(&run), Some(key(REPLACEMENT)));

    // Poll without admitting work before endpoint teardown: transport and
    // supervisor health only, not another round trip.
    let requests = run.wm.requests;
    assert!(
        run.wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap()
            .is_none()
    );
    {
        let public = run.wm.public.as_ref().unwrap();
        assert!(
            !run.wm.degraded
                && !run.wm.force_transport_restart
                && !public.transport_unavailable
                && public.connection_epoch == epoch,
            "peer healthy before reused-identity teardown"
        );
        assert!(
            run.wm.requests == requests
                && public.in_flight_request.is_none()
                && public.queue.is_empty(),
            "a non-admitting poll cannot start a cycle before teardown"
        );
    }
    assert!(
        run.wm.supervisor.poll().unwrap().is_none(),
        "peer alive before reused-identity teardown"
    );
    run.record("reused-identity-focused");
    run.stop();
}
