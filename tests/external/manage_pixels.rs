//! A new policy-managed surface whose first frame is supplied CPU content.
//! Production intake quarantines it, selects it as the
//! admission candidate and its extent; real Hagia places the surface, Session
//! reconciles that placement to the extent, and the supplied control answers
//! let the staged candidate commit. The released frame then passes
//! through the owner loop's projection and the ordinary CPU production cycle.
//! Proven: Session admission to Managed; CPU production commit of the source
//! identity, generation and geometry; the scene's retained source bytes; and
//! one interior pixel of the headless CPU composed frame. Not proven: native
//! scanout, pixels on any physical head, or frontend map/configure delivery.
//! The software-Present variant waits for the headless backend's copy retirement
//! record and passes it to Session's retirement owner. The fixture drives that
//! drain and call; it does not exercise native service selection or page flips.
use super::*;

const NEW: SurfaceId = SurfaceId::new(61, 1);
/// Deliberately unlike any tile of three windows on the headless output.
const EXTENT: Size = Size {
    width: 173,
    height: 111,
};
const FIRST: u64 = 611;
const SECOND: u64 = 612;
const FIRST_FILL: u8 = 0x5a;
const SECOND_FILL: u8 = 0xa5;

fn bytes(fill: u8) -> Vec<u8> {
    vec![fill; (EXTENT.width * EXTENT.height * 4) as usize]
}

/// One CPU backing snapshot of `handle` for the new surface, without any
/// software Present: production records it as BackingSnapshot evidence.
fn frame(
    batch: &mut sophia_x_authority::XAuthorityObservedTransactionBatch,
    handle: u64,
    fill: u8,
    geometry: Rect,
    previous_committed_generation: u64,
) -> SurfaceTransaction {
    let transaction = SurfaceTransaction {
        input_region: None,
        transaction: batch.transaction,
        authority: AuthorityKind::SophiaX,
        surface: NEW,
        namespace: None,
        target_geometry: geometry,
        presentation_extent: EXTENT,
        content: SurfaceContentSet::singleton(BufferSource::CpuBuffer { handle }, EXTENT),
        damage: Region::single(Rect {
            x: 0,
            y: 0,
            width: EXTENT.width,
            height: EXTENT.height,
        }),
        readiness: SurfaceTransactionReadiness::Ready,
        timeout_msec: 250,
        previous_committed_generation,
    };
    batch.transactions.push(transaction.clone());
    batch
        .cpu_buffer_updates
        .push(sophia_x_authority::XAuthorityCpuBufferUpdate::Replace(
            sophia_x_authority::XAuthorityCpuBufferSnapshot {
                handle,
                drawable: sophia_x_authority::XResourceId::new((handle as u32).into(), 1),
                size: EXTENT,
                stride: EXTENT.width as u32 * 4,
                format: sophia_backend_live::LIVE_RENDERER_SCANOUT_FORMAT_XRGB8888,
                generation: previous_committed_generation + 1,
                bytes: std::sync::Arc::new(bytes(fill)),
            },
        ));
    transaction
}

/// The owner loop's authority-to-production step for one observed batch:
/// projection releases admitted groups, then one ordinary CPU cycle runs.
/// Returns each released group's transactions and whether a frame composed.
fn produce(
    run: &mut Lifecycle,
    runtime: &mut sophia_backend_live::LiveProductionVisualRuntime,
    scene: &mut sophia_backend_live::LiveProductionCpuScene,
    batch: &sophia_x_authority::XAuthorityObservedTransactionBatch,
) -> (Vec<Vec<SurfaceTransaction>>, bool) {
    let (projected, released) = run.layout.projected_batch(batch);
    let production =
        crate::live_session::production_authority_batch(&projected, &released, &run.layout)
            .unwrap();
    production.validate().unwrap();
    let layers = run.layout.layers.values().cloned().collect::<Vec<_>>();
    let surfaces = run.layout.layers.keys().copied().collect::<Vec<_>>();
    let output = run.output;
    let (submission, _, _) = runtime
        .run_cpu_production_cycle(sophia_backend_live::LiveProductionCycleRequest {
            batch: &production,
            scene,
            raised_surface: None,
            focused_surface: focus(run),
            cursor_presentation: sophia_backend_live::LiveProductionCursorPresentation::Software(
                None,
            ),
            defer_frame: false,
            output_descriptors: &[output],
            native_scanout: None,
            wm_update: None,
            presentation_layout: &layers,
            geometry_routed_surfaces: &[],
            chrome_surfaces: &surfaces,
            indicator_publication: None,
            staged_cpu_buffer_handles: &[],
        })
        .unwrap();
    let released = released
        .into_iter()
        .map(|group| group.transactions)
        .collect();
    (released, submission.composed)
}

