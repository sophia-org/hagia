//! Opt-in normal-Hagia control-path measurement, mounted beneath layout only
//! in the exact-source external overlay. No physical input, X client, backend
//! frame, native retirement or input-to-photon claim. The admission boundary
//! is Session's enqueue_pointer_interaction, not a fabricated policy request.
//!
//! Historical managed pixels and subsequent frontend ACKs/CPU observations are
//! supplied. Normal Hagia checkpoint writes/fsync remain enabled on both wires;
//! they may backpressure subsequent cycles. No per-update checkpoint reads,
//! fake WM outcomes, forced expiry, production hooks or second reducer.
use super::*;
use serde_json::{Value, json};

const MAX_UPDATES: u64 = 100_000;
const DRAIN_BUDGET: Duration = Duration::from_secs(12);
const POLL_PAUSE: Duration = Duration::from_micros(100);
const BASE: Rect = Rect {
    x: 96,
    y: 96,
    width: 320,
    height: 240,
};

#[derive(Clone, Copy)]
struct Settings {
    transport: WmTransportSelection,
    wire: &'static str,
    mode: WmPointerGestureMode,
    kind: &'static str,
    rate: u64,
    updates: u64,
}

impl Settings {
    fn from_env() -> Self {
        let required = |name| std::env::var(name).unwrap_or_else(|_| panic!("required {name}"));
        let (transport, wire) = match required("HAGIA_MEASURE_WIRE").as_str() {
            "current-ipc" => (WmTransportSelection::CurrentIpc, "current-ipc"),
            "9p2000.L" => (WmTransportSelection::NineP2000L, "9p2000.L"),
            _ => panic!("HAGIA_MEASURE_WIRE must be current-ipc or 9p2000.L"),
        };
        let (mode, kind) = match required("HAGIA_MEASURE_KIND").as_str() {
            "move" => (WmPointerGestureMode::Move, "move"),
            "resize" => (WmPointerGestureMode::Resize, "resize"),
            _ => panic!("HAGIA_MEASURE_KIND must be move or resize"),
        };
        let rate = required("HAGIA_MEASURE_RATE_HZ")
            .parse()
            .expect("integer rate");
        assert!(matches!(rate, 60 | 120));
        let updates = required("HAGIA_MEASURE_UPDATES")
            .parse()
            .expect("integer updates");
        assert!((1..=MAX_UPDATES).contains(&updates));
        Self {
            transport,
            wire,
            mode,
            kind,
            rate,
            updates,
        }
    }

    fn scheduled_ns(self, sequence: u64) -> u64 {
        sequence
            .checked_sub(1)
            .unwrap()
            .checked_mul(1_000_000_000)
            .unwrap()
            / self.rate
    }

    fn geometry(self, sequence: u64) -> Rect {
        let step = i32::try_from(sequence % 64).unwrap();
        match self.mode {
            WmPointerGestureMode::Move => Rect {
                x: BASE.x + step,
                y: BASE.y + step / 2,
                ..BASE
            },
            WmPointerGestureMode::Resize => Rect {
                width: BASE.width + step,
                height: BASE.height + step / 2,
                ..BASE
            },
        }
    }

    fn interaction(
        self,
        phase: PolicyInteractionPhase,
        geometry: Rect,
    ) -> FloatingPointerPolicyInteraction {
        FloatingPointerPolicyInteraction {
            surface: SURFACE,
            mode: self.mode,
            phase,
            start: WmPointerPosition {
                x: BASE.x,
                y: BASE.y,
            },
            current: WmPointerPosition {
                x: geometry.x,
                y: geometry.y,
            },
            geometry,
        }
    }
}

#[derive(Clone, Copy)]
struct Offered {
    sequence: u64,
    scheduled_ns: u64,
    enqueued_ns: u64,
    geometry: Rect,
    request_id: Option<u64>,
    transaction: Option<u64>,
}

