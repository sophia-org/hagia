//! Ordinary Hagia's recent-windows switcher through Session's chord,
//! presentation, held-capture and receipt owners. Supplied, and labelled so:
//! the native presentation ceiling is selected without a device; three CPU
//! surfaces are committed through the ordinary CPU production cycle, bypassing
//! Session admission and visual-readiness projection of their pixels; display
//! heads, presentation completions, router time and occupied facts are given
//! by the fixture. No native retirement, pixels, physical input device or
//! latency is claimed. A receipt leaving Session's queue is transport progress,
//! not proof that the peer consumed or acknowledged it, and Hagia's model
//! ignores Presented receipts.
use super::*;
use sophia_backend_live::{
    LivePolicyPresentation, LivePolicyPresentationRefusal, LivePresentedInputProjection,
    LivePresentedPolicyPublication, LiveProductionCpuScene, LiveProductionCursorPresentation,
    LiveProductionCycleRequest, LiveProductionVisualRuntime,
};
use sophia_protocol::*;
use std::sync::Arc;

#[path = "presentation_revocation.rs"]
mod revocation;

#[path = "presentation_disconnect.rs"]
mod disconnect;

#[path = "presentation_cancel.rs"]
mod cancel;

#[path = "presentation_consensus.rs"]
mod consensus;

#[path = "presentation_repaint.rs"]
mod repaint;

#[path = "presentation_service.rs"]
mod presentation_service;

const SURFACES: [SurfaceId; 3] = [
    SurfaceId::new(31, 2),
    SurfaceId::new(47, 5),
    SurfaceId::new(53, 3),
];
const HANDLES: [u64; 3] = [301, 302, 303];
const ALT: u32 = 56;
const TAB: u32 = 15;
const RIGHT: u32 = 106;
/// The fixture's own profile: the bootstrap profile plus one binding. Its
/// bytes are compared and hashed into the evidence.
const DESKTOP: &str = "schema 1\nshell { enabled #false; }\nsession { terminal \"terminal\"; browser \"brave-origin\"; startup \"panel\"; }\nshortcut { profile \"default\"; bind \"Alt+Tab\" \"policy:recent-window-next\"; }\n";

fn key_of(surface: SurfaceId) -> u64 {
    (u64::from(surface.generation()) << 32) | u64::from(surface.index())
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

fn focus(run: &Lifecycle) -> Option<SurfaceId> {
    run.wm.public.as_ref().unwrap().reducer.committed()[0].focus
}

fn action_id(run: &Lifecycle, name: &str) -> WmActionId {
    run.wm
        .public
        .as_ref()
        .unwrap()
        .actions
        .iter()
        .find(|a| a.name == name)
        .unwrap()
        .action
}

fn credits(run: &Lifecycle) -> usize {
    run.wm.shortcuts.as_ref().unwrap().chord_credits_free()
}

/// Release debt is private to the capture owner; its Debug form is the only
/// read-only view, so presence is checked by the captured key's entry.
fn owes(run: &Lifecycle, keycode: u32) -> bool {
    let capture = format!("{:?}", run.wm.public.as_ref().unwrap().presentation_capture);
    assert!(capture.contains("exhausted: false"), "{capture}");
    capture.contains(&format!("Key({keycode})"))
}

fn receipts(run: &Lifecycle) -> Vec<PolicyPresentationReceipt> {
    run.wm
        .public
        .as_ref()
        .unwrap()
        .presentation_receipts
        .iter()
        .copied()
        .collect()
}

/// Poll without admitting a new cycle until Session's receipt queue is empty.
/// Each receipt needs the capacity-one command queue, so Ready can precede the
/// last flush. Drained means handed to the transport worker: progress only,
/// not proof that the peer consumed or acknowledged a receipt.
fn drain(run: &mut Lifecycle) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !receipts(run).is_empty() {
        assert!(
            run.wm
                .poll_public_request(&mut run.layout, run.output, false)
                .unwrap()
                .is_none()
        );
        assert!(!run.wm.degraded && !run.wm.force_transport_restart);
        assert!(Instant::now() < deadline, "receipt queue drain deadline");
        std::thread::sleep(Duration::from_millis(2));
    }
}

