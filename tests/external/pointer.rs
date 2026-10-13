//! Production interaction admission and routing with supplied input and completion.
//! The bounded ledger is an accounting diagnostic, not a latency campaign.
use super::*;
use serde_json::json;
use sophia_protocol::PolicyInteractionPhase as Phase;
use sophia_protocol::WmPointerGestureMode as Mode;

#[derive(Clone, Debug)]
enum Disposition {
    Replaced(usize),
    Cancelled(usize),
    Committed(u64),
}

#[derive(Clone)]
struct Offer {
    mode: Mode,
    phase: Phase,
    geometry: Rect,
    enqueued_ns: u64,
    request: Option<(u64, u64, u64)>,
    disposition: Option<Disposition>,
}

struct Accounting {
    start: Instant,
    offers: Vec<Offer>,
}

fn rect(x: i32, width: i32) -> Rect {
    Rect {
        x,
        y: 80,
        width,
        height: 200,
    }
}

// The fixture's negotiated chrome has one pixel of clearance. Hagia keeps
// outer geometry; Session commits the corresponding content rectangle.
fn content(outer: Rect) -> Rect {
    Rect {
        x: outer.x + 1,
        y: outer.y + 1,
        width: outer.width - 2,
        height: outer.height - 2,
    }
}

fn outer(content: Rect) -> Rect {
    Rect {
        x: content.x - 1,
        y: content.y - 1,
        width: content.width + 2,
        height: content.height + 2,
    }
}

fn kind(mode: Mode) -> PolicyInteractionKind {
    match mode {
        Mode::Move => PolicyInteractionKind::Move,
        Mode::Resize => PolicyInteractionKind::Resize,
    }
}

impl Accounting {
    fn new() -> Self {
        Self {
            start: Instant::now(),
            offers: Vec::new(),
        }
    }

    fn ns(&self) -> u64 {
        self.start.elapsed().as_nanos().try_into().unwrap()
    }

    fn offer(&mut self, run: &mut Lifecycle, mode: Mode, phase: Phase, geometry: Rect) -> usize {
        self.routed_offer(
            run,
            crate::live_session::FloatingPointerPolicyInteraction {
                surface: SURFACES[0],
                mode,
                phase,
                geometry: content(geometry),
                start: WmPointerPosition { x: 100, y: 100 },
                current: WmPointerPosition {
                    x: geometry.x,
                    y: geometry.y,
                },
            },
            geometry,
        )
    }

    fn routed_offer(
        &mut self,
        run: &mut Lifecycle,
        interaction: crate::live_session::FloatingPointerPolicyInteraction,
        geometry: Rect,
    ) -> usize {
        assert_eq!(interaction.surface, SURFACES[0], "exact routed target");
        let (mode, phase) = (interaction.mode, interaction.phase);
        assert!(self.offers.len() < 32, "bounded interaction diagnostic");
        let id = self.offers.len();
        let pending = self
            .offers
            .iter()
            .enumerate()
            .filter_map(|(i, o)| {
                (o.mode == mode && o.request.is_none() && o.disposition.is_none()).then_some(i)
            })
            .collect::<Vec<_>>();
        let replaced = pending
            .iter()
            .copied()
            .find(|i| self.offers[*i].phase == Phase::Update);
        if phase == Phase::Update
            && let Some(old) = replaced
        {
            assert_ne!(
                geometry, self.offers[old].geometry,
                "distinct replacement is observable"
            );
            assert!(run.wm.public.as_ref().unwrap().queue.iter().any(|c| matches!(
                c.cause, PolicyRequestCause::Interaction { phase: Phase::Update, geometry: g, .. }
                if g == self.offers[old].geometry
            )));
        }
        let enqueued_ns = self.ns();
        let admission = run
            .wm
            .enqueue_pointer_interaction(interaction, &run.layout)
            .unwrap();
        let replacement = phase == Phase::Update && replaced.is_some();
        assert_eq!(
            admission,
            if replacement {
                LiveWmRequestAdmission::Duplicate
            } else {
                LiveWmRequestAdmission::Admitted
            },
            "interaction offer admission"
        );
        if phase == Phase::Update {
            let queued = run
                .wm
                .public
                .as_ref()
                .unwrap()
                .queue
                .iter()
                .filter_map(|c| match c.cause {
                    PolicyRequestCause::Interaction {
                        phase: Phase::Update,
                        kind: k,
                        target,
                        geometry,
                        ..
                    } if k == kind(mode) && target == SURFACES[0] => Some(geometry),
                    _ => None,
                })
                .collect::<Vec<_>>();
            assert_eq!(
                queued,
                vec![geometry],
                "queued pointer update must retain the latest offered geometry"
            );
        }
        if phase == Phase::Cancel {
            let queue = &run.wm.public.as_ref().unwrap().queue;
            assert!(matches!(
                queue.front().map(|c| &c.cause),
                Some(PolicyRequestCause::Interaction {
                    phase: Phase::Cancel,
                    ..
                })
            ));
            assert!(!queue.iter().any(|c| matches!(c.cause,
                PolicyRequestCause::Interaction { phase: Phase::Begin | Phase::Update | Phase::End, target, kind: k, .. }
                    if target == SURFACES[0] && k == kind(mode)
            )), "pointer cancel must remove obsolete queued interaction work");
            for old in pending {
                self.offers[old].disposition = Some(Disposition::Cancelled(id));
            }
        } else if replacement {
            self.offers[replaced.unwrap()].disposition = Some(Disposition::Replaced(id));
        }
        self.offers.push(Offer {
            mode,
            phase,
            geometry,
            enqueued_ns,
            request: None,
            disposition: None,
        });
        id
    }