struct Capture {
    settings: Settings,
    origin: Instant,
    offered: u64,
    admitted: u64,
    rejected: u64,
    coalesced: u64,
    settled: u64,
    timeouts: u64,
    disconnects: u64,
    rejected_settlements: u64,
    unresolved: u64,
    max_in_flight: usize,
    max_queue_depth: usize,
    queued: Option<Offered>,
    active: Option<Offered>,
    samples: Vec<Value>,
    failures: Vec<Value>,
}

impl Capture {
    fn new(settings: Settings) -> Self {
        Self {
            settings,
            origin: Instant::now(),
            offered: 0,
            admitted: 0,
            rejected: 0,
            coalesced: 0,
            settled: 0,
            timeouts: 0,
            disconnects: 0,
            rejected_settlements: 0,
            unresolved: 0,
            max_in_flight: 0,
            max_queue_depth: 0,
            queued: None,
            active: None,
            samples: Vec::with_capacity(usize::try_from(settings.updates).unwrap()),
            failures: Vec::new(),
        }
    }

    fn ns(&self) -> u64 {
        u64::try_from(self.origin.elapsed().as_nanos()).expect("bounded capture duration")
    }

    fn failure(&mut self, ticket: Offered, reason: &str) {
        // A queued update may have neither identity. A dispatched update may
        // have a request but no response transaction. Never invent either.
        self.failures.push(json!({
            "offered_sequence": ticket.sequence, "reason": reason,
            "request_id": ticket.request_id, "transaction": ticket.transaction,
            "scheduled_ns": ticket.scheduled_ns, "enqueued_ns": ticket.enqueued_ns,
            "observed_ns": self.ns(),
        }));
    }

    fn observe_depth(&mut self, wm: &LiveWmSession) {
        let public = wm.public.as_ref().unwrap();
        self.max_queue_depth = self.max_queue_depth.max(public.queue.len());
        self.max_in_flight = self
            .max_in_flight
            .max(usize::from(public.in_flight_request.is_some()));
        assert!(public.queue.len() <= WM_OWNER_REQUEST_CAPACITY);
    }

    fn offer(
        &mut self,
        wm: &mut LiveWmSession,
        layout: &PersistentLiveLayout,
    ) -> Result<(), String> {
        let sequence = self.offered.checked_add(1).unwrap();
        let geometry = self.settings.geometry(sequence);
        assert!(layout.is_policy_managed(SURFACE));
        assert!(
            committed_output_placing(&wm.public.as_ref().unwrap().reducer.committed(), SURFACE)
                .is_some()
        );
        let before = queued_update(wm, self.settings.mode);
        assert_eq!(before, self.queued.map(|ticket| ticket.geometry));
        if before == Some(geometry) {
            // After a sufficiently long stall the sawtooth can repeat. A
            // same-value queue cannot witness replacement versus dropped
            // Duplicate, so stop with partial evidence rather than count it.
            return Err(
                "repeated queued geometry cannot distinguish replacement from a dropped Update"
                    .into(),
            );
        }
        let ticket = Offered {
            sequence,
            scheduled_ns: self.settings.scheduled_ns(sequence),
            // Immediately before the real Session enqueue call, on one clock.
            enqueued_ns: self.ns(),
            geometry,
            request_id: None,
            transaction: None,
        };
        self.offered += 1;
        let admission = match wm.enqueue_pointer_interaction(
            self.settings
                .interaction(PolicyInteractionPhase::Update, geometry),
            layout,
        ) {
            Ok(admission) => admission,
            Err(error) => {
                self.rejected += 1;
                self.failure(ticket, "enqueue_refused");
                return Err(error.to_string());
            }
        };
        match admission {
            LiveWmRequestAdmission::Admitted => {
                assert!(self.queued.is_none());
                assert_eq!(queued_update(wm, self.settings.mode), Some(geometry));
                self.admitted += 1;
                self.queued = Some(ticket);
            }
            LiveWmRequestAdmission::Duplicate
                if before.is_some() && queued_update(wm, self.settings.mode) == Some(geometry) =>
            {
                // Duplicate also denotes dropped invalid input elsewhere.
                // Only this exact observed queue replacement counts as admission.
                self.queued.take().expect("replaced measured Update");
                self.coalesced += 1;
                self.admitted += 1;
                self.queued = Some(ticket);
            }
            LiveWmRequestAdmission::Duplicate | LiveWmRequestAdmission::RejectedCapacity => {
                assert_eq!(queued_update(wm, self.settings.mode), before);
                self.rejected += 1;
                self.failure(ticket, "enqueue_refused");
            }
        }
        self.observe_depth(wm);
        Ok(())
    }