fn log(run: &Lifecycle, line: &str) {
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(run.evidence.join("observations.txt"))
        .unwrap();
    writeln!(file, "{line}").unwrap();
}

/// Three mapped policy-managed surfaces, as in `occupied.rs`, whose committed
/// layers name the CPU buffers committed below.
fn populate(run: &mut Lifecycle) {
    let client = sophia_x_authority::XServerFrontendClientId::from_raw(1);
    let mut batch = crate::live_session::wm_update_coordinator_batch(TransactionId::from_raw(700));
    batch.client = Some(client);
    for (i, (surface, handle)) in SURFACES.into_iter().zip(HANDLES).enumerate() {
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
                source: BufferSource::CpuBuffer { handle },
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
        3,
        "all supplied surfaces reach the peer"
    );
    run.commit(proposal); // Supplied completion, not a visual-readiness proof.
    run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
    let proposal = run.proposal();
    run.commit(proposal);
    assert!(focus(run).is_some());
    for (surface, handle) in SURFACES.into_iter().zip(HANDLES) {
        assert_eq!(
            run.layout.layers[&surface].source,
            BufferSource::CpuBuffer { handle },
            "committed layers keep the supplied CPU source"
        );
    }
    run.record("presented-baseline");
}

/// The headless visual owner, holding the committed CPU sources for the
/// case's lifetime, and the supplied head the publication is checked against.
struct Content {
    runtime: LiveProductionVisualRuntime,
    scene: LiveProductionCpuScene,
    head: sophia_engine::HeadRenderTarget,
}

/// One ordinary CPU production cycle commits owned bytes for each surface.
fn commit_cpu_sources(run: &Lifecycle) -> Content {
    let output = run.output;
    let mut runtime = LiveProductionVisualRuntime::new(&[output], None).unwrap();
    let mut scene = LiveProductionCpuScene::new(output.size);
    let transaction = TransactionId::from_raw(900);
    let mut observed = crate::live_session::wm_update_coordinator_batch(transaction);
    for (surface, handle) in SURFACES.into_iter().zip(HANDLES) {
        let layer = &run.layout.layers[&surface];
        let size = layer.source_size;
        observed.transactions.push(SurfaceTransaction {
            input_region: None,
            transaction,
            authority: AuthorityKind::SophiaX,
            surface,
            namespace: None,
            target_geometry: layer.geometry,
            presentation_extent: size,
            content: SurfaceContentSet::singleton(BufferSource::CpuBuffer { handle }, size),
            damage: Region::single(Rect {
                x: 0,
                y: 0,
                width: size.width,
                height: size.height,
            }),
            readiness: SurfaceTransactionReadiness::Ready,
            timeout_msec: 250,
            previous_committed_generation: 0,
        });
        observed
            .cpu_buffer_updates
            .push(sophia_x_authority::XAuthorityCpuBufferUpdate::Replace(
                sophia_x_authority::XAuthorityCpuBufferSnapshot {
                    handle,
                    drawable: sophia_x_authority::XResourceId::new((handle as u32).into(), 1),
                    size,
                    stride: size.width as u32 * 4,
                    format: sophia_backend_live::LIVE_RENDERER_SCANOUT_FORMAT_XRGB8888,
                    generation: 1,
                    bytes: Arc::new(vec![0x40; (size.width * size.height * 4) as usize]),
                },
            ));
    }
    let batch =
        crate::live_session::production_authority_batch(&observed, &[], &run.layout).unwrap();
    batch.validate().unwrap();
    let layers = SURFACES
        .iter()
        .map(|surface| run.layout.layers[surface].clone())
        .collect::<Vec<_>>();
    let (submission, _, _) = runtime
        .run_cpu_production_cycle(LiveProductionCycleRequest {
            batch: &batch,
            scene: &mut scene,
            raised_surface: None,
            focused_surface: focus(run),
            cursor_presentation: LiveProductionCursorPresentation::Software(None),
            defer_frame: false,
            output_descriptors: &[output],
            native_scanout: None,
            wm_update: None,
            presentation_layout: &layers,
            geometry_routed_surfaces: &[],
            chrome_surfaces: &SURFACES,
            indicator_publication: None,
            staged_cpu_buffer_handles: &[],
        })
        .unwrap();
    assert!(submission.composed);
    assert!(!runtime.native_scanout_in_flight());
    let committed = runtime.committed_surfaces();
    assert_eq!(committed.len(), 3, "{committed:?}");
    for (surface, handle) in SURFACES.into_iter().zip(HANDLES) {
        let state = committed.iter().find(|s| s.surface == surface).unwrap();
        assert_eq!(state.committed_generation, 1);
        assert_eq!(state.buffer(), BufferSource::CpuBuffer { handle });
    }
    let scene_output = &run.wm.public.as_ref().unwrap().reducer.scene().outputs[0];
    let head = sophia_engine::HeadRenderTarget {
        head: sophia_engine::RenderHeadId::from_raw(1),
        output: scene_output.output,
        target_generation: 1,
        native_size: Size {
            width: scene_output.bounds.width,
            height: scene_output.bounds.height,
        },
        scale: 1,
        refresh_millihz: 60_000,
        transform: OutputTransform::Normal,
        mapping: OutputHeadMapping::Fit,
    };
    Content {
        runtime,
        scene,
        head,
    }
}