/// The scene's retained source for the new surface, and one interior pixel
/// of the last headless CPU composed frame at its committed geometry.
fn retained(
    runtime: &sophia_backend_live::LiveProductionVisualRuntime,
    scene: &sophia_backend_live::LiveProductionCpuScene,
    handle: u64,
    generation: u64,
    fill: u8,
    geometry: Rect,
) {
    let layers = scene.presentation_layers(runtime.committed_surfaces(), &[NEW]);
    let [layer] = &layers[..] else {
        panic!("one retained CPU source for the new surface: {layers:?}");
    };
    assert_eq!(layer.geometry, geometry);
    assert_eq!(
        (
            layer.buffer.handle,
            layer.buffer.generation,
            layer.buffer.size
        ),
        (handle, generation, EXTENT)
    );
    assert_eq!(*layer.buffer.bytes, bytes(fill), "retained source bytes");
    let frame = &scene
        .last_report()
        .expect("a composed headless frame")
        .frame;
    let x = (geometry.x + geometry.width / 2) as usize;
    let y = (geometry.y + geometry.height / 2) as usize;
    let offset = y * frame.stride as usize + x * 4;
    assert_eq!(
        frame.bytes[offset..offset + 3],
        [fill; 3],
        "headless composed interior pixel"
    );
}