    fn dispatched(&mut self, wm: &LiveWmSession) -> Result<(), String> {
        let public = wm.public.as_ref().ok_or("public owner disappeared")?;
        if let Some(request) = &public.in_flight_request {
            if public.in_flight_source
                != Some(LiveWmProposalSource::PointerGesture {
                    surface: SURFACE,
                    mode: self.settings.mode,
                })
            {
                return Err("unmeasured in-flight source; queued ticket preserved".into());
            }
            let ticket = self
                .active
                .or(self.queued)
                .ok_or("unmeasured cause entered timed window")?;
            if request.cause
                != interaction_cause(
                    self.settings.mode,
                    PolicyInteractionPhase::Update,
                    ticket.geometry,
                )
            {
                return Err("unmeasured in-flight cause; queued ticket preserved".into());
            }
            if let Some(active) = self.active {
                if active.request_id != Some(request.request_id) {
                    return Err(
                        "in-flight identity changed without observed layout settlement".into(),
                    );
                }
            } else {
                let mut ticket = self
                    .queued
                    .take()
                    .ok_or("unmeasured cause entered timed window")?;
                ticket.request_id = Some(request.request_id);
                self.active = Some(ticket);
            }
        } else if self.active.is_some() {
            // poll_public_request can internally reject a projection without
            // returning it. It does not expose that response tx/outcome here.
            // Record the loss of custody, not a guessed stale/invalid result.
            return Err("owner ended request without an exposed layout result".into());
        }
        self.observe_depth(wm);
        Ok(())
    }

    fn sample(&mut self, result: Settled) -> Result<(), String> {
        let mut ticket = self
            .active
            .take()
            .ok_or("settlement without measured request")?;
        assert_eq!(ticket.request_id, Some(result.identity.request_id));
        ticket.transaction = Some(result.identity.transaction.raw());
        let failure = match result.outcome {
            TransactionOutcome::Committed => None,
            TransactionOutcome::TimedOut => {
                self.timeouts += 1;
                Some("timed_out")
            }
            TransactionOutcome::RejectedStaleSurface => {
                self.rejected_settlements += 1;
                Some("rejected_stale")
            }
            TransactionOutcome::RejectedInvalidSurface => {
                self.rejected_settlements += 1;
                Some("rejected_invalid")
            }
        };
        if let Some(reason) = failure {
            self.failure(ticket, reason);
            return Err(format!("actual layout outcome {reason}"));
        }
        self.settled += 1;
        self.samples.push(json!({
            "offered_sequence": ticket.sequence,
            "request_id": result.identity.request_id,
            "transaction": result.identity.transaction.raw(), "outcome": "committed",
            "scheduled_ns": ticket.scheduled_ns, "enqueued_ns": ticket.enqueued_ns,
            "settled_ns": u64::try_from(result.at.duration_since(self.origin).as_nanos()).unwrap(),
        }));
        Ok(())
    }