/// A supplied completed frame of `publication` on its output: the stamp names
/// exactly the publication's targets there, held keyboard scope.
fn completed(
    content: &Content,
    publication: &PolicyPresentation,
) -> Vec<LivePresentedInputProjection> {
    let output = publication.outputs[0];
    let mut projections = content.runtime.input_projections().to_vec();
    let projection = projections
        .iter_mut()
        .find(|p| p.output == output.output)
        .unwrap();
    projection.frame_completed = true;
    projection.policy_visible = true;
    projection.presented_keyboard = sophia_engine::PresentedKeyboardScope::Held;
    projection.policy_publication = Some(LivePresentedPolicyPublication {
        owner_epoch: 1,
        generation: publication.generation,
        output: output.output,
        output_generation: output.generation,
        instances: publication
            .instances
            .iter()
            .filter(|i| i.output == output.output)
            .map(|i| (i.id, i.generation))
            .collect(),
        regions: publication
            .regions
            .iter()
            .filter(|r| r.output == output.output)
            .map(|r| (r.id, r.generation))
            .collect(),
    });
    projections
}

/// A supplied completed replacement frame without policy content.
fn withdrawn(content: &Content) -> Vec<LivePresentedInputProjection> {
    let mut projections = content.runtime.input_projections().to_vec();
    projections[0].frame_completed = true;
    projections[0].policy_visible = false;
    projections[0].policy_publication = None;
    projections
}

/// `service_presented_policy`'s frame-service order (revalidate, settle
/// withdrawals, observe completion) for supplied projections. That owner's
/// install branch is not used headless: without native retirement it would
/// revoke every committed publication.
fn service(run: &mut Lifecycle, projections: &[LivePresentedInputProjection]) {
    let public = run.wm.public.as_mut().unwrap();
    public.revalidate_presentation_input();
    public.settle_presented_withdrawals(projections);
    public.observe_presented_policy(projections);
}

/// The committed publication installed as the authority-production boundary
/// does with native retirement, against the supplied head.
fn install(run: &mut Lifecycle, content: &mut Content) {
    run.wm
        .install_committed_policy_presentation(
            &mut content.runtime,
            &content.scene,
            true,
            false,
            None,
            &[content.head],
        )
        .unwrap();
}

/// `Lifecycle::commit` with the presentation installed at the production
/// boundary before the owner polls the transport again, so receipts are
/// observed before they are flushed.
fn commit_installed(run: &mut Lifecycle, content: &mut Content, proposal: LiveWmProposal) -> u64 {
    let previous = run.checkpoint().1;
    let result = run.layout.commit_proposal(proposal);
    assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
    run.wm
        .apply_commit_result(result, None, run.output.id)
        .unwrap();
    install(run, content);
    previous
}

