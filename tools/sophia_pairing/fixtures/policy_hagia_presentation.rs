//! Normal Hagia, Session settlement and real mirrored backend frame custody.
//! Copy/device/page-flip inputs are explicitly simulated by the backend fixture;
//! neither Presented receipts nor publication stamps are supplied by this test.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;
use sophia_protocol::{PolicyPresentationOutcome, WmActionId};

fn action(wm: &LiveWmSession, name: &str) -> WmActionId {
    wm.public
        .as_ref()
        .unwrap()
        .actions
        .iter()
        .find(|entry| entry.name == name)
        .unwrap()
        .action
}

fn settle_immediate(
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    cpu: &CpuOwner,
    target: &SessionPolicyPresentationFixture,
    output: sophia_engine::HeadlessOutput,
    proposal: LiveWmProposal,
) {
    assert!(wm.preflight_staged_presentation_on_heads(Some(&cpu.runtime), &target.heads()));
    let mut controls = crate::session_control::SessionControlQueue::default();
    let result = layout
        .stage(proposal, &mut controls)
        .unwrap()
        .expect("overview leaves ordinary sizing unchanged");
    assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
    assert!(
        wm.apply_commit_result(result, None, output.id)
            .unwrap()
            .session_action
            .is_none()
    );
    await_ready(wm, layout, output);
}

fn install(
    wm: &mut LiveWmSession,
    cpu: &mut CpuOwner,
    target: &mut SessionPolicyPresentationFixture,
) {
    // The test target supplies two heads and simulated retirement. Passing
    // true here is fixture metadata, never detection of a native device.
    wm.install_committed_policy_presentation(
        &mut cpu.runtime,
        &cpu.scene,
        true,
        false,
        None,
        &target.heads(),
    )
    .unwrap();
    target.queue(&cpu.runtime, &cpu.scene).unwrap();
    target.simulate_submit(cpu.output.id);
}

fn observe(wm: &mut LiveWmSession, cpu: &CpuOwner) {
    let public = wm.public.as_mut().unwrap();
    public.settle_presented_withdrawals(cpu.runtime.input_projections());
    public.observe_presented_policy(cpu.runtime.input_projections());
}