    fn finish(mut self, mut error: Option<String>, disconnected: bool) -> Value {
        let deadline =
            error.as_deref() == Some("absolute capture/drain deadline (not a semantic timeout)");
        let mut unresolved_updates = Vec::new();
        for ticket in [self.active.take(), self.queued.take()]
            .into_iter()
            .flatten()
        {
            if disconnected {
                self.disconnects += 1;
            } else {
                self.unresolved += 1;
            }
            if disconnected || deadline {
                self.failure(
                    ticket,
                    if disconnected {
                        "disconnected"
                    } else {
                        "measurement_deadline"
                    },
                );
            } else {
                // An unexpected helper/owner error is not evidence of a
                // particular semantic refusal. Preserve custody separately.
                unresolved_updates.push(json!({
                    "offered_sequence": ticket.sequence, "request_id": ticket.request_id,
                    "transaction": ticket.transaction, "scheduled_ns": ticket.scheduled_ns,
                    "enqueued_ns": ticket.enqueued_ns, "observed_ns": self.ns(),
                }));
            }
        }
        let terminal = self
            .coalesced
            .checked_add(self.settled)
            .and_then(|n| n.checked_add(self.timeouts))
            .and_then(|n| n.checked_add(self.disconnects))
            .and_then(|n| n.checked_add(self.rejected_settlements))
            .and_then(|n| n.checked_add(self.unresolved));
        if self.admitted.checked_add(self.rejected) != Some(self.offered)
            || terminal != Some(self.admitted)
            || (error.is_none() && self.offered != self.settings.updates)
        {
            // A caught helper panic may interrupt a counter transition. Keep
            // the raw counts, even if the strict reporter refuses them. Never
            // overwrite the first failure with a finish assertion or repair
            // counts to manufacture conservation.
            let detail = "partial accounting interrupted; raw counts retained without repair";
            error = Some(match error {
                Some(first) => format!("{first}; {detail}"),
                None => detail.to_owned(),
            });
        }
        json!({
            "schema": 1, "wire": self.settings.wire, "rate_hz": self.settings.rate,
            "kind": self.settings.kind, "requested_updates": self.settings.updates,
            "offered": self.offered, "admitted": self.admitted, "rejected": self.rejected,
            "coalesced": self.coalesced, "settled": self.settled, "timeouts": self.timeouts,
            "disconnects": self.disconnects, "rejected_settlements": self.rejected_settlements,
            "unresolved": self.unresolved, "max_queue_depth": self.max_queue_depth,
            "max_in_flight": self.max_in_flight, "elapsed_ns": self.ns(),
            "samples": self.samples, "failures": self.failures,
            "unresolved_updates": unresolved_updates, "error": error,
            "status": if error.is_none() && self.rejected == 0 { "complete" } else { "failed" },
            "boundary": "session_enqueue_to_layout_settlement",
            "checkpoint_mode": "normal_hagia_enabled_same_filesystem",
            "frontend_acks": "supplied_through_actual_queue_correlation",
            "pixels": "supplied_cpu_observations_no_native_presentation",
            "acceptance": false,
        })
    }
}

fn queued_update(wm: &LiveWmSession, mode: WmPointerGestureMode) -> Option<Rect> {
    let updates = wm
        .public
        .as_ref()
        .unwrap()
        .queue
        .iter()
        .filter_map(|entry| {
            if entry.source
                != (LiveWmProposalSource::PointerGesture {
                    surface: SURFACE,
                    mode,
                })
            {
                return None;
            }
            match entry.cause {
                PolicyRequestCause::Interaction {
                    phase: PolicyInteractionPhase::Update,
                    geometry,
                    ..
                } => Some(geometry),
                _ => None,
            }
        })
        .collect::<Vec<_>>();
    assert!(
        updates.len() <= 1,
        "production coalescer keeps one queued Update"
    );
    updates.first().copied()
}

