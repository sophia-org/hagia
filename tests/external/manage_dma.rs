//! Admission uses real Hagia and the production GPU cycle. Worker storage,
//! completion and startup device observations are supplied; no GPU is opened.
use super::*;

pub(super) fn frame(
    batch: &mut sophia_x_authority::XAuthorityObservedTransactionBatch,
    geometry: Rect,
) -> sophia_protocol::SurfaceTransactionKey {
    let mut transaction = super::frame(batch, FIRST, FIRST_FILL, geometry, 0);
    batch.cpu_buffer_updates.clear();
    transaction.content =
        SurfaceContentSet::singleton(BufferSource::DmaBuf { handle: FIRST }, EXTENT);
    *batch.transactions.last_mut().unwrap() = transaction.clone();
    let handle = sophia_protocol::BufferHandle::from_raw(FIRST);
    batch
        .dma_buf_registrations
        .push(sophia_x_authority::XAuthorityDmaBufRegistration {
            pixmap: sophia_x_authority::XResourceId::new((FIRST as u32).into(), 1),
            descriptor: sophia_protocol::DmaBufDescriptor {
                handle,
                size: EXTENT,
                format: sophia_backend_live::LIVE_RENDERER_SCANOUT_FORMAT_XRGB8888,
                modifier: sophia_protocol::DRM_FORMAT_MOD_INVALID,
                plane_count: 1,
                planes: [
                    Some(sophia_protocol::DmaBufPlaneDescriptor {
                        offset: 0,
                        stride: EXTENT.width as u32 * 4,
                    }),
                    None,
                    None,
                    None,
                ],
            },
            plane_fds: vec![std::sync::Arc::new(
                std::fs::File::open("/dev/null").unwrap().into(),
            )],
        });
    batch
        .present_submissions
        .push(sophia_x_authority::XAuthorityPresentSubmission {
            transaction: transaction.transaction,
            surface: NEW,
            buffer: handle,
            x_offset: 0,
            y_offset: 0,
            acquire_fence: None,
            idle_fence: None,
        });
    transaction.key()
}

pub(super) fn retire(
    run: &mut Lifecycle,
    runtime: &mut sophia_backend_live::LiveProductionVisualRuntime,
    native: &mut SessionPolicyPresentationFixture,
    candidate: sophia_protocol::SurfaceTransactionKey,
    placed: Rect,
) {
    use sophia_engine::SurfacePresentationAdmissionState as Admission;
    assert!(
        committed(runtime).is_none(),
        "DMA admission cannot commit before retirement"
    );
    assert!(
        matches!(run.layout.admissions.state(NEW), Admission::AwaitingRetirement { visual_candidate, .. } if visual_candidate == candidate)
    );
    native.simulate_dma_submit(runtime, run.output.id).unwrap();
    assert!(
        native
            .simulate_native_retirement(runtime, run.output.id, 1)
            .unwrap()
            .is_none()
    );
    assert!(
        committed(runtime).is_none(),
        "sibling completion cannot commit DMA admission"
    );
    let retired = native
        .simulate_native_retirement(runtime, run.output.id, 0)
        .unwrap()
        .expect("primary retirement must return the DMA admission candidate");
    assert_eq!(retired.candidate, candidate);
    assert_eq!(retired.source_size, EXTENT);
    assert!(retired.ust_usec > 0 && retired.msc > 0);
    let first = committed(runtime).unwrap();
    assert_eq!(
        (first.committed_generation, first.buffer(), first.geometry),
        (1, candidate.target_buffer, placed)
    );
    assert!(
        matches!(
            run.layout.admissions.state(NEW),
            Admission::AwaitingRetirement { .. }
        ),
        "Engine retirement alone cannot finish Session admission"
    );
    let mut evidence = crate::live_session::NativePresentEvidence::new(false);
    let mut retired_surfaces = BTreeMap::new();
    let mut startup_presentations =
        crate::live_session::StartupSurfacePresentationEvidence::default();
    let mut startup = crate::session_startup::SessionStartupReadiness::default();
    let observed =
        crate::live_session::native_retirement::record_native_present_retirement_with_observation(
            crate::live_session::NativePresentRecording {
                layout: &mut run.layout,
                evidence: &mut evidence,
            },
            retired,
            &mut retired_surfaces,
            &mut startup_presentations,
            &mut startup,
            |_| (false, 0), // No stable-device or nonzero-pixel evidence is supplied.
        );
    assert_eq!(observed.surface, NEW);
    assert!(!observed.stable);
    assert_eq!(retired_surfaces.get(&NEW), Some(&candidate.transaction));
    assert!(!startup_presentations.stable_presented(NEW));
    assert!(
        matches!(run.layout.admissions.state(NEW), Admission::Managed),
        "DMA retirement recorder must finish Session admission"
    );
}