fn run_presentation(case: &str, transport: WmTransportSelection) {
    with_normal_hagia_transport_fixture(
        case,
        transport,
        None,
        true,
        |wm, layout, _, output, checkpoint, identity| {
            let peer = wm.supervisor.peer_id();
            retain_existing_surface(layout);
            let mut cpu = CpuOwner::new(output);
            let old = layout.layers[&SURFACE].geometry;
            cpu.cycle(
                wm,
                layout,
                &cpu_batch(700, 700, 0, OLD_CONTENT_GENERATION, old, OLD_RGB),
                None,
            );
            wm.enqueue_relayout(layout, output).unwrap();
            let proposal = next_proposal(wm, layout, output);
            let mut controls = crate::session_control::SessionControlQueue::default();
            assert!(layout.stage(proposal, &mut controls).unwrap().is_none());
            acknowledge_frontend_controls(layout, &mut controls);
            let geometry = layout
                .pending
                .as_ref()
                .unwrap()
                .layers
                .iter()
                .find(|layer| layer.surface == SURFACE)
                .unwrap()
                .geometry;
            let pixels = cpu_batch(701, 701, 1, NEW_CONTENT_GENERATION, geometry, NEW_RGB);
            assert!(!layout.observe_authority_batch(&pixels).client_route_invalid);
            assert!(layout.pending_is_ready());
            assert!(wm.prepare_public_layout_commit(layout).unwrap());
            let result = layout.resolve_pending().unwrap();
            let applied = wm.apply_commit_result(result, None, output.id).unwrap();
            cpu.cycle(wm, layout, &pixels, Some(applied.update));
            await_ready(wm, layout, output);
            await_checkpoint(checkpoint);

            let mut target = SessionPolicyPresentationFixture::new(&[output]);
            target.queue(&cpu.runtime, &cpu.scene).unwrap();
            target.simulate_submit(output.id);
            target.simulate_head_completion(&mut cpu.runtime, output.id, 0);
            target.simulate_head_completion(&mut cpu.runtime, output.id, 1);
            assert!(cpu.runtime.input_projections()[0].frame_completed);
            assert!(
                cpu.runtime.input_projections()[0]
                    .policy_publication
                    .is_none()
            );

            wm.enqueue_action(action(wm, "toggle-overview"), layout, output)
                .unwrap();
            let proposal = next_proposal(wm, layout, output);
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .staged
                    .as_ref()
                    .unwrap()
                    .presentation_publication()
                    .is_some()
            );
            settle_immediate(wm, layout, &cpu, &target, output, proposal);
            let (_, publication) = wm
                .public
                .as_ref()
                .unwrap()
                .reducer
                .presentation_publication()
                .unwrap();
            let publication = publication.clone();
            assert!(
                !publication.instances.is_empty(),
                "real overview samples the retained surface"
            );
            assert!(
                publication
                    .instances
                    .iter()
                    .all(|instance| instance.source == SURFACE)
            );
            install(wm, &mut cpu, &mut target);
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_input
                    .output_receipt(output.id)
                    .is_none()
            );
            target.simulate_head_completion(&mut cpu.runtime, output.id, 0);
            observe(wm, &cpu);
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_input
                    .output_receipt(output.id)
                    .is_none(),
                "one mirror cannot attest the output"
            );
            assert!(!cpu.runtime.input_projections()[0].frame_completed);
            target.simulate_head_completion(&mut cpu.runtime, output.id, 1);
            observe(wm, &cpu);
            let receipt = wm
                .public
                .as_ref()
                .unwrap()
                .presentation_input
                .output_receipt(output.id)
                .unwrap();
            assert_eq!(receipt.outcome, PolicyPresentationOutcome::Presented);
            assert_eq!(receipt.publication_generation, publication.generation);
            assert_eq!(receipt.connection_epoch, 1);
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_receipts
                    .contains(&receipt)
            );
            let count = wm.public.as_ref().unwrap().presentation_receipts.len();
            observe(wm, &cpu);
            assert_eq!(
                wm.public.as_ref().unwrap().presentation_receipts.len(),
                count,
                "duplicate frame observation emits no second receipt"
            );

            // Change only authority-owned source bytes. The next mirrored frame
            // carries the same publication/target identity and a new source version.
            let repaint = cpu_batch(
                702,
                702,
                2,
                37,
                layout.layers[&SURFACE].geometry,
                [0x22, 0x66, 0xaa, 0xff],
            );
            assert!(
                !layout
                    .observe_authority_batch(&repaint)
                    .client_route_invalid
            );
            cpu.cycle(wm, layout, &repaint, None);
            target.queue(&cpu.runtime, &cpu.scene).unwrap();
            target.simulate_submit(output.id);
            for head in 0..2 {
                target.simulate_head_completion(&mut cpu.runtime, output.id, head);
                observe(wm, &cpu);
            }
            assert_eq!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_input
                    .output_receipt(output.id),
                Some(receipt)
            );
            assert_eq!(
                cpu.runtime.policy_presentation().unwrap().presentation,
                publication
            );

            // Resolve a real presented binding through Engine's input owner. The
            // next answer follows receipt delivery at the shared application
            // point. Presented is a no-op in Hagia's model; accepting this
            // action does not demonstrate a receipt-dependent state change.
            let close = action(wm, "close-overview");
            let binding = publication
                .bindings
                .iter()
                .find(|binding| binding.action == close)
                .unwrap();
            let public = wm.public.as_ref().unwrap();
            assert!(
                public
                    .presentation_input
                    .keyboard_action(binding.keycode, binding.modifiers, true)
                    .is_none(),
                "application capture blocks modal policy input"
            );
            let (action, presented_identity) = public
                .presentation_input
                .keyboard_action(binding.keycode, binding.modifiers, false)
                .unwrap();
            wm.enqueue_presented_action(sophia_engine::PresentedPolicyAction {
                connection_epoch: 1,
                action,
                identity: presented_identity,
            })
            .unwrap();
            let proposal = next_proposal(wm, layout, output);
            assert!(
                matches!(wm.public.as_ref().unwrap().in_flight_request.as_ref().unwrap().cause, PolicyRequestCause::PresentationAction { identity, .. } if identity == presented_identity)
            );
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .staged
                    .as_ref()
                    .unwrap()
                    .presentation_publication()
                    .is_none(),
                "Hagia accepted the exact completed close action"
            );
            settle_immediate(wm, layout, &cpu, &target, output, proposal);
            install(wm, &mut cpu, &mut target);
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_input
                    .publication()
                    .is_none()
            );
            assert!(
                !wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_input
                    .action_is_current(1, close, presented_identity)
            );
            let withdrawn = |wm: &LiveWmSession| {
                wm.public
                    .as_ref()
                    .unwrap()
                    .presentation_receipts
                    .iter()
                    .filter(|r| r.outcome == PolicyPresentationOutcome::Withdrawn)
                    .count()
            };
            assert_eq!(withdrawn(wm), 0);
            target.simulate_head_completion(&mut cpu.runtime, output.id, 0);
            observe(wm, &cpu);
            assert_eq!(
                withdrawn(wm),
                0,
                "old mirror pixels still retain the withdrawal obligation"
            );
            target.simulate_head_completion(&mut cpu.runtime, output.id, 1);
            observe(wm, &cpu);
            assert_eq!(withdrawn(wm), 1);
            assert!(!cpu.runtime.input_projections()[0].policy_visible);
            wm.enqueue_relayout(layout, output).unwrap();
            let next = next_proposal(wm, layout, output);
            assert_eq!(wm.supervisor.peer_id(), peer);
            assert_eq!(next.policy_settlement.unwrap().connection_epoch, 1);
            assert!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .staged
                    .as_ref()
                    .unwrap()
                    .presentation_publication()
                    .is_none()
            );
            writeln!(identity, "presentation_join=real_hagia_session_backend\nheads_per_output=2\nreceipt_source=retired_backend_frame_lists\nsupplied_receipt=false\nsimulated_copy_device_flip=true\nsource_only_repaint=true\nwithdrawal_requires_both_heads=true\napplication_capture_refused=true\nwhole_owner_loop=false\nphysical_acceptance=false").unwrap();
        },
    );
}

#[test]
#[ignore = "requires pinned normal Hagia and explicit simulated backend completion fixture"]
fn normal_hagia_receipts_follow_mirrored_backend_completion_on_both_wires() {
    run_presentation("presentation-ipc", WmTransportSelection::CurrentIpc);
    run_presentation("presentation-files", WmTransportSelection::NineP2000L);
}