fn interaction_cause(
    mode: WmPointerGestureMode,
    phase: PolicyInteractionPhase,
    geometry: Rect,
) -> PolicyRequestCause {
    let kind = match mode {
        WmPointerGestureMode::Move => PolicyInteractionKind::Move,
        WmPointerGestureMode::Resize => PolicyInteractionKind::Resize,
    };
    PolicyRequestCause::Interaction {
        phase,
        kind,
        axis: PolicyInteractionAxis::None,
        target: SURFACE,
        geometry,
    }
}

struct Settled {
    identity: LivePolicySettlementIdentity,
    outcome: TransactionOutcome,
    at: Instant,
}

/// Supplies only client-side observations; it never resolves the WM reducer.
/// Two reusable buffers bound the size inventory, with a fresh batch tx and
/// the actual retained Engine generation for every resize. No CPU render or
/// copied backing claim follows from these metadata-only observations.
fn supply_resize_pixels(layout: &mut PersistentLiveLayout, serial: &mut u64) {
    let pending = layout.pending.as_ref().unwrap();
    if pending.requested_sizes.is_empty() {
        return;
    }
    assert_eq!(pending.requested_sizes.len(), 1);
    let size = pending.requested_sizes[&SURFACE];
    let geometry = pending
        .layers
        .iter()
        .find(|layer| layer.surface == SURFACE)
        .unwrap()
        .geometry;
    *serial = serial.checked_add(1).unwrap();
    let transaction = TransactionId::from_raw(*serial);
    let handle = 900 + *serial % 2;
    layout.cpu_buffer_sizes.insert(handle, size);
    let mut batch = crate::live_session::wm_update_coordinator_batch(transaction);
    batch.client = Some(sophia_x_authority::XServerFrontendClientId::from_raw(1));
    batch.transactions.push(SurfaceTransaction {
        transaction,
        authority: AuthorityKind::SophiaX,
        surface: SURFACE,
        namespace: None,
        target_geometry: geometry,
        presentation_extent: size,
        content: SurfaceContentSet::singleton(BufferSource::CpuBuffer { handle }, size),
        damage: Region::single(geometry),
        readiness: SurfaceTransactionReadiness::Ready,
        timeout_msec: 250,
        previous_committed_generation: layout.layers[&SURFACE].generation,
        input_region: None,
    });
    assert!(!layout.observe_authority_batch(&batch).client_route_invalid);
}

/// Same queue service/correlation path as acknowledge_frontend_controls, also
/// allowing the ordinary no-command turn. ACKs are simulated, not X delivery.
fn service_frontend(
    layout: &mut PersistentLiveLayout,
    controls: &mut crate::session_control::SessionControlQueue,
) {
    use sophia_x_authority::{
        XAuthorityClientControlAck, XAuthorityControlAck, XAuthorityControlKind,
        XAuthorityControlOutcome,
    };
    let (sender, receiver) = std::sync::mpsc::sync_channel(32);
    let (ack_sender, ack_receiver) = std::sync::mpsc::sync_channel(32);
    let mut completions = Vec::new();
    controls
        .service(&sender, &ack_receiver, Instant::now(), &mut completions)
        .unwrap();
    assert!(completions.is_empty());
    for command in receiver.try_iter() {
        ack_sender
            .send(XAuthorityClientControlAck {
                client: command.client,
                acknowledgement: XAuthorityControlAck {
                    kind: command.command.kind(),
                    transaction: command.command.transaction(),
                    surface: command.command.surface(),
                    outcome: XAuthorityControlOutcome::Delivered,
                },
            })
            .unwrap();
    }
    controls
        .service(&sender, &ack_receiver, Instant::now(), &mut completions)
        .unwrap();
    for completion in completions {
        assert!(completion.failure.is_none());
        if completion.key.kind == XAuthorityControlKind::SetPresentationState {
            assert!(layout.acknowledge_presentation_control(
                completion.key.transaction,
                completion.key.surface
            ));
        }
    }
}