/// The remainder of `Lifecycle::commit`: transport Ready, then the peer's own
/// checkpoint replacement.
fn settle(run: &mut Lifecycle, previous: u64) {
    run.ready(false);
    let deadline = Instant::now() + Duration::from_secs(5);
    while run.checkpoint().1 == previous {
        assert!(
            Instant::now() < deadline,
            "committed checkpoint replacement deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
}

/// Physical routing and owner-loop dispatch state kept across turns.
struct Routing {
    mapper: XCoreKeyboardMapper,
    repeat: KeyRepeatState,
    keymap: XkbKeymapSnapshot,
    client_keys: SessionClientKeyState,
    emergency: EmergencyChordState,
    terminal: VirtualTerminalChordState,
    coverage: PhysicalKeyboardCoverage,
    pointer: SessionPointerPlacement,
    delivery: u64,
    coalescer: sophia_engine::RoutedInputCoalescer,
    motion: Option<Instant>,
    serial: u64,
    queue: PhysicalPolicyInputQueue,
}

impl Routing {
    fn new() -> Self {
        let mut pointer = SessionPointerPlacement::default();
        pointer.center_on_primary_output(Size {
            width: 20,
            height: 20,
        });
        Self {
            mapper: XCoreKeyboardMapper::new(),
            repeat: KeyRepeatState::new(KeyRepeatConfig::new(600, 25).unwrap()),
            keymap: XkbKeymapSnapshot::new(&sophia_x_authority::XkbRmlvoConfig::default()).unwrap(),
            client_keys: SessionClientKeyState::default(),
            emergency: EmergencyChordState::awaiting_arm(),
            terminal: VirtualTerminalChordState::default(),
            coverage: PhysicalKeyboardCoverage::default(),
            pointer,
            delivery: 1,
            coalescer: sophia_engine::RoutedInputCoalescer::new(),
            motion: None,
            serial: 0,
            queue: PhysicalPolicyInputQueue::default(),
        }
    }

    /// One production routing call, `route_input_events_with_launcher`, with
    /// the WM's real router and presented-policy state; no focused client.
    /// Returns the report and how many inputs reached application ingress.
    fn route(
        &mut self,
        run: &mut Lifecycle,
        projections: &[LivePresentedInputProjection],
        keys: &[(u32, bool)],
        now: u64,
    ) -> (PhysicalInputRouteReport, usize) {
        let events = keys
            .iter()
            .map(|&(keycode, pressed)| {
                self.serial += 1;
                InputEventPacket {
                    serial: self.serial,
                    seat: SeatId::from_raw(1),
                    device: DeviceId::from_raw(1),
                    time_msec: now,
                    kind: InputEventKind::Key { keycode, pressed },
                    global_position: Some(Point { x: 10.0, y: 10.0 }),
                    target_surface: None,
                    local_position: None,
                }
            })
            .collect();
        let (sender, receiver) = std::sync::mpsc::sync_channel(64);
        let wm = &mut run.wm;
        let public = wm.public.as_mut().unwrap();
        let protected_actions = public
            .actions
            .iter()
            .filter(|action| action.session_operation_slot.is_some())
            .map(|action| action.action)
            .collect();
        let report = route_input_events_with_launcher(
            events,
            &InputFocusState::new(),
            &[],
            &[],
            &Default::default(),
            &Default::default(),
            &sender,
            &mut self.mapper,
            &mut self.repeat,
            &self.keymap,
            &mut self.client_keys,
            &mut self.emergency,
            &mut self.terminal,
            &mut self.coverage,
            wm.shortcuts.as_mut(),
            &mut self.pointer,
            true,
            false,
            false,
            PhysicalInputRoutingMode::Full,
            &mut self.delivery,
            now,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            Some(projections[0].output),
            projections[0].epoch,
            Some(projections),
            None,
            None,
            None,
            None,
            &mut self.coalescer,
            true,
            &mut self.motion,
            Duration::ZERO,
            Some(PolicyPresentedInputRouting {
                state: &public.presentation_input,
                capture: &mut public.presentation_capture,
                protected_actions,
            }),
        )
        .unwrap();
        let ingress = receiver.try_iter().count();
        (report, ingress)
    }

    /// The owner loop's `dispatch_physical_policy_inputs` (pinned
    /// owner_loop/policy_input_phase.rs) for the three arms this case reaches;
    /// any other input is a fixture failure, not a silent drop.
    fn dispatch(&mut self, run: &mut Lifecycle, report: &PhysicalInputRouteReport) {
        let wm = &mut run.wm;
        self.queue
            .synchronize(wm.public.as_ref().map(|p| p.connection_epoch));
        if report.presentation_capacity_exceeded
            && let Some(public) = wm.public.as_mut()
        {
            public.revoke_live_presentation();
        }
        let hover_enabled = wm.pointer_focus_enabled();
        for input in report.policy_inputs.iter().copied() {
            let router = wm.shortcuts.as_mut();
            assert!(
                self.queue.admit(input, hover_enabled, router),
                "policy input queue refused {input:?}"
            );
        }
        while let Some(input) = self.queue.next(wm.pointer_focus_pending()) {
            if wm.holds_physical_inputs() {
                self.queue.hold(input);
                break;
            }
            match input {
                PhysicalPolicyInput::Chord(event) => {
                    assert!(wm.public.is_some());
                    assert_eq!(
                        wm.enqueue_chord_event(event).unwrap(),
                        LiveChordEventAdmission::Queued
                    );
                }
                PhysicalPolicyInput::ChordAction(chorded) => {
                    assert_eq!(
                        wm.admit_chord_action(
                            chorded.action,
                            chorded.chord,
                            chorded.device,
                            chorded.keycode,
                            &run.layout,
                            run.output,
                        )
                        .unwrap(),
                        LiveChordActionAdmission::Admitted
                    );
                }
                PhysicalPolicyInput::PresentedAction(action) => {
                    wm.enqueue_presented_action(action).unwrap();
                }
                other => panic!("unexpected policy input in this case: {other:?}"),
            }
        }
    }
}

fn presented_actions(
    report: &PhysicalInputRouteReport,
) -> Vec<sophia_engine::PresentedPolicyAction> {
    report
        .policy_inputs
        .iter()
        .filter_map(|input| match input {
            PhysicalPolicyInput::PresentedAction(action) => Some(*action),
            _ => None,
        })
        .collect()
}

fn staged_publication(run: &Lifecycle) -> Option<(u64, PolicyPresentation)> {
    run.wm
        .public
        .as_ref()
        .unwrap()
        .staged
        .as_ref()
        .and_then(|staged| staged.presentation_publication())
        .map(|(owner, publication)| (owner, publication.clone()))
}

fn in_flight_cause(run: &Lifecycle) -> PolicyRequestCause {
    run.wm
        .public
        .as_ref()
        .unwrap()
        .in_flight_request
        .as_ref()
        .unwrap()
        .cause
}

/// The real publication passes unmodified preflight only where its sources
/// are committed and displayed and a head covers its output.
fn preflight(run: &Lifecycle, content: &Content, owner: u64, publication: &PolicyPresentation) {
    let desired = LivePolicyPresentation {
        owner_epoch: owner,
        presentation: publication.clone(),
    };
    let sourceless = LiveProductionVisualRuntime::new(&[run.output], None).unwrap();
    assert!(
        matches!(
            sourceless.validate_policy_presentation_on_heads(&desired, &[content.head]),
            Err(LivePolicyPresentationRefusal::MissingSource { source }) if SURFACES.contains(&source)
        ),
        "a runtime without the CPU sources refuses the real publication"
    );
    assert!(
        matches!(
            content
                .runtime
                .validate_policy_presentation_on_heads(&desired, &[]),
            Err(LivePolicyPresentationRefusal::MissingHeads { .. })
        ),
        "no head refuses the real publication"
    );
    assert!(
        content
            .runtime
            .validate_policy_presentation_on_heads(&desired, &[content.head])
            .is_ok()
    );
    assert!(
        run.wm
            .preflight_staged_presentation_on_heads(Some(&content.runtime), &[content.head]),
        "the unmodified real publication passes production preflight"
    );
}

/// State after the shared prefix: Alt+Tab opened a followed chord and real
/// Hagia's Held publication is installed and settled, with no completed frame,
/// receipt, captured key or release debt yet.
struct Held {
    run: Lifecycle,
    content: Content,
    routing: Routing,
    idle: Vec<LivePresentedInputProjection>,
    first: PolicyPresentation,
    next: WmActionId,
    /// Checkpoint windows in the documented candidate order.
    candidates: Vec<u64>,
    /// Their surfaces: W1 (the settled focus), W2, W3.
    expected: Vec<SurfaceId>,
}

fn held(case: &str) -> Held {
    let mut run = Lifecycle::native_ceiling(case, DESKTOP);
    let profile =
        std::fs::read(run.source.config.desktop_profile_source.as_ref().unwrap()).unwrap();
    assert_eq!(profile, DESKTOP.as_bytes());
    log(
        &run,
        &format!(
            "native_ceiling=selected_without_device presentation_completion=supplied surface_content=supplied_cpu_intake heads=supplied router_time=supplied admission_visual_readiness=bypassed profile_sha256={:x}",
            sha2::Sha256::digest(&profile)
        ),
    );
    let next = action_id(&run, "recent-window-next");
    // Lifecycle interest is Hagia's own configuration, not the fixture's.
    let public = run.wm.public.as_ref().unwrap();
    assert!(
        public
            .accepted_configuration
            .as_ref()
            .unwrap()
            .action_lifecycles
            .iter()
            .any(|interest| interest.action == next && interest.held_ms == 150)
    );

    populate(&mut run);
    let mut content = commit_cpu_sources(&run);

    // Expected selection from the checkpoint and Hagia's documented rule:
    // candidates are recent focus (only the settled focus, never changed
    // here) then window order; the opener selects one past the focus and a
    // captured Right one more. recentFocus itself is not checkpointed.
    let checkpoint = model(&run);
    let focused = checkpoint["outputs"][0]["focusedWindow"].as_u64().unwrap();
    let mut candidates = vec![focused];
    for window in checkpoint["windowOrder"].as_array().unwrap() {
        let window = window.as_u64().unwrap();
        if window != focused {
            candidates.push(window);
        }
    }
    assert_eq!(candidates.len(), 3);
    let surface_of = |window: u64| -> SurfaceId {
        let key = checkpoint["surfaces"]
            .as_array()
            .unwrap()
            .iter()
            .find(|s| s["window"].as_u64() == Some(window))
            .unwrap()["key"]
            .as_u64()
            .unwrap();
        *SURFACES.iter().find(|s| key_of(**s) == key).unwrap()
    };
    let expected = candidates
        .iter()
        .map(|w| surface_of(*w))
        .collect::<Vec<_>>();
    let (w1, w2, w3) = (expected[0], expected[1], expected[2]);
    assert_eq!(focus(&run), Some(w1));
    // Positive commits W3; no completion leaves W2; an ignored Ended, W1.
    assert!(w1 != w2 && w2 != w3 && w1 != w3);
    log(
        &run,
        &format!("phase=expected w1={w1:?} w2={w2:?} w3={w3:?}"),
    );

    // Alt+Tab opens a chord the WM follows; its activation is a ChordAction.
    let mut routing = Routing::new();
    let idle = content.runtime.input_projections().to_vec();
    let (report, _) = routing.route(&mut run, &idle, &[(ALT, true), (TAB, true)], 1000);
    assert!(
        matches!(
            report.policy_inputs[..],
            [PhysicalPolicyInput::ChordAction(chorded)] if chorded.action == next && chorded.chord.opens
        ),
        "{:?}",
        report.policy_inputs
    );
    routing.dispatch(&mut run, &report);
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);
    assert_eq!(run.wm.chord_ledger.len(), 1);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::ChordAction { activation_serial, chord_serial, action }
            if activation_serial == chord_serial && action == next
    ));
    assert!(staged_publication(&run).is_none(), "hidden until Held");
    run.commit(proposal);
    let (report, _) = routing.route(&mut run, &idle, &[(TAB, false)], 1010);
    assert!(report.policy_inputs.is_empty());

    // Held falls due by the supplied router clock, through the per-turn service.
    let mut report = PhysicalInputRouteReport::default();
    report.policy_inputs.extend(
        run.wm
            .service_shortcuts(1150)
            .into_iter()
            .map(PhysicalPolicyInput::from_shortcut),
    );
    assert!(
        matches!(
            report.policy_inputs[..],
            [PhysicalPolicyInput::Chord(
                sophia_engine::WmChordEvent::Held { .. }
            )]
        ),
        "{:?}",
        report.policy_inputs
    );
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::ActionLifecycle {
            phase: PolicyChordPhase::Held,
            ..
        }
    ));
    let (owner, first) = staged_publication(&run).expect("Held draws the switcher");
    assert_eq!(owner, 1);
    let output = first.outputs[0];
    assert_eq!(first.outputs.len(), 1);
    assert_eq!(output.mode, PolicyPresentationMode::Overlay);
    assert_eq!(first.keyboard_output, Some(output.output));
    assert!(
        first
            .bindings
            .iter()
            .any(|b| b.keycode == RIGHT && b.action == next)
    );
    let mut previews = first.instances.clone();
    previews.sort_by_key(|instance| instance.z_index);
    assert_eq!(
        previews.iter().map(|i| i.source).collect::<Vec<_>>(),
        expected,
        "held preview order follows the documented candidate rule"
    );
    preflight(&run, &content, owner, &first);
    let previous = commit_installed(&mut run, &mut content, proposal);
    settle(&mut run, previous);
    {
        let public = run.wm.public.as_ref().unwrap();
        assert_eq!(public.presentation_input.publication(), Some((1, &first)));
        assert!(public.presentation_input.held_capture());
        assert!(
            public
                .presentation_input
                .output_receipt(output.output)
                .is_none(),
            "installation alone is not presentation"
        );
        assert!(!public.presentation_input.modal_ready(false));
        assert!(public.presentation_receipts.is_empty());
    }
    Held {
        run,
        content,
        routing,
        idle,
        first,
        next,
        candidates,
        expected,
    }
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_presented_chord_switcher() {
    let Held {
        mut run,
        mut content,
        mut routing,
        idle,
        first,
        next,
        candidates,
        expected,
    } = held("presented-chord");
    let output = first.outputs[0];
    let w3 = expected[2];
    // Without a completed frame the capture is not actionable: Right reaches
    // client routing (no focus) and nothing is owed.
    let (report, ingress) = routing.route(&mut run, &idle, &[(RIGHT, true), (RIGHT, false)], 1200);
    assert!(
        report.policy_inputs.is_empty(),
        "{:?}",
        report.policy_inputs
    );
    assert_eq!(report.keys_suppressed_no_focus, 2);
    assert_eq!(ingress, 0);
    assert!(!owes(&run, RIGHT));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);

    // Supplied completion, then the captured key.
    let presented = completed(&content, &first);
    service(&mut run, &presented);
    let (report, ingress) = routing.route(&mut run, &presented, &[(RIGHT, true)], 1300);
    let actions = presented_actions(&report);
    assert!(
        matches!(actions[..], [action] if action.action == next),
        "presented switcher must take the captured key: {:?}",
        report.policy_inputs
    );
    let captured = actions[0];
    assert_eq!(ingress, 0);
    assert_eq!(report.keys_suppressed_no_focus, 0);
    assert!(owes(&run, RIGHT), "the captured press is owed its release");
    let receipt = {
        let public = run.wm.public.as_ref().unwrap();
        assert!(public.presentation_input.modal_ready(false));
        public
            .presentation_input
            .output_receipt(output.output)
            .unwrap()
    };
    assert_eq!(
        receipt,
        PolicyPresentationReceipt {
            connection_epoch: 1,
            publication_generation: first.generation,
            output: output.output,
            output_generation: output.generation,
            presentation_epoch: receipt.presentation_epoch,
            outcome: PolicyPresentationOutcome::Presented,
        }
    );
    assert_eq!(receipts(&run), vec![receipt]);
    service(&mut run, &presented);
    assert_eq!(
        receipts(&run),
        vec![receipt],
        "one Presented per completion"
    );
    assert_eq!(captured.connection_epoch, 1);
    assert_eq!(
        captured.identity,
        PolicyPresentationIdentity {
            publication_generation: first.generation,
            output: output.output,
            output_generation: output.generation,
            presentation_epoch: receipt.presentation_epoch,
            target_id: 0,
            target_generation: 0,
        }
    );
    routing.dispatch(&mut run, &report);
    let (report, ingress) = routing.route(&mut run, &presented, &[(RIGHT, false)], 1310);
    assert!(report.policy_inputs.is_empty());
    assert_eq!((ingress, report.keys_suppressed_no_focus), (0, 0));
    assert!(!owes(&run, RIGHT), "the release settles the debt");
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);

    // Receipts leave before the action's cycle is admitted.
    drain(&mut run);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::PresentationAction { action, identity, .. }
            if action == next && identity == captured.identity
    ));
    let (owner, second) = staged_publication(&run).expect("the switcher stays drawn");
    assert!(second.generation > first.generation);
    preflight(&run, &content, owner, &second);
    let previous = commit_installed(&mut run, &mut content, proposal);
    let revoked = PolicyPresentationReceipt {
        outcome: PolicyPresentationOutcome::Revoked,
        ..receipt
    };
    assert_eq!(receipts(&run), vec![revoked]);
    settle(&mut run, previous);
    drain(&mut run);
    let queued = run.wm.public.as_ref().unwrap().queue.len();
    run.wm.enqueue_presented_action(captured).unwrap();
    assert_eq!(
        run.wm.public.as_ref().unwrap().queue.len(),
        queued,
        "the republished switcher rejects the old identity"
    );
    let presented = completed(&content, &second);
    service(&mut run, &presented);
    let second_receipt = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .presentation_input
        .output_receipt(output.output)
        .unwrap();
    assert!(second_receipt.presentation_epoch > receipt.presentation_epoch);
    assert_eq!(second_receipt.publication_generation, second.generation);
    // Revoked(first) already left; its Withdrawn and the new Presented follow.
    assert_eq!(
        receipts(&run),
        vec![
            PolicyPresentationReceipt {
                outcome: PolicyPresentationOutcome::Withdrawn,
                ..receipt
            },
            second_receipt
        ]
    );
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS - 1);
    assert_eq!(run.wm.chord_ledger.len(), 1);
    drain(&mut run);

    // Alt's release ends the chord; its Ended cycle returns the credit.
    let (report, ingress) = routing.route(&mut run, &presented, &[(ALT, false)], 1400);
    assert!(
        matches!(
            report.policy_inputs[..],
            [PhysicalPolicyInput::Chord(
                sophia_engine::WmChordEvent::Ended {
                    end: PolicyChordEnd::Released,
                    ..
                }
            )]
        ),
        "{:?}",
        report.policy_inputs
    );
    assert_eq!(ingress, 0);
    routing.dispatch(&mut run, &report);
    let proposal = run.proposal();
    assert!(matches!(
        in_flight_cause(&run),
        PolicyRequestCause::ActionLifecycle {
            phase: PolicyChordPhase::Ended(PolicyChordEnd::Released),
            ..
        }
    ));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    assert!(run.wm.chord_ledger.is_empty());
    assert_eq!(
        proposal.focus,
        Some(w3),
        "released chord must commit the switcher selection"
    );
    assert!(staged_publication(&run).is_none(), "the switcher closes");
    let previous = commit_installed(&mut run, &mut content, proposal);
    let closed = PolicyPresentationReceipt {
        outcome: PolicyPresentationOutcome::Revoked,
        ..second_receipt
    };
    assert_eq!(receipts(&run), vec![closed]);
    service(&mut run, &withdrawn(&content));
    assert_eq!(
        receipts(&run),
        vec![
            closed,
            PolicyPresentationReceipt {
                outcome: PolicyPresentationOutcome::Withdrawn,
                ..second_receipt
            }
        ]
    );
    settle(&mut run, previous);
    drain(&mut run);
    assert_eq!(focus(&run), Some(w3));
    assert_eq!(
        model(&run)["outputs"][0]["focusedWindow"].as_u64(),
        Some(candidates[2])
    );
    assert!(!owes(&run, RIGHT));
    assert_eq!(credits(&run), sophia_engine::WM_CHORD_CREDITS);
    log(
        &run,
        &format!("phase=committed focus={w3:?} presented={receipt:?} second={second_receipt:?}"),
    );
    run.record("presented-committed");
    run.stop();
}
