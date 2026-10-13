//! Ordinary SDK peer with supplied mapped surface facts and layout completion.
//! No application, pixels, configure ACK, renderer or physical focus is exercised.
use super::*;
use sophia_protocol::*;

#[path = "abort_settlement.rs"]
mod abort_settlement;

#[path = "manage.rs"]
mod manage;

#[path = "manage_pixels.rs"]
mod manage_pixels;

#[path = "reused_identity.rs"]
mod reused_identity;

#[path = "pointer.rs"]
mod pointer;

#[path = "pointer_focus_sdk.rs"]
mod pointer_focus;

#[path = "policy_projection.rs"]
mod policy_projection;

#[path = "launch_outputs.rs"]
mod launch_outputs;

const SURFACES: [SurfaceId; 2] = [SurfaceId::new(31, 2), SurfaceId::new(47, 5)];

pub(super) fn populate(run: &mut Lifecycle) {
    populate_with_placements(run, 2);
}

fn populate_with_placements(run: &mut Lifecycle, placements: usize) {
    let client = sophia_x_authority::XServerFrontendClientId::from_raw(1);
    let mut batch = crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(700));
    batch.client = Some(client);
    for (i, surface) in SURFACES.into_iter().enumerate() {
        let geometry = Rect {
            x: 30 + i as i32 * 200,
            y: 30,
            width: 160,
            height: 120,
        };
        batch
            .surface_routes
            .push(sophia_x_authority::XAuthoritySurfaceRouteObservation {
                surface,
                client,
                admission: None,
            });
        batch.surface_presentations.push(
            sophia_x_authority::XAuthoritySurfacePresentationObservation {
                surface,
                role: SurfacePresentationRole::PolicyManaged,
                kind: LayoutNodeKind::Toplevel,
                placement_preference: SurfacePlacementPreference::Default,
                owner: None,
                stack_rank: i as u32,
                mapped: true,
                geometry,
                constraints: SurfaceConstraints {
                    min_size: None,
                    max_size: None,
                },
                generation: 8 + i as u64,
            },
        );
        run.layout.layers.insert(
            surface,
            LayerSnapshot {
                input_region: None,
                translation: None,
                output: None,
                surface,
                authority_local_id: None,
                namespace: None,
                stack_rank: i as u32,
                geometry,
                source_size: Size {
                    width: 160,
                    height: 120,
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
    }
    assert!(
        !run.layout
            .observe_authority_batch(&batch)
            .client_route_invalid
    );
    run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
    let proposal = run.proposal();
    assert_eq!(
        proposal.layers.len(),
        placements,
        "the layout must project its expected visible surfaces"
    );
    run.commit(proposal); // Supplied completion, not a visual-readiness proof.
    // Reconcile the committed focus into the next complete snapshot.
    run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
    let proposal = run.proposal();
    run.commit(proposal);
    assert!(focus(run).is_some());
    assert_checkpoint(run);
    run.record("occupied-baseline");
}

pub(super) fn focus(run: &Lifecycle) -> Option<SurfaceId> {
    run.wm.public.as_ref().unwrap().reducer.committed()[0].focus
}

fn model(run: &Lifecycle) -> serde_json::Value {
    let bytes = run.checkpoint().0;
    serde_json::from_str(
        std::str::from_utf8(&bytes)
            .unwrap()
            .strip_prefix("HAGIA-POLICY-CHECKPOINT-19\n")
            .unwrap(),
    )
    .unwrap()
}

pub(super) fn assert_checkpoint(run: &Lifecycle) {
    let model = model(run);
    let surfaces = model["surfaces"].as_array().unwrap();
    assert_eq!(surfaces.len(), 2);
    assert_eq!(model["windows"].as_array().unwrap().len(), 2);
    let focused = model["outputs"][0]["focusedWindow"].as_u64().unwrap();
    let mapped = surfaces
        .iter()
        .find(|s| s["window"].as_u64() == Some(focused))
        .unwrap();
    let surface = focus(run).unwrap();
    assert_eq!(
        mapped["key"].as_u64(),
        Some((u64::from(surface.generation()) << 32) | u64::from(surface.index())),
        "client checkpoint focus agrees with Session's committed focus"
    );
}

fn action(run: &mut Lifecycle, name: &str) -> LiveWmProposal {
    let action = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .actions
        .iter()
        .find(|a| a.name == name)
        .unwrap()
        .action;
    assert!(matches!(
        run.wm
            .enqueue_action(action, &run.layout, run.output)
            .unwrap(),
        LiveOrderedWmActionAdmission::Admitted { .. }
    ));
    run.proposal()
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_occupied_settlement() {
    let mut run = Lifecycle::new("occupied-settlement");
    populate(&mut run);
    let before = focus(&run);
    let proposal = action(&mut run, "focus-next");
    assert_ne!(proposal.focus, before, "real catalog action changes focus");
    assert_eq!(focus(&run), before, "proposal cannot publish focus");
    run.commit(proposal);
    assert_checkpoint(&run);
    run.record("action-committed");

    for stale in [false, true] {
        let saved = run.checkpoint();
        let committed = run.wm.public.as_ref().unwrap().reducer.committed();
        let layers = run.layout.layers.clone();
        let proposal = action(&mut run, "focus-next");
        let identity = proposal.policy_settlement.unwrap();
        let refused_focus = proposal.focus;
        assert_ne!(proposal.focus, focus(&run));
        assert_eq!(run.checkpoint(), saved, "staging cannot save a candidate");
        if stale {
            let public = run.wm.public.as_mut().unwrap();
            let mut scene = public.reducer.scene().clone();
            scene.generation += 1;
            public.reducer.observe_scene(scene).unwrap();
            assert_eq!(
                public
                    .reducer
                    .revalidate_staged(public.staged.as_ref().unwrap()),
                PolicyProjectionOutcome::RejectedStale
            );
        }
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
        run.wm
            .apply_commit_result(result, focus(&run), run.output.id)
            .unwrap();
        run.ready(false);
        assert_eq!(
            run.layout.layers, layers,
            "refusal keeps committed placements"
        );
        assert_eq!(
            run.wm.public.as_ref().unwrap().reducer.committed(),
            committed
        );
        assert_eq!(
            run.checkpoint(),
            saved,
            "refusal cannot promote client candidate"
        );
        run.record(if stale {
            "stale-refused"
        } else {
            "timeout-refused"
        });
        // Refusal owes a SceneChanged cycle, never a replay of the action.
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
            focus(&run),
            "recovery does not replay refused focus action"
        );
        assert_eq!(
            run.checkpoint(),
            saved,
            "recovery response confirms refusal without a save"
        );
        let recovery_id = recovery.policy_settlement.unwrap();
        assert!(recovery_id.request_id > identity.request_id);
        run.commit(recovery);
        let next = action(&mut run, "focus-next");
        assert_eq!(
            next.focus, refused_focus,
            "refused focus was not promoted in Hagia"
        );
        let next_id = next.policy_settlement.unwrap();
        assert_eq!(next_id.connection_epoch, identity.connection_epoch);
        assert!(next_id.request_id > identity.request_id);
        assert_ne!(next_id.transaction, identity.transaction);
        run.commit(next);
        assert_checkpoint(&run);
    }
    run.stop();
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_occupied_restart() {
    let mut run = Lifecycle::new("occupied-restart");
    populate(&mut run);
    let proposal = action(&mut run, "focus-next");
    run.commit(proposal);
    let columns = model(&run)["columns"].clone();
    let proposal = action(&mut run, "resize-width 0.1");
    run.commit(proposal);
    assert_ne!(
        model(&run)["columns"],
        columns,
        "private column sizing changed"
    );
    // Checkpoint facts describe the snapshot consumed by that cycle, not its
    // just-produced projection. Observe the new geometry before comparing
    // snapshot caches across a restart.
    run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
    let proposal = run.proposal();
    run.commit(proposal);
    assert_checkpoint(&run);
    for epoch in [2, 3] {
        let saved = run.checkpoint();
        let expected = run.wm.public.as_ref().unwrap().reducer.committed();
        let mut retained_layers = run.layout.layers.clone();
        for layer in retained_layers.values_mut() {
            if let Some(translation) = layer.translation.as_mut() {
                // Only this identity is defined relative to the new connection.
                translation.connection_epoch = epoch;
            }
        }
        let peer = run.wm.supervisor.peer_id();
        if epoch == 2 {
            run.wm.supervisor.request_termination().unwrap();
            let deadline = Instant::now() + Duration::from_secs(5);
            while run.wm.public.as_ref().unwrap().connection_epoch < epoch {
                assert!(run.poll_restart().unwrap().is_none());
                assert!(!run.wm.degraded);
                assert!(
                    Instant::now() < deadline,
                    "occupied automatic restart deadline"
                );
                std::thread::sleep(Duration::from_millis(2));
            }
        } else {
            assert_eq!(run.wm.begin_control_restart(run.output).unwrap(), epoch);
        }
        run.ready(true);
        assert_ne!(run.wm.supervisor.peer_id(), peer);
        assert_eq!(run.checkpoint(), saved, "restart startup cannot commit");
        for _ in 0..2 {
            // Owner's queued scene, then client's actual restore Dirty.
            let proposal = run.proposal();
            assert_eq!(proposal.policy_settlement.unwrap().connection_epoch, epoch);
            run.commit(proposal);
            assert_eq!(
                run.wm.public.as_ref().unwrap().reducer.committed(),
                expected,
                "occupied restart restores committed placements and focus"
            );
        }
        assert_checkpoint(&run);
        assert_eq!(
            run.layout.layers, retained_layers,
            "restart keeps the committed layout layers"
        );
        let restored = model(&run);
        let old: serde_json::Value = serde_json::from_str(
            std::str::from_utf8(&saved.0)
                .unwrap()
                .split_once('\n')
                .unwrap()
                .1,
        )
        .unwrap();
        for field in [
            "windows",
            "columns",
            "windowOrder",
            "windowTags",
            "views",
            "outputs",
            "surfaces",
        ] {
            assert_eq!(
                restored[field], old[field],
                "restored occupied checkpoint field {field}"
            );
        }
        run.record(if epoch == 2 {
            "occupied-automatic"
        } else {
            "occupied-requested"
        });
    }
    run.stop();
}