    fn proposal(&mut self, run: &mut Lifecycle, id: usize, expected: Rect) -> LiveWmProposal {
        let proposal = run.proposal();
        assert_eq!(run.wm.candidate_chrome_style().clearance(), 1);
        let offer = &mut self.offers[id];
        assert!(offer.request.is_none() && offer.disposition.is_none());
        let request = run
            .wm
            .public
            .as_ref()
            .unwrap()
            .in_flight_request
            .as_ref()
            .unwrap();
        assert!(
            matches!(request.cause, PolicyRequestCause::Interaction {
            phase, kind: k, target, geometry, ..
        } if phase == offer.phase && k == kind(offer.mode) && target == SURFACES[0] && geometry == offer.geometry),
            "peer answer must correlate to the surviving pointer offer"
        );
        let identity = proposal.policy_settlement.unwrap();
        offer.request = Some((
            identity.connection_epoch,
            identity.request_id,
            identity.transaction.raw(),
        ));
        assert_eq!(
            proposal
                .layers
                .iter()
                .find(|l| l.surface == SURFACES[0])
                .unwrap()
                .geometry,
            content(expected),
            "pointer proposal must carry the expected committed geometry"
        );
        proposal
    }

    fn commit(&mut self, run: &mut Lifecycle, id: usize, proposal: LiveWmProposal, expected: Rect) {
        run.commit(proposal); // Supplied layout completion, never application ACKs.
        assert!(self.offers[id].disposition.is_none());
        self.offers[id].disposition = Some(Disposition::Committed(self.ns()));
        assert_eq!(run.layout.layers[&SURFACES[0]].geometry, content(expected));
        let checkpoint = model(run);
        let key = (u64::from(SURFACES[0].generation()) << 32) | u64::from(SURFACES[0].index());
        let window = &checkpoint["surfaces"]
            .as_array()
            .unwrap()
            .iter()
            .find(|s| s["key"].as_u64() == Some(key))
            .unwrap()["window"];
        let saved = checkpoint["windows"]
            .as_array()
            .unwrap()
            .iter()
            .find(|w| &w["id"] == window)
            .unwrap();
        assert_eq!(
            saved["floatingGeometry"],
            json!({"x":expected.x,"y":expected.y,"width":expected.width,"height":expected.height}),
            "pointer settlement and Hagia checkpoint must agree"
        );
    }

    fn valid(offers: &[Offer]) -> bool {
        let mut requests = std::collections::BTreeSet::new();
        offers
            .iter()
            .enumerate()
            .all(|(id, o)| match o.disposition {
                Some(Disposition::Committed(at)) => {
                    at >= o.enqueued_ns && o.request.is_some_and(|r| requests.insert(r))
                }
                Some(Disposition::Replaced(next)) => {
                    o.request.is_none()
                        && next > id
                        && o.phase == Phase::Update
                        && offers.get(next).is_some_and(|n| {
                            n.phase == Phase::Update
                                && n.mode == o.mode
                                && n.geometry != o.geometry
                                && n.enqueued_ns >= o.enqueued_ns
                        })
                }
                Some(Disposition::Cancelled(next)) => {
                    o.request.is_none()
                        && next > id
                        && offers.get(next).is_some_and(|n| {
                            n.phase == Phase::Cancel
                                && n.mode == o.mode
                                && n.enqueued_ns >= o.enqueued_ns
                        })
                }
                None => false,
            })
    }