fn apply_result(
    wm: &mut LiveWmSession,
    output: sophia_engine::HeadlessOutput,
    result: LiveWmCommitResult,
) -> Result<Settled, String> {
    let identity = result
        .policy_settlement
        .ok_or("missing actual settlement identity")?;
    let outcome = result.update.commit.outcome;
    let before = wm.public.as_ref().unwrap().reducer.commit_serial();
    let applied = wm
        .apply_commit_result(result, None, output.id)
        .map_err(|e| e.to_string())?;
    let at = Instant::now(); // Includes the actual public reducer/outcome handoff.
    assert!(applied.session_action.is_none());
    assert!(applied.physical_action.is_none());
    if outcome == TransactionOutcome::Committed {
        assert!(
            wm.public.as_ref().unwrap().reducer.commit_serial() > before,
            "layout Committed alone is insufficient without actual reducer commit"
        );
    }
    Ok(Settled {
        identity,
        outcome,
        at,
    })
}

fn settle_proposal(
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    output: sophia_engine::HeadlessOutput,
    proposal: LiveWmProposal,
    controls: &mut crate::session_control::SessionControlQueue,
    serial: &mut u64,
) -> Result<Option<Settled>, String> {
    assert!(layout.pending.is_none());
    assert!(!proposal.policy_settlement.unwrap().expect_session_operation);
    let immediate = layout
        .stage(proposal, controls)
        .map_err(|e| e.to_string())?;
    if let Some(result) = immediate {
        let settled = apply_result(wm, output, result)?;
        service_frontend(layout, controls);
        return Ok(Some(settled));
    }
    service_frontend(layout, controls);
    supply_resize_pixels(layout, serial);
    settle_pending(wm, layout, output, controls)
}

fn settle_pending(
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    output: sophia_engine::HeadlessOutput,
    controls: &mut crate::session_control::SessionControlQueue,
) -> Result<Option<Settled>, String> {
    let result = if layout.pending_is_ready() {
        if !wm
            .prepare_public_layout_commit(layout)
            .map_err(|e| e.to_string())?
        {
            return Err("real ready candidate failed preparation; no fabricated resolution".into());
        }
        layout.resolve_pending()
    } else {
        // Actual deadline only. Never force_pending_timeout in a measurement.
        layout.expire_pending(controls).map_err(|e| e.to_string())?
    };
    result
        .map(|result| apply_result(wm, output, result))
        .transpose()
}

fn idle(wm: &LiveWmSession, layout: &PersistentLiveLayout) -> bool {
    let public = wm.public.as_ref().unwrap();
    public.transport_ready
        && public.queue.is_empty()
        && public.in_flight_request.is_none()
        && public.pending_dirty_outputs.is_empty()
        && public.deferred_command.is_none()
        && layout.pending.is_none()
}

fn assert_committed_geometry(wm: &LiveWmSession, layout: &PersistentLiveLayout, outer: Rect) {
    let committed = wm.public.as_ref().unwrap().reducer.committed();
    let placement = committed
        .iter()
        .flat_map(|output| &output.placements)
        .find(|placement| placement.surface == SURFACE)
        .expect("committed managed placement");
    assert_eq!(placement.geometry, outer, "actual Hagia outer allocation");
    // The public reducer retains outer allocations. Session materializes
    // content layers through Engine's chrome conversion (proposal.rs).
    let content = sophia_engine::content_surface_geometry(outer, wm.candidate_chrome_style())
        .expect("valid workload content geometry");
    assert_eq!(layout.layers[&SURFACE].geometry, content);
}

