//! A source-only repaint under a presented switcher. One previewed surface
//! commits new CPU bytes through production intake and the ordinary CPU
//! cycle, with no WM request. The backend recomposes the retained switcher on
//! the test-support target's two mirror heads, and each retired frame's
//! preview instances are read back: the backend, never the WM, resolves each
//! instance's source generation. The fixture queues that recomposition
//! itself, so production's repaint scheduling is not exercised; the target
//! does not rasterize, so no preview pixels are claimed. CPU sources and the
//! device submit and page flips are supplied; one output, no physical display.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;

const REPAINT_HANDLE: u64 = 402;
const REPAINT_FILL: u8 = 0x9c;

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
/// projections the runtime derived from the retired frame lists.
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

/// Each head's retired previews as (id, generation, source, source generation).
fn previews(
    target: &SessionPolicyPresentationFixture,
    output: OutputId,
) -> Vec<Vec<(u64, u64, SurfaceId, u64)>> {
    target
        .presented_surface_instances(output)
        .into_iter()
        .map(|head| {
            head.into_iter()
                .map(|i| (i.id, i.generation, i.source, i.source_generation))
                .collect()
        })
        .collect()
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_presented_source_repaint_preserves_identity() {
    let Held {
        mut run,
        mut content,
        first,
        expected,
        ..
    } = held("presented-repaint");
    let output = first.outputs[0];
    log(
        &run,
        "presentation_completion=simulated_per_head receipts=backend_derived heads=target_mirrored repaint_queue=fixture",
    );

    // Present the held switcher on both mirror heads, as the consensus case.
    let mut target = SessionPolicyPresentationFixture::new(&[run.output]);
    assert_eq!(target.heads().len(), 2);
    install_on(&mut run, &mut content, &target);
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    retire(&mut run, &mut content, &mut target, 0);
    let presented = retire(&mut run, &mut content, &mut target, 1);
    let receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(output.output)
        .expect("both mirror heads retired the switcher");
    assert_eq!(receipt.outcome, PolicyPresentationOutcome::Presented);
    assert_eq!(receipt.publication_generation, first.generation);
    assert_eq!(receipts(&run), vec![receipt]);
    drain(&mut run);
    let stamp = presented[0].policy_publication.clone().unwrap();

    // Every preview first samples its source's only committed generation.
    let repainted = expected[1];
    let before = previews(&target, output.output);
    assert_eq!(before.len(), 2);
    for head in &before {
        assert!(head.iter().any(|preview| preview.2 == repainted));
        assert!(head.iter().all(|preview| preview.3 == 1), "{head:?}");
    }
    let requests = run.wm.requests;

    // A source-only commit for one previewed surface through production
    // intake: observation, projection and one ordinary CPU cycle. No relayout,
    // action or other WM cause is queued.
    let layer = run.layout.layers[&repainted].clone();
    let size = layer.source_size;
    let transaction = TransactionId::from_raw(950);
    let mut batch = crate::live_session::wm_update_coordinator_batch(transaction);
    batch.transactions.push(SurfaceTransaction {
        input_region: None,
        transaction,
        authority: AuthorityKind::SophiaX,
        surface: repainted,
        namespace: None,
        target_geometry: layer.geometry,
        presentation_extent: size,
        content: SurfaceContentSet::singleton(
            BufferSource::CpuBuffer {
                handle: REPAINT_HANDLE,
            },
            size,
        ),
        damage: Region::single(Rect {
            x: 0,
            y: 0,
            width: size.width,
            height: size.height,
        }),
        readiness: SurfaceTransactionReadiness::Ready,
        timeout_msec: 250,
        previous_committed_generation: 1,
    });
    let bytes = vec![REPAINT_FILL; (size.width * size.height * 4) as usize];
    batch
        .cpu_buffer_updates
        .push(sophia_x_authority::XAuthorityCpuBufferUpdate::Replace(
            sophia_x_authority::XAuthorityCpuBufferSnapshot {
                handle: REPAINT_HANDLE,
                drawable: sophia_x_authority::XResourceId::new((REPAINT_HANDLE as u32).into(), 1),
                size,
                stride: size.width as u32 * 4,
                format: sophia_backend_live::LIVE_RENDERER_SCANOUT_FORMAT_XRGB8888,
                generation: 2,
                bytes: Arc::new(bytes.clone()),
            },
        ));
    assert!(
        !run.layout
            .observe_authority_batch(&batch)
            .client_route_invalid
    );
    let (projected, released) = run.layout.projected_batch(&batch);
    assert!(released.is_empty());
    let production =
        crate::live_session::production_authority_batch(&projected, &released, &run.layout)
            .unwrap();
    production.validate().unwrap();
    let layers = SURFACES
        .iter()
        .map(|surface| run.layout.layers[surface].clone())
        .collect::<Vec<_>>();
    content
        .runtime
        .run_cpu_production_cycle(LiveProductionCycleRequest {
            batch: &production,
            scene: &mut content.scene,
            raised_surface: None,
            focused_surface: focus(&run),
            cursor_presentation: LiveProductionCursorPresentation::Software(None),
            defer_frame: false,
            output_descriptors: &[run.output],
            native_scanout: None,
            wm_update: None,
            presentation_layout: &layers,
            geometry_routed_surfaces: &[],
            chrome_surfaces: &SURFACES,
            indicator_publication: None,
            staged_cpu_buffer_handles: &[],
        })
        .unwrap();
    let committed = content
        .runtime
        .committed_surfaces()
        .iter()
        .find(|state| state.surface == repainted)
        .unwrap()
        .clone();
    assert_eq!(
        (committed.committed_generation, committed.buffer()),
        (
            2,
            BufferSource::CpuBuffer {
                handle: REPAINT_HANDLE
            }
        )
    );

    // The backend recomposes the retained switcher; both heads retire it.
    target.queue(&content.runtime, &content.scene).unwrap();
    target.simulate_submit(output.output);
    retire(&mut run, &mut content, &mut target, 0);
    let retired = retire(&mut run, &mut content, &mut target, 1);

    {
        let public = run.wm.public.as_ref().unwrap();
        assert!(
            run.wm.requests == requests
                && public.in_flight_request.is_none()
                && public.queue.is_empty(),
            "source-only repaint must not start a WM cycle"
        );
        assert!(
            public.presentation_input.output_receipt(output.output) == Some(receipt)
                && public.presentation_receipts.is_empty()
                && content
                    .runtime
                    .policy_presentation()
                    .is_some_and(|installed| installed.presentation == first)
                && retired[0].policy_publication.as_ref() == Some(&stamp),
            "source-only repaint keeps the presented identity"
        );
    }
    let resampled = before
        .iter()
        .map(|head| {
            head.iter()
                .map(|&(id, generation, source, sampled)| {
                    (
                        id,
                        generation,
                        source,
                        if source == repainted { 2 } else { sampled },
                    )
                })
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    assert_eq!(
        previews(&target, output.output),
        resampled,
        "retired previews must sample the repainted source"
    );

    // Diagnostics, after the behavior: the retired frame's application layer
    // and the scene's retained source bytes.
    let presented_layer = retired[0]
        .layers
        .iter()
        .find(|layer| layer.surface == repainted)
        .unwrap();
    assert_eq!(
        (presented_layer.generation, presented_layer.source),
        (
            2,
            BufferSource::CpuBuffer {
                handle: REPAINT_HANDLE
            }
        )
    );
    let retained = content
        .scene
        .presentation_layers(content.runtime.committed_surfaces(), &[repainted]);
    assert_eq!(retained.len(), 1);
    assert_eq!(*retained[0].buffer.bytes, bytes);

    // Poll without admitting work before endpoint teardown. This observes
    // transport and supervisor health, not a new policy round trip.
    assert!(
        run.wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap()
            .is_none(),
        "source-only repaint must not produce a proposal before teardown"
    );
    let public = run.wm.public.as_ref().unwrap();
    assert!(
        !run.wm.degraded
            && !run.wm.force_transport_restart
            && !public.transport_unavailable
            && public.connection_epoch == receipt.connection_epoch,
        "peer healthy before repaint teardown"
    );
    assert!(
        run.wm.requests == requests
            && public.in_flight_request.is_none()
            && public.queue.is_empty(),
        "source-only repaint must not start a WM cycle"
    );
    assert!(
        run.wm.supervisor.poll().unwrap().is_none(),
        "peer alive before repaint teardown"
    );
    log(
        &run,
        &format!("phase=repainted source={repainted:?} generation=2 presented={receipt:?}"),
    );
    run.record("source-repaint-presented");
    run.stop();
}