    fn finish(&self, run: &Lifecycle) {
        assert!(
            Self::valid(&self.offers),
            "every pointer offer must have one correlated disposition"
        );
        let mut missing = self.offers.clone();
        let edge = missing
            .iter_mut()
            .find(|o| {
                matches!(
                    o.disposition,
                    Some(Disposition::Replaced(_) | Disposition::Cancelled(_))
                )
            })
            .unwrap();
        edge.disposition = None;
        assert!(
            !Self::valid(&missing),
            "accounting must refuse a missing replacement or cancellation edge"
        );
        let rows = self
            .offers
            .iter()
            .enumerate()
            .map(|(id, o)| {
                let (outcome, successor, settled_ns) = match o.disposition.as_ref().unwrap() {
                    Disposition::Replaced(next) => ("replaced", Some(*next), None),
                    Disposition::Cancelled(next) => ("cancelled_by", Some(*next), None),
                    Disposition::Committed(at) => ("committed", None, Some(*at)),
                };
                json!({"offer":id,"surface":[SURFACES[0].index(),SURFACES[0].generation()],
                "mode":format!("{:?}",o.mode),"phase":format!("{:?}",o.phase),
                "geometry":[o.geometry.x,o.geometry.y,o.geometry.width,o.geometry.height],
                "enqueued_ns":o.enqueued_ns,"request_epoch_id_transaction":o.request,
                "outcome":outcome,"successor":successor,"settled_observed_ns":settled_ns})
            })
            .collect::<Vec<_>>();
        std::fs::write(run.evidence.join("pointer-accounting.json"), serde_json::to_vec_pretty(&json!({
            "schema":1,"mode":"bounded_diagnostic_no_latency_claim","scheduled_input":"fixture_driven",
            "all_offers_accepted":true,"unresolved":0,"offers":rows
        })).unwrap()).unwrap();
    }
}