fn warmup_drain(
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    output: sophia_engine::HeadlessOutput,
    controls: &mut crate::session_control::SessionControlQueue,
    serial: &mut u64,
) {
    let deadline = Instant::now() + DRAIN_BUDGET;
    loop {
        if let Some(proposal) = wm.poll_public_request(layout, output, true).unwrap() {
            if let Some(settled) =
                settle_proposal(wm, layout, output, proposal, controls, serial).unwrap()
            {
                assert_eq!(settled.outcome, TransactionOutcome::Committed);
            }
        } else if let Some(settled) = settle_pending(wm, layout, output, controls).unwrap() {
            assert_eq!(settled.outcome, TransactionOutcome::Committed);
        }
        assert!(!wm.force_transport_restart && !wm.degraded);
        if idle(wm, layout) {
            return;
        }
        assert!(Instant::now() < deadline, "untimed setup/drain deadline");
        std::thread::sleep(POLL_PAUSE);
    }
}

fn measured_loop(
    capture: &mut Capture,
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    output: sophia_engine::HeadlessOutput,
    controls: &mut crate::session_control::SessionControlQueue,
    serial: &mut u64,
) -> Result<(), String> {
    let deadline = capture.origin
        + Duration::from_nanos(capture.settings.scheduled_ns(capture.settings.updates))
        + DRAIN_BUDGET;
    let chrome = wm.candidate_chrome_style();
    loop {
        assert_eq!(
            wm.candidate_chrome_style(),
            chrome,
            "fixed measurement chrome"
        );
        if wm.force_transport_restart || wm.degraded {
            return Err("actual transport failure/restart requested".into());
        }
        if Instant::now() >= deadline {
            return Err("absolute capture/drain deadline (not a semantic timeout)".into());
        }
        // All elapsed schedule slots are offered. No relative sleep schedule,
        // skipping late work, or waiting for an answer before the next offer.
        while capture.offered < capture.settings.updates
            && capture.ns() >= capture.settings.scheduled_ns(capture.offered + 1)
        {
            if Instant::now() >= deadline {
                return Err("absolute capture/drain deadline (not a semantic timeout)".into());
            }
            capture.offer(wm, layout)?;
        }
        let proposal = wm
            .poll_public_request(layout, output, true)
            .map_err(|e| e.to_string())?;
        if wm.force_transport_restart || wm.degraded {
            return Err("actual transport failure/restart requested".into());
        }
        capture.dispatched(wm)?;
        let settled = if let Some(proposal) = proposal {
            let identity = proposal
                .policy_settlement
                .ok_or("proposal lost settlement identity")?;
            let active = capture.active.as_mut().ok_or("unmeasured proposal")?;
            assert_eq!(active.request_id, Some(identity.request_id));
            active.transaction = Some(identity.transaction.raw());
            settle_proposal(wm, layout, output, proposal, controls, serial)?
        } else {
            settle_pending(wm, layout, output, controls)?
        };
        if let Some(settled) = settled {
            if settled.outcome == TransactionOutcome::Committed {
                assert_committed_geometry(wm, layout, capture.active.unwrap().geometry);
            }
            capture.sample(settled)?;
        }
        capture.observe_depth(wm);
        if capture.offered == capture.settings.updates && idle(wm, layout) {
            assert!(capture.active.is_none() && capture.queued.is_none());
            return Ok(());
        }
        let pause = if capture.offered < capture.settings.updates {
            Duration::from_nanos(
                capture
                    .settings
                    .scheduled_ns(capture.offered + 1)
                    .saturating_sub(capture.ns()),
            )
            .min(POLL_PAUSE)
        } else {
            POLL_PAUSE
        };
        if !pause.is_zero() {
            std::thread::sleep(pause);
        }
    }
}

