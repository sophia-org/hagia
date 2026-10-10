//! A newly requested policy-managed surface through Session's admission
//! owners: intent, owner selection, Manage cycle, production staging, the
//! queued AdmitSurface and SetPresentationState controls, and their supplied
//! frontend acknowledgements. No pixels are supplied, so admission stops at
//! AwaitingPixels: neither Managed state nor extent reconciliation is claimed.
use super::*;

const NEW: SurfaceId = SurfaceId::new(59, 1);

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_occupied_manage_settles_admission() {
    let mut run = Lifecycle::new("manage-admission");
    populate(&mut run);
    let before = focus(&run);
    let saved = run.checkpoint();
    use sophia_engine::SurfacePresentationAdmissionState as Admission;

    // The X authority's request for a new top-level, as Session's own
    // admission tests shape it: route, intent and mapped presentation, with
    // no transaction and so no pixels.
    let client = sophia_x_authority::XServerFrontendClientId::from_raw(1);
    let geometry = Rect {
        x: 430,
        y: 30,
        width: 160,
        height: 120,
    };
    let intent = SurfacePresentationIntent {
        surface: NEW,
        kind: SurfacePresentationIntentKind::Request,
        role: SurfacePresentationRole::PolicyManaged,
        surface_kind: LayoutNodeKind::Toplevel,
        placement_preference: SurfacePlacementPreference::Default,
        presentation_owner: None,
        stack_rank: 2,
        geometry,
        constraints: SurfaceConstraints {
            min_size: None,
            max_size: None,
        },
        generation: 1,
    };
    let mut batch = crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(710));
    batch.client = Some(client);
    batch
        .surface_routes
        .push(sophia_x_authority::XAuthoritySurfaceRouteObservation {
            surface: NEW,
            client,
            admission: None,
        });
    batch.presentation_intents.push(intent);
    batch.surface_presentations.push(
        sophia_x_authority::XAuthoritySurfacePresentationObservation {
            surface: NEW,
            role: intent.role,
            kind: intent.surface_kind,
            placement_preference: intent.placement_preference,
            owner: None,
            stack_rank: intent.stack_rank,
            mapped: true,
            geometry,
            constraints: intent.constraints,
            generation: intent.generation,
        },
    );
    assert!(
        !run.layout
            .observe_authority_batch(&batch)
            .client_route_invalid
    );
    assert_eq!(run.layout.admissions.state(NEW), Admission::PolicyPending);
    assert!(run.layout.unmanaged_surfaces.contains(&NEW));
    assert!(!run.layout.layers.contains_key(&NEW), "no pixels, no layer");
    // The owner loop asks only with no pending layout, and only for the
    // surface it selects itself.
    assert!(run.layout.pending.is_none());
    assert_eq!(run.layout.next_unmanaged_surface(), Some(NEW));

    assert!(matches!(
        run.wm.enqueue_manage(NEW, &run.layout, run.output).unwrap(),
        LiveWmRequestAdmission::Admitted
    ));
    assert!(
        matches!(
            run.wm.enqueue_manage(NEW, &run.layout, run.output).unwrap(),
            LiveWmRequestAdmission::Duplicate
        ),
        "a queued manage request must coalesce"
    );
    let proposal = run.proposal();
    assert!(
        matches!(
            run.wm.enqueue_manage(NEW, &run.layout, run.output).unwrap(),
            LiveWmRequestAdmission::Duplicate
        ),
        "an in-flight manage request must coalesce"
    );
    let identity = proposal.policy_settlement.unwrap();
    let placed = proposal
        .layers
        .iter()
        .find(|layer| layer.surface == NEW)
        .expect("Hagia must place the requested surface")
        .geometry;
    assert_eq!(
        proposal.focus,
        Some(NEW),
        "Hagia focuses a newly admitted window"
    );
    let state = proposal.presentation_states[&NEW];

    // Production staging: the admission transition and both controls.
    let mut controls = crate::session_control::SessionControlQueue::default();
    assert!(
        run.layout.stage(proposal, &mut controls).unwrap().is_none(),
        "an owed presentation state keeps the admission pending"
    );
    assert_eq!(
        run.layout.admissions.state(NEW),
        Admission::ControlPending {
            transaction: identity.transaction,
            geometry: placed,
        }
    );
    {
        let pending = run.layout.pending.as_ref().unwrap();
        assert_eq!(pending.policy_settlement, Some(identity));
        assert!(pending.admission_surfaces.contains(&NEW));
        assert!(pending.presentation_settlements.contains(&NEW));
        assert!(pending.layers.iter().any(|layer| layer.surface == NEW));
    }

    // Dispatch through the production queue; other surfaces may also have
    // geometry controls, so only the new surface's commands are compared.
    let (commands, sent) = std::sync::mpsc::sync_channel(64);
    let (acknowledge, acknowledgements) = std::sync::mpsc::sync_channel(64);
    let mut completions = Vec::new();
    controls
        .service(
            &commands,
            &acknowledgements,
            Instant::now(),
            &mut completions,
        )
        .unwrap();
    assert!(completions.is_empty());
    let issued = sent
        .try_iter()
        .filter(|command| command.command.surface() == NEW)
        .collect::<Vec<_>>();
    assert_eq!(
        issued,
        [
            sophia_x_authority::XAuthorityClientControlCommand {
                client,
                command: sophia_x_authority::XAuthorityControlCommand::AdmitSurface {
                    transaction: identity.transaction,
                    surface: NEW,
                    geometry: placed,
                },
            },
            sophia_x_authority::XAuthorityClientControlCommand {
                client,
                command: sophia_x_authority::XAuthorityControlCommand::SetPresentationState {
                    transaction: identity.transaction,
                    surface: NEW,
                    state,
                },
            },
        ]
    );

    // A wrong transaction cannot advance admission.
    let wrong = TransactionId::from_raw(identity.transaction.raw() + 1);
    assert!(!run.layout.acknowledge_admission_control(wrong, NEW));
    assert!(matches!(
        run.layout.admissions.state(NEW),
        Admission::ControlPending { .. }
    ));

    // Supplied frontend answers, correlated by the production queue and
    // applied by the owner loop's AdmitSurface and SetPresentationState arms.
    let delivered = |kind| sophia_x_authority::XAuthorityClientControlAck {
        client,
        acknowledgement: sophia_x_authority::XAuthorityControlAck {
            kind,
            transaction: identity.transaction,
            surface: NEW,
            outcome: sophia_x_authority::XAuthorityControlOutcome::Delivered,
        },
    };
    for kind in [
        sophia_x_authority::XAuthorityControlKind::AdmitSurface,
        sophia_x_authority::XAuthorityControlKind::SetPresentationState,
    ] {
        acknowledge.try_send(delivered(kind)).unwrap();
    }
    controls
        .service(
            &commands,
            &acknowledgements,
            Instant::now(),
            &mut completions,
        )
        .unwrap();
    assert_eq!(completions.len(), 2);
    for completion in &completions {
        assert!(completion.failure.is_none());
        assert_eq!(completion.key.surface, NEW);
        match completion.key.kind {
            sophia_x_authority::XAuthorityControlKind::AdmitSurface => {
                assert!(run.layout.acknowledge_admission_control(
                    completion.key.transaction,
                    completion.key.surface
                ));
            }
            sophia_x_authority::XAuthorityControlKind::SetPresentationState => {
                assert!(run.layout.acknowledge_presentation_control(
                    completion.key.transaction,
                    completion.key.surface
                ));
            }
            other => panic!("unexpected completion {other:?}"),
        }
    }
    let awaiting = Admission::AwaitingPixels {
        transaction: identity.transaction,
        geometry: placed,
    };
    assert_eq!(run.layout.admissions.state(NEW), awaiting);
    // Neither the admission owner nor the queue accepts a repeated answer.
    // The queue's refusal is a control observation of correlation, not a
    // transport failure.
    assert!(
        !run.layout
            .acknowledge_admission_control(identity.transaction, NEW)
    );
    acknowledge
        .try_send(delivered(
            sophia_x_authority::XAuthorityControlKind::AdmitSurface,
        ))
        .unwrap();
    assert_eq!(
        controls.service(
            &commands,
            &acknowledgements,
            Instant::now(),
            &mut Vec::new()
        ),
        Err(crate::session_control::SessionControlFailure::UnexpectedAcknowledgement)
    );

    let result = run
        .layout
        .resolve_pending()
        .expect("answered controls settle the pending admission");
    assert_eq!(result.policy_settlement, Some(identity));
    assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
    run.wm
        .apply_commit_result(result, before, run.output.id)
        .unwrap();
    run.ready(false);
    // Ready is transport custody; the peer's checkpoint rename is separate.
    let deadline = Instant::now() + Duration::from_secs(5);
    while run.checkpoint().1 == saved.1 {
        assert!(
            Instant::now() < deadline,
            "committed checkpoint replacement deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    }

    assert_eq!(
        run.layout.next_unmanaged_surface(),
        None,
        "committed Manage answer must end the owner's admission request"
    );
    assert!(!run.layout.unmanaged_surfaces.contains(&NEW));
    assert!(
        !run.layout.manage_settlements.contains_key(&NEW),
        "the surface was placed, not merely answered"
    );
    assert_eq!(run.layout.layers[&NEW].geometry, placed);
    assert_eq!(focus(&run), Some(NEW));
    let model = model(&run);
    assert_eq!(model["windows"].as_array().unwrap().len(), 3);
    let focused = model["outputs"][0]["focusedWindow"].as_u64().unwrap();
    let key = model["surfaces"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["window"].as_u64() == Some(focused))
        .unwrap()["key"]
        .as_u64();
    assert_eq!(
        key,
        Some((u64::from(NEW.generation()) << 32) | u64::from(NEW.index())),
        "client checkpoint focus agrees with Session's committed focus"
    );
    assert_eq!(
        run.layout.admissions.state(NEW),
        awaiting,
        "without pixels admission must remain AwaitingPixels"
    );
    // No later relayout: restaging an AwaitingPixels surface re-enters
    // admission control and would conflate another path.
    run.record("manage-awaiting-pixels");
    run.stop();
}