fn committed(
    runtime: &sophia_backend_live::LiveProductionVisualRuntime,
) -> Option<sophia_protocol::CommittedSurfaceState> {
    runtime
        .committed_surfaces()
        .iter()
        .find(|state| state.surface == NEW)
        .cloned()
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_occupied_manage_admits_cpu_candidate() {
    admission_case(false);
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_occupied_manage_admits_software_present() {
    admission_case(true);
}

fn admission_case(software_present: bool) {
    let mut run = Lifecycle::new(if software_present {
        "manage-software-present"
    } else {
        "manage-cpu-candidate"
    });
    populate(&mut run);
    let before = focus(&run);
    let saved = run.checkpoint();
    use sophia_engine::SurfacePresentationAdmissionState as Admission;

    // B1: the X authority's request and the client's first frame together.
    let client = sophia_x_authority::XServerFrontendClientId::from_raw(1);
    let requested = Rect {
        x: 430,
        y: 30,
        width: EXTENT.width,
        height: EXTENT.height,
    };
    let intent = SurfacePresentationIntent {
        surface: NEW,
        kind: SurfacePresentationIntentKind::Request,
        role: SurfacePresentationRole::PolicyManaged,
        surface_kind: LayoutNodeKind::Toplevel,
        placement_preference: SurfacePlacementPreference::Default,
        presentation_owner: None,
        stack_rank: 2,
        geometry: requested,
        constraints: SurfaceConstraints {
            min_size: None,
            max_size: None,
        },
        generation: 1,
    };
    let mut batch = crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(720));
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
            geometry: requested,
            constraints: intent.constraints,
            generation: intent.generation,
        },
    );
    let candidate = frame(&mut batch, FIRST, FIRST_FILL, requested, 0).key();
    if software_present {
        batch.software_present_submissions.push(
            sophia_x_authority::XAuthoritySoftwarePresentSubmission {
                transaction: candidate.transaction,
                surface: NEW,
                acquire_fence: None,
                idle_fence: None,
            },
        );
    }
    assert!(
        !run.layout
            .observe_authority_batch(&batch)
            .client_route_invalid
    );
    assert_eq!(run.layout.admissions.state(NEW), Admission::PolicyPending);
    let observation = run.layout.layout_epochs.safe_observation(NEW).unwrap();
    assert_eq!(observation.candidate, Some(candidate));
    assert_eq!(observation.extent, EXTENT);
    assert_eq!(
        observation.evidence,
        if software_present {
            sophia_engine::SurfaceVisualEvidence::PresentedBuffer
        } else {
            sophia_engine::SurfaceVisualEvidence::BackingSnapshot
        }
    );
    // The recovery extent itself is checked through B2's reconciliation.
    assert!(
        run.layout
            .pre_admission_groups
            .iter()
            .any(|group| group.transaction == batch.transaction),
        "the first frame is quarantined until admission"
    );
    assert!(!run.layout.layers.contains_key(&NEW));
    assert!(run.layout.pending.is_none());
    assert_eq!(run.layout.next_unmanaged_surface(), Some(NEW));

    // B2: real Hagia places it; Session reconciles to the candidate extent.
    assert!(matches!(
        run.wm.enqueue_manage(NEW, &run.layout, run.output).unwrap(),
        LiveWmRequestAdmission::Admitted
    ));
    let proposal = run.proposal();
    let identity = proposal.policy_settlement.unwrap();
    let placed = proposal
        .layers
        .iter()
        .find(|layer| layer.surface == NEW)
        .expect("Hagia must place the requested surface")
        .geometry;
    assert_eq!(
        (placed.width, placed.height),
        (EXTENT.width, EXTENT.height),
        "Session must reconcile admission to the safe candidate extent"
    );
    assert_eq!(proposal.requested_sizes.get(&NEW), Some(&EXTENT));
    assert_eq!(proposal.focus, Some(NEW));
    let state = proposal.presentation_states[&NEW];

    // B3: production staging selects the quarantined candidate.
    let mut controls = crate::session_control::SessionControlQueue::default();
    assert!(run.layout.stage(proposal, &mut controls).unwrap().is_none());
    assert_eq!(
        run.layout.admissions.state(NEW),
        Admission::ControlPending {
            transaction: identity.transaction,
            geometry: placed,
        }
    );
    {
        let pending = run.layout.pending.as_ref().unwrap();
        assert_eq!(
            pending.staged_transactions.get(&NEW).map(|t| t.key()),
            Some(candidate),
            "staging must select the exact quarantined candidate"
        );
        assert_eq!(
            pending
                .layers
                .iter()
                .find(|layer| layer.surface == NEW)
                .unwrap()
                .source,
            BufferSource::CpuBuffer { handle: FIRST }
        );
    }

    // B4: Tier 1's dispatch and supplied answers through the production queue.
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
    for kind in [
        sophia_x_authority::XAuthorityControlKind::AdmitSurface,
        sophia_x_authority::XAuthorityControlKind::SetPresentationState,
    ] {
        acknowledge
            .try_send(sophia_x_authority::XAuthorityClientControlAck {
                client,
                acknowledgement: sophia_x_authority::XAuthorityControlAck {
                    kind,
                    transaction: identity.transaction,
                    surface: NEW,
                    outcome: sophia_x_authority::XAuthorityControlOutcome::Delivered,
                },
            })
            .unwrap();
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

    // B5: a backing snapshot admits immediately; a Present still owes retirement.
    let result = run
        .layout
        .resolve_pending()
        .expect("answered controls and the exact candidate settle the pending admission");
    assert_eq!(result.policy_settlement, Some(identity));
    assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
    if software_present {
        assert_eq!(
            run.layout.admissions.state(NEW),
            Admission::AwaitingRetirement {
                admission_transaction: identity.transaction,
                visual_candidate: candidate,
                geometry: placed,
            },
            "a presented candidate must wait for retirement"
        );
    }
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
    assert_eq!(run.layout.next_unmanaged_surface(), None);
    let layer = run.layout.layers[&NEW].clone();
    assert_eq!(layer.geometry, placed);
    assert_eq!(layer.source, BufferSource::CpuBuffer { handle: FIRST });

    // B6: the next authority turn releases the admitted frame to production.
    let output = run.output;
    let mut runtime =
        sophia_backend_live::LiveProductionVisualRuntime::new(&[output], None).unwrap();
    let mut scene = sophia_backend_live::LiveProductionCpuScene::new(output.size);
    let next = crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(721));
    assert!(
        !run.layout
            .observe_authority_batch(&next)
            .client_route_invalid
    );
    let (released, composed) = produce(&mut run, &mut runtime, &mut scene, &next);
    assert_eq!(
        released.len(),
        1,
        "the admitted frame must reach production"
    );
    assert!(released[0].iter().all(|t| t.surface == NEW
        && t.target_geometry == placed
        && t.previous_committed_generation == 0));
    let first = committed(&runtime).expect("the admitted frame must reach production");
    assert_eq!(first.committed_generation, 1);
    assert_eq!(first.buffer(), BufferSource::CpuBuffer { handle: FIRST });
    assert_eq!(first.geometry, placed);
    assert!(composed);
    retained(&runtime, &scene, FIRST, 1, FIRST_FILL, placed);

    if software_present {
        let mut retired = Vec::new();
        runtime
            .drain_retired_software_presents_into(&mut retired)
            .unwrap();
        assert_eq!(
            retired.len(),
            1,
            "production must retire the exact software Present candidate"
        );
        let retired = retired[0];
        assert_eq!(
            (retired.candidate, retired.source_size),
            (candidate, EXTENT),
            "production must retire the exact software Present candidate"
        );
        assert_eq!(
            (
                retired.frame.raw(),
                retired.native_submission,
                retired.ust_usec,
                retired.msc
            ),
            (0, 0, 0, 0),
            "headless copy retirement carries no native frame or timing evidence"
        );
        // Direct production owner call. The record is generated by the CPU
        // backend, but draining here does not qualify the native service loop.
        let mut evidence = crate::live_session::NativePresentEvidence::new(false);
        crate::live_session::record_native_software_present_retirement(
            crate::live_session::NativePresentRecording {
                layout: &mut run.layout,
                evidence: &mut evidence,
            },
            retired,
        );
    }

    // B7: a managed surface's next frame is not quarantined again.
    let mut batch = crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(722));
    batch.client = Some(client);
    frame(&mut batch, SECOND, SECOND_FILL, placed, 1);
    assert!(
        !run.layout
            .observe_authority_batch(&batch)
            .client_route_invalid
    );
    let (released, composed) = produce(&mut run, &mut runtime, &mut scene, &batch);
    assert!(released.is_empty());
    let second = committed(&runtime).unwrap();
    assert_eq!(
        (second.committed_generation, second.buffer()),
        (2, BufferSource::CpuBuffer { handle: SECOND }),
        "{}",
        if software_present {
            "a retired admission's next frame must reach production"
        } else {
            "a managed surface's next frame must reach production"
        }
    );
    assert_eq!(second.geometry, placed);
    assert!(composed);
    retained(&runtime, &scene, SECOND, 2, SECOND_FILL, placed);

    // Session state, checked after the behavior it explains.
    assert_eq!(run.layout.admissions.state(NEW), Admission::Managed);
    assert!(!run.layout.planning_surfaces.contains_key(&NEW));
    assert_eq!(run.layout.layout_epochs.recovery_extent(NEW), None);
    assert_eq!(focus(&run), Some(NEW));
    let model = model(&run);
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
    run.record(if software_present {
        "manage-software-present-managed"
    } else {
        "manage-cpu-managed"
    });
    run.stop();
}