#[test]
#[ignore = "requires exact normal Hagia, fresh evidence and explicit HAGIA_MEASURE inputs; small runs are not acceptance"]
fn normal_hagia_session_drag_measurement() {
    let settings = Settings::from_env();
    let case_wire = match settings.transport {
        WmTransportSelection::CurrentIpc => "ipc",
        WmTransportSelection::NineP2000L => "files",
    };
    let case = format!("drag-{}-{}-{}", settings.kind, settings.rate, case_wire);
    with_normal_hagia_transport(
        &case,
        settings.transport,
        |wm, layout, _, output, checkpoint, identity| {
            let peer = wm.supervisor.peer_id();
            let mut controls = crate::session_control::SessionControlQueue::default();
            let mut serial = 1_000;
            // Check every point in the bounded sequence, including the max,
            // through Session's real clamp before any measurement begins.
            // Duplicate/drop classification must not rely on assumed bounds.
            let bounds = wm_output_bounds(&wm.public.as_ref().unwrap().outputs);
            for geometry in std::iter::once(BASE).chain((0..64).map(|n| settings.geometry(n))) {
                let start = settings
                    .interaction(PolicyInteractionPhase::Begin, BASE)
                    .start;
                let actual = clamp_floating_pointer_outline(
                    FloatingPointerOutline {
                        surface: SURFACE,
                        start,
                        geometry,
                    },
                    &bounds,
                );
                assert_eq!(
                    actual.map(|outline| outline.geometry),
                    Some(geometry),
                    "workload geometry must survive the actual admission clamp unchanged"
                );
            }
            retain_existing_surface(layout);
            wm.enqueue_relayout(layout, output).unwrap();
            warmup_drain(wm, layout, output, &mut controls, &mut serial);
            assert_eq!(
                wm.enqueue_pointer_interaction(
                    settings.interaction(PolicyInteractionPhase::Begin, BASE),
                    layout
                )
                .unwrap(),
                LiveWmRequestAdmission::Admitted
            );
            warmup_drain(wm, layout, output, &mut controls, &mut serial);
            assert_managed_baseline(layout);
            assert_committed_geometry(wm, layout, BASE);
            await_checkpoint(checkpoint);
            writeln!(identity, "measurement=control_path\nworkload=bounded_sawtooth_v1\ncheckpoint=normal_enabled\nsetup_and_end=excluded\noutput_service=none\nphysical_input=false\nfrontend_acks=supplied\ncpu_facts=supplied\nnative_presentation=false").unwrap();

            let mut capture = Capture::new(settings);
            // Retain partial evidence even if an actual owner/helper assertion
            // fails. This catches unwinding panics, not process abort, OOM or
            // the runner's hard deadline. Those still retain runner logs.
            let caught = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                measured_loop(&mut capture, wm, layout, output, &mut controls, &mut serial)
            }));
            let (result, panic) = match caught {
                Ok(result) => (result, None),
                Err(payload) => {
                    let message = payload
                        .downcast_ref::<String>()
                        .map(String::as_str)
                        .or_else(|| payload.downcast_ref::<&str>().copied())
                        .unwrap_or("non-string panic payload");
                    (
                        Err(format!("measured owner/helper panic: {message}")),
                        Some(payload),
                    )
                }
            };
            let disconnected = wm.force_transport_restart || wm.degraded;
            let report = capture.finish(result.as_ref().err().cloned(), disconnected);
            let path = PathBuf::from(std::env::var_os("SOPHIA_HAGIA_FILE_EVIDENCE").unwrap())
                .join(&case)
                .join("measurement.json");
            let file = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(path)
                .unwrap();
            serde_json::to_writer_pretty(file, &report).unwrap();
            if let Some(payload) = panic {
                std::panic::resume_unwind(payload);
            }
            result.expect("measurement failed; partial accounting retained in measurement.json");
            assert_eq!(report["rejected"], 0);
            assert_eq!(wm.supervisor.peer_id(), peer);
            // End and final peer-side persistence are outside the measured window.
            assert_eq!(
                wm.enqueue_pointer_interaction(
                    settings.interaction(
                        PolicyInteractionPhase::End,
                        settings.geometry(settings.updates)
                    ),
                    layout
                )
                .unwrap(),
                LiveWmRequestAdmission::Admitted
            );
            warmup_drain(wm, layout, output, &mut controls, &mut serial);
            await_checkpoint(checkpoint);
        },
    );
}
