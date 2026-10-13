//! Direct production interaction admission with supplied motion and completion.
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
            .enqueue_pointer_interaction(
                crate::live_session::FloatingPointerPolicyInteraction {
                    surface: SURFACES[0],
                    mode,
                    phase,
                    geometry,
                    start: WmPointerPosition { x: 100, y: 100 },
                    current: WmPointerPosition {
                        x: geometry.x,
                        y: geometry.y,
                    },
                },
                &run.layout,
            )
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