fn healthy(run: &mut Lifecycle) {
    assert!(
        run.wm
            .poll_public_request(&mut run.layout, run.output, false)
            .unwrap()
            .is_none()
    );
    let p = run.wm.public.as_ref().unwrap();
    assert!(
        !run.wm.degraded
            && !run.wm.force_transport_restart
            && !p.transport_unavailable
            && p.connection_epoch == 1
            && p.in_flight_request.is_none()
            && p.queue.is_empty(),
        "peer healthy and pointer queue empty before teardown"
    );
    assert!(run.wm.supervisor.poll().unwrap().is_none());
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_pointer_updates_coalesce_and_settle() {
    let mut run = Lifecycle::new("pointer-coalescing");
    populate(&mut run);
    let mut ledger = Accounting::new();
    for (mode, geometries) in [
        (
            Mode::Move,
            [
                rect(100, 300),
                rect(140, 300),
                rect(180, 300),
                rect(220, 300),
            ],
        ),
        (
            Mode::Resize,
            [
                rect(220, 320),
                rect(220, 360),
                rect(220, 400),
                rect(220, 440),
            ],
        ),
    ] {
        let begin = ledger.offer(&mut run, mode, Phase::Begin, geometries[0]);
        let proposal = ledger.proposal(&mut run, begin, geometries[0]);
        let checkpoint = run.checkpoint();
        let before = run.layout.layers.clone();
        ledger.offer(&mut run, mode, Phase::Update, geometries[1]);
        let latest = ledger.offer(&mut run, mode, Phase::Update, geometries[2]);
        let end = ledger.offer(&mut run, mode, Phase::End, geometries[3]);
        assert_eq!(run.wm.public.as_ref().unwrap().queue.len(), 2);
        assert_eq!(
            run.layout.layers, before,
            "queued motion cannot publish geometry"
        );
        assert_eq!(
            run.checkpoint(),
            checkpoint,
            "queued motion cannot save a candidate"
        );
        ledger.commit(&mut run, begin, proposal, geometries[0]);
        let proposal = ledger.proposal(&mut run, latest, geometries[2]);
        ledger.commit(&mut run, latest, proposal, geometries[2]);
        let proposal = ledger.proposal(&mut run, end, geometries[3]);
        ledger.commit(&mut run, end, proposal, geometries[3]);
    }
    ledger.finish(&run);
    healthy(&mut run);
    run.record("pointer-move-resize-settled");
    run.stop();
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_pointer_cancel_purges_queued_work() {
    let mut run = Lifecycle::new("pointer-cancel");
    populate(&mut run);
    let mut ledger = Accounting::new();
    let committed = rect(100, 300);
    let begin = ledger.offer(&mut run, Mode::Move, Phase::Begin, committed);
    let proposal = ledger.proposal(&mut run, begin, committed);
    run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
    ledger.offer(&mut run, Mode::Move, Phase::Update, rect(180, 300));
    ledger.offer(&mut run, Mode::Move, Phase::End, rect(220, 300));
    let cancel = ledger.offer(&mut run, Mode::Move, Phase::Cancel, rect(260, 300));
    let queue = &run.wm.public.as_ref().unwrap().queue;
    assert_eq!(queue.len(), 2, "cancel preserves unrelated work");
    assert!(matches!(
        queue.back().unwrap().cause,
        PolicyRequestCause::SceneChanged
    ));
    ledger.commit(&mut run, begin, proposal, committed);
    let proposal = ledger.proposal(&mut run, cancel, committed);
    ledger.commit(&mut run, cancel, proposal, committed);
    let unrelated = run.proposal();
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
    run.commit(unrelated);
    assert_eq!(
        run.layout.layers[&SURFACES[0]].geometry,
        content(committed),
        "cancel cannot apply a queued end or undo a committed begin"
    );
    for (phase, geometry) in [(Phase::Begin, rect(140, 300)), (Phase::End, rect(180, 300))] {
        let id = ledger.offer(&mut run, Mode::Move, phase, geometry);
        let proposal = ledger.proposal(&mut run, id, geometry);
        ledger.commit(&mut run, id, proposal, geometry);
    }
    ledger.finish(&run);
    healthy(&mut run);
    run.record("pointer-cancel-fresh-interaction");
    run.stop();
}

pub(super) struct PointerRouting {
    pub(super) target: SurfaceId,
    mapper: XCoreKeyboardMapper,
    repeat: KeyRepeatState,
    keymap: XkbKeymapSnapshot,
    client_keys: SessionClientKeyState,
    emergency: EmergencyChordState,
    terminal: VirtualTerminalChordState,
    coverage: PhysicalKeyboardCoverage,
    pointer: SessionPointerPlacement,
    gesture: FloatingPointerGestureState,
    delivery: u64,
    serial: u64,
    coalescer: sophia_engine::RoutedInputCoalescer,
    motion: Option<Instant>,
}

impl PointerRouting {
    pub(super) fn new(output: sophia_engine::HeadlessOutput) -> Self {
        // Supplied event positions are already logical, unlike libinput's
        // accumulated coordinates. Keep confinement but use a zero offset.
        let mut pointer = SessionPointerPlacement::with_raw_to_logical_offset(Point::default());
        pointer.set_output_bounds(vec![Rect {
            x: 0,
            y: 0,
            width: output.size.width,
            height: output.size.height,
        }]);
        Self {
            target: SURFACES[0],
            mapper: XCoreKeyboardMapper::new(),
            repeat: KeyRepeatState::new(KeyRepeatConfig::new(600, 25).unwrap()),
            keymap: XkbKeymapSnapshot::new(&sophia_x_authority::XkbRmlvoConfig::default()).unwrap(),
            client_keys: SessionClientKeyState::default(),
            emergency: EmergencyChordState::awaiting_arm(),
            terminal: VirtualTerminalChordState::default(),
            coverage: PhysicalKeyboardCoverage::default(),
            pointer,
            gesture: FloatingPointerGestureState::default(),
            delivery: 1,
            serial: 0,
            coalescer: sophia_engine::RoutedInputCoalescer::new(),
            motion: None,
        }
    }

    // One supplied visible layer, taken from committed Session geometry.
    // Its opaque CPU handle supplies renderability; no pixel import is claimed.
    // Actual hit testing and modifier/gesture reduction run below; this is
    // not backend-produced presentation or frontend delivery evidence.
    pub(super) fn route(
        &mut self,
        run: &mut Lifecycle,
        kind: InputEventKind,
        point: Point,
    ) -> PhysicalInputRouteReport {
        self.serial += 1;
        let events = vec![InputEventPacket {
            serial: self.serial,
            seat: SeatId::from_raw(1),
            device: DeviceId::from_raw(1),
            time_msec: self.serial,
            kind,
            global_position: Some(point),
            target_surface: None,
            local_position: None,
        }];
        let mut layer = run.layout.layers[&self.target].clone();
        layer.source = BufferSource::CpuBuffer { handle: 901 };
        let layers = [layer];
        if matches!(
            kind,
            InputEventKind::PointerButton {
                button: 0x110 | 0x111,
                pressed: true
            }
        ) {
            assert_eq!(
                sophia_engine::hit_test_scene_surface_for_input(&events[0], &layers).target_surface,
                Some(self.target),
                "supplied visible scene contains the intended pointer target"
            );
        }
        let (sender, _receiver) = std::sync::mpsc::sync_channel(64);
        route_input_events_with_launcher(
            events,
            &InputFocusState::new(),
            &[],
            &layers,
            &run.layout.presentation_roles,
            &run.layout.client_routes,
            &sender,
            &mut self.mapper,
            &mut self.repeat,
            &self.keymap,
            &mut self.client_keys,
            &mut self.emergency,
            &mut self.terminal,
            &mut self.coverage,
            run.wm.shortcuts.as_mut(),
            &mut self.pointer,
            true,
            false,
            false,
            PhysicalInputRoutingMode::Full,
            &mut self.delivery,
            self.serial,
            None,
            None,
            None,
            None,
            Some(&mut self.gesture),
            None,
            None,
            None,
            None,
            None,
            Some(run.output.id),
            1,
            None,
            None,
            None,
            None,
            None,
            &mut self.coalescer,
            true,
            &mut self.motion,
            Duration::ZERO,
            None,
        )
        .unwrap()
    }

    fn interaction(
        &mut self,
        run: &mut Lifecycle,
        kind: InputEventKind,
        point: Point,
        mode: Mode,
        phase: Phase,
        expected: Rect,
    ) -> FloatingPointerPolicyInteraction {
        let report = self.route(run, kind, point);
        assert_eq!(
            report.wm_pointer_interactions.len(),
            1,
            "bound routed input produces one interaction"
        );
        let interaction = report.wm_pointer_interactions[0];
        assert_eq!(
            (
                interaction.surface,
                interaction.mode,
                interaction.phase,
                interaction.geometry
            ),
            (SURFACES[0], mode, phase, expected),
            "routing preserves exact target, mode, phase and geometry"
        );
        assert_eq!(
            report.wm_pointer_gestures.len(),
            usize::from(phase == Phase::End)
        );
        interaction
    }
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_pointer_routing_selects_exact_interactions() {
    let mut run = Lifecycle::new("pointer-routing");
    populate(&mut run);
    let mut ledger = Accounting::new();
    // Establish a floating target away from output edges through real policy.
    let setup = rect(100, 300);
    for phase in [Phase::Begin, Phase::End] {
        let id = ledger.offer(&mut run, Mode::Move, phase, setup);
        let proposal = ledger.proposal(&mut run, id, setup);
        ledger.commit(&mut run, id, proposal, setup);
    }
    let mut routing = PointerRouting::new(run.output);
    let button = |button, pressed| InputEventKind::PointerButton { button, pressed };
    for (mode, code, cancel) in [
        (Mode::Move, 0x110, false),
        (Mode::Resize, 0x111, false),
        (Mode::Move, 0x110, true),
        (Mode::Resize, 0x111, true),
    ] {
        let initial = run.layout.layers[&SURFACES[0]].geometry;
        let start = Point {
            x: f64::from(initial.x + 20),
            y: f64::from(initial.y + 20),
        };
        let checkpoint = run.checkpoint();
        for pressed in [true, false] {
            let report = routing.route(&mut run, button(code, pressed), start);
            assert!(
                report.wm_pointer_interactions.is_empty(),
                "without Super no policy gesture starts"
            );
        }
        routing.route(
            &mut run,
            InputEventKind::Key {
                keycode: 125,
                pressed: true,
            },
            start,
        );
        for pressed in [true, false] {
            let report = routing.route(&mut run, button(0x112, pressed), start);
            assert!(
                report.wm_pointer_interactions.is_empty(),
                "unbound middle button cannot start a policy gesture"
            );
        }
        assert_eq!(run.checkpoint(), checkpoint);
        assert!(
            !run.wm
                .shortcuts
                .as_ref()
                .unwrap()
                .seat_uncertain(SeatId::from_raw(1))
        );
        assert_ne!(
            run.wm
                .shortcuts
                .as_ref()
                .unwrap()
                .modifier_mask(SeatId::from_raw(1))
                .bits
                & WmModifierMask::SUPER,
            0,
            "routed Super press is held before gesture admission"
        );
        let interaction = routing.interaction(
            &mut run,
            button(code, true),
            start,
            mode,
            Phase::Begin,
            initial,
        );
        let begin = ledger.routed_offer(&mut run, interaction, outer(initial));
        let proposal = ledger.proposal(&mut run, begin, outer(initial));
        assert_eq!(
            proposal
                .layers
                .iter()
                .find(|layer| layer.surface == SURFACES[0])
                .unwrap()
                .geometry,
            initial,
            "a routed Begin without motion must preserve committed content geometry"
        );
        let geometry = |delta| match mode {
            Mode::Move => Rect {
                x: initial.x + delta,
                ..initial
            },
            Mode::Resize => Rect {
                width: initial.width + delta,
                ..initial
            },
        };
        let mut latest = None;
        for delta in [10, 20] {
            let point = Point {
                x: start.x + f64::from(delta),
                ..start
            };
            let interaction = routing.interaction(
                &mut run,
                InputEventKind::PointerMotion,
                point,
                mode,
                Phase::Update,
                geometry(delta),
            );
            latest = Some(ledger.routed_offer(&mut run, interaction, outer(geometry(delta))));
        }
        let point = Point {
            x: start.x + 30.0,
            ..start
        };
        let wrong_release = routing.route(&mut run, button(0x112, false), point);
        assert!(
            wrong_release.wm_pointer_interactions.is_empty(),
            "wrong-button release cannot end the captured gesture"
        );
        assert!(routing.gesture.active());
        if cancel {
            // Supply a security-revocation trigger at the same owner boundary
            // as revoke_floating_pointer_interaction. The actual grab owner
            // produces Cancel from routed state; this is not a lock/seat test.
            let interaction = routing.gesture.cancel().expect("routed grab is active");
            assert_eq!(interaction.phase, Phase::Cancel);
            assert_eq!((interaction.surface, interaction.mode), (SURFACES[0], mode));
            assert_eq!(interaction.geometry, geometry(30));
            assert!(
                !routing.gesture.active(),
                "security cancellation must clear the routed gesture"
            );
            assert!(
                routing.gesture.cancel().is_none(),
                "cancellation cannot replay"
            );
            let cancelled = ledger.routed_offer(&mut run, interaction, outer(geometry(30)));
            ledger.commit(&mut run, begin, proposal, outer(initial));
            let proposal = ledger.proposal(&mut run, cancelled, outer(initial));
            ledger.commit(&mut run, cancelled, proposal, outer(initial));
            let released = routing.route(&mut run, button(code, false), point);
            assert!(
                released.wm_pointer_interactions.is_empty(),
                "a cancelled grab cannot emit End on release"
            );
            routing.route(
                &mut run,
                InputEventKind::Key {
                    keycode: 125,
                    pressed: false,
                },
                point,
            );
            continue;
        }
        let interaction = routing.interaction(
            &mut run,
            button(code, false),
            point,
            mode,
            Phase::End,
            geometry(30),
        );
        let end = ledger.routed_offer(&mut run, interaction, outer(geometry(30)));
        assert!(!routing.gesture.active());
        assert_eq!(
            run.checkpoint(),
            checkpoint,
            "routed pending motion cannot save policy state"
        );
        ledger.commit(&mut run, begin, proposal, outer(initial));
        let proposal = ledger.proposal(&mut run, latest.unwrap(), outer(geometry(20)));
        ledger.commit(&mut run, latest.unwrap(), proposal, outer(geometry(20)));
        let proposal = ledger.proposal(&mut run, end, outer(geometry(30)));
        ledger.commit(&mut run, end, proposal, outer(geometry(30)));
        let duplicate = routing.route(&mut run, button(code, false), point);
        assert!(
            duplicate.wm_pointer_interactions.is_empty(),
            "duplicate release cannot replay the ended gesture"
        );
        routing.route(
            &mut run,
            InputEventKind::Key {
                keycode: 125,
                pressed: false,
            },
            point,
        );
    }
    ledger.finish(&run);
    healthy(&mut run);
    run.record("pointer-routing-move-resize-settled");
    run.stop();
}
