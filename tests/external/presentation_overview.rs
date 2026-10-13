//! Real overview targets from composed/retired frames on two logical outputs.
//! Input, surface bytes, topology and device completion remain supplied.
use super::*;
use sophia_backend_live::session_policy_presentation_fixture::SessionPolicyPresentationFixture;
use sophia_engine::{PolicyPointerHit, PresentedPolicyAction};

fn ordinary_focus(run: &Lifecycle) -> Option<SurfaceId> {
    let public = run.wm.public.as_ref().unwrap();
    public
        .reducer
        .committed()
        .iter()
        .find(|o| o.output == public.active_output)
        .and_then(|o| o.focus)
}

fn install_target(
    run: &mut Lifecycle,
    content: &mut Content,
    target: &mut SessionPolicyPresentationFixture,
) {
    let heads = target.heads();
    run.wm
        .install_committed_policy_presentation_with(
            &mut content.runtime,
            true,
            false,
            &heads,
            |runtime, desired| target.install(runtime, &content.scene, desired),
        )
        .unwrap();
}

fn retire_all(
    run: &mut Lifecycle,
    content: &mut Content,
    target: &mut SessionPolicyPresentationFixture,
    outputs: &[sophia_engine::HeadlessOutput],
) -> Vec<LivePresentedInputProjection> {
    for output in outputs {
        assert!(target.queued(output.id));
        target.simulate_submit(output.id);
        for head in 0..2 {
            target.simulate_head_completion(&mut content.runtime, output.id, head);
        }
    }
    let projections = content.runtime.input_projections().to_vec();
    service(run, &projections);
    projections
}

fn setup(
    case: &str,
) -> (
    Lifecycle,
    Content,
    SessionPolicyPresentationFixture,
    [sophia_engine::HeadlessOutput; 2],
) {
    let mut run = Lifecycle::native_ceiling(case, DESKTOP);
    populate(&mut run);
    let first = run.output;
    let second = sophia_engine::HeadlessOutput {
        id: OutputId::from_raw(first.id.raw() + 1),
        ..first
    };
    let outputs = [first, second];
    assert_eq!(
        run.wm
            .update_output_work_areas(&run.layout, &outputs, first)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    run.commit(proposal);
    let moving = ordinary_focus(&run).unwrap();
    let action = action_id(&run, "move-to-output-next");
    assert!(matches!(
        run.wm.enqueue_action(action, &run.layout, first).unwrap(),
        LiveOrderedWmActionAdmission::Admitted { .. }
    ));
    let proposal = run.proposal();
    assert_eq!(
        proposal
            .layers
            .iter()
            .find(|l| l.surface == moving)
            .unwrap()
            .output,
        Some(second.id)
    );
    run.commit(proposal);
    let mut content = commit_cpu_sources_on(&run, &outputs);
    let target = SessionPolicyPresentationFixture::new(&outputs);
    target.simulate_initialization(&mut content.runtime);
    (run, content, target, outputs)
}

fn open(
    run: &mut Lifecycle,
    content: &mut Content,
    target: &mut SessionPolicyPresentationFixture,
    outputs: &[sophia_engine::HeadlessOutput],
) -> Vec<LivePresentedInputProjection> {
    let before = ordinary_focus(run);
    let action = action_id(run, "toggle-overview");
    assert!(matches!(
        run.wm
            .enqueue_action(action, &run.layout, run.output)
            .unwrap(),
        LiveOrderedWmActionAdmission::Admitted { .. }
    ));
    let proposal = run.proposal();
    let (_, publication) = staged_publication(run).unwrap();
    assert_eq!(publication.outputs.len(), 2);
    assert!(!publication.instances.is_empty() && !publication.regions.is_empty());
    let previous = commit_with_install(run, content, proposal, |run, content| {
        install_target(run, content, target)
    });
    settle(run, previous);
    assert_eq!(ordinary_focus(run), before);
    let projections = retire_all(run, content, target, outputs);
    for output in outputs {
        let stamp = projections
            .iter()
            .find(|p| p.output == output.id)
            .and_then(|p| p.policy_publication.as_ref())
            .expect("overview must retire a publication on each logical output");
        assert!(!stamp.instances.is_empty() && !stamp.regions.is_empty());
        for region in publication.regions.iter().filter(|r| r.output == output.id) {
            assert!(
                stamp.regions.contains(&(region.id, region.generation)),
                "overview region must be drawn in the retired backend frame"
            );
        }
    }
    assert_eq!(
        receipts(run)
            .iter()
            .filter(|r| r.outcome == PolicyPresentationOutcome::Presented)
            .count(),
        2
    );
    projections
}

fn target_at(
    run: &Lifecycle,
    target: &SessionPolicyPresentationFixture,
    output: OutputId,
) -> (SurfaceId, Point, PresentedPolicyAction) {
    let frames = target.presented_surface_instances(output);
    assert_eq!(frames.len(), 2);
    let instance = frames[0]
        .iter()
        .find(|i| Some(i.source) != ordinary_focus(run))
        .expect("overview must offer another window");
    assert!(instance.id != 0 && instance.generation != 0);
    assert!(
        frames[1]
            .iter()
            .any(|other| other.id == instance.id && other.source == instance.source)
    );
    let public = run.wm.public.as_ref().unwrap();
    let bounds = public
        .reducer
        .scene()
        .outputs
        .iter()
        .find(|o| o.output == output)
        .unwrap()
        .bounds;
    let visible = instance.visible();
    let point = Point {
        x: f64::from(bounds.x + visible.x + visible.width / 2),
        y: f64::from(bounds.y + visible.y + visible.height / 2),
    };
    let PolicyPointerHit::Action(action) = public.presentation_input.pointer_hit(output, point)
    else {
        panic!("retired overview instance must provide an actionable target")
    };
    assert_eq!(
        action.identity.target_id, instance.id,
        "pointer identity must name the backend's retired instance"
    );
    assert_eq!(action.identity.target_generation, instance.generation);
    assert_eq!(action.identity.output, output);
    (instance.source, point, action)
}

fn pointer(
    routing: &mut Routing,
    run: &mut Lifecycle,
    projections: &[LivePresentedInputProjection],
    point: Point,
    pressed: bool,
    now: u64,
) -> PhysicalInputRouteReport {
    routing.pointer = SessionPointerPlacement::with_raw_to_logical_offset(Point::default());
    routing.pointer.set_output_bounds(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .reducer
            .scene()
            .outputs
            .iter()
            .map(|o| o.bounds)
            .collect(),
    );
    let (report, ingress) = routing.route_events(
        run,
        projections,
        &[
            InputEventKind::PointerMotion,
            InputEventKind::PointerButton {
                button: 0x110,
                pressed,
            },
        ],
        point,
        now,
    );
    assert_eq!(ingress, 0);
    report
}

fn refuse(run: &mut Lifecycle, action: PresentedPolicyAction, message: &str) {
    let queued = run.wm.public.as_ref().unwrap().queue.len();
    let saved = run.checkpoint();
    run.wm.enqueue_presented_action(action).unwrap();
    assert_eq!(
        run.wm.public.as_ref().unwrap().queue.len(),
        queued,
        "{message}"
    );
    assert_eq!(run.checkpoint(), saved);
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_overview_pointer_commits_exact_target() {
    let (mut run, mut content, mut target, outputs) = setup("overview-pointer");
    let projections = open(&mut run, &mut content, &mut target, &outputs);
    let (selected, point, expected) = target_at(&run, &target, outputs[0].id);
    let before = ordinary_focus(&run);
    assert_ne!(before, Some(selected));
    for (identity, message) in [
        (
            PolicyPresentationIdentity {
                target_generation: expected.identity.target_generation + 1,
                ..expected.identity
            },
            "stale overview target generation must not enter the peer queue",
        ),
        (
            PolicyPresentationIdentity {
                publication_generation: expected.identity.publication_generation + 1,
                ..expected.identity
            },
            "stale overview publication must not enter the peer queue",
        ),
        (
            PolicyPresentationIdentity {
                output: outputs[1].id,
                ..expected.identity
            },
            "overview target must not borrow another live output",
        ),
    ] {
        refuse(
            &mut run,
            PresentedPolicyAction {
                identity,
                ..expected
            },
            message,
        );
    }
    let mut routing = Routing::new();
    let pressed = pointer(&mut routing, &mut run, &projections, point, true, 1500);
    assert!(presented_actions(&pressed).is_empty());
    assert!(owes_pointer(&run, 0x110));
    let released = pointer(&mut routing, &mut run, &projections, point, false, 1501);
    assert_eq!(presented_actions(&released), vec![expected]);
    assert!(!owes_pointer(&run, 0x110));
    let saved = run.checkpoint();
    routing.dispatch(&mut run, &released);
    let proposal = run.proposal();
    assert!(
        matches!(in_flight_cause(&run), PolicyRequestCause::PresentationAction { action, identity, .. } if action == expected.action && identity == expected.identity)
    );
    assert_eq!(
        proposal.focus,
        Some(selected),
        "overview click must select the exact retired instance"
    );
    assert_eq!(ordinary_focus(&run), before);
    assert_eq!(run.checkpoint(), saved);
    assert!(staged_publication(&run).is_none());
    let previous = commit_with_install(&mut run, &mut content, proposal, |run, content| {
        install_target(run, content, &mut target)
    });
    settle(&mut run, previous);
    assert_eq!(ordinary_focus(&run), Some(selected));
    retire_all(&mut run, &mut content, &mut target, &outputs);
    refuse(
        &mut run,
        expected,
        "closed overview must not replay its old pointer target",
    );
    run.record("overview-pointer-committed");
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_overview_output_loss_preserves_release_debt() {
    let (mut run, mut content, mut target, outputs) = setup("overview-output-loss");
    let projections = open(&mut run, &mut content, &mut target, &outputs);
    let (_, point, old) = target_at(&run, &target, outputs[0].id);
    let before = ordinary_focus(&run);
    let mut routing = Routing::new();
    let report = pointer(&mut routing, &mut run, &projections, point, true, 1600);
    assert!(presented_actions(&report).is_empty() && owes_pointer(&run, 0x110));
    assert_eq!(
        run.wm
            .update_output_work_areas(&run.layout, &outputs[1..], outputs[1])
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    assert!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .reducer
            .presentation_publication()
            .is_none()
    );
    run.wm
        .public
        .as_mut()
        .unwrap()
        .revalidate_presentation_input();
    assert!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .presentation_input
            .publication()
            .is_none(),
        "output loss must revoke overview input before another frame"
    );
    assert!(
        owes_pointer(&run, 0x110),
        "output loss must retain the captured pointer release"
    );
    refuse(
        &mut run,
        old,
        "lost-output target cannot enter the peer queue",
    );
    run.output = outputs[1];
    let proposal = run.proposal();
    assert!(
        staged_publication(&run).is_none(),
        "real peer must close the overview after output loss"
    );
    let previous = commit_with_install(&mut run, &mut content, proposal, |run, content| {
        install_target(run, content, &mut target)
    });
    settle(&mut run, previous);
    assert_eq!(ordinary_focus(&run), before);
    let replaced = retire_all(&mut run, &mut content, &mut target, &outputs);
    let live = replaced
        .into_iter()
        .filter(|p| p.output == outputs[1].id)
        .collect::<Vec<_>>();
    let bounds = run.wm.public.as_ref().unwrap().reducer.scene().outputs[0].bounds;
    let outside_content = Point {
        x: f64::from(bounds.x),
        y: f64::from(bounds.y),
    };
    let release = pointer(&mut routing, &mut run, &live, outside_content, false, 1601);
    assert!(presented_actions(&release).is_empty());
    assert_eq!(
        release.pointer_buttons_suppressed_no_target, 0,
        "owed pointer release must be swallowed after output loss"
    );
    assert!(!owes_pointer(&run, 0x110));
    let duplicate = pointer(&mut routing, &mut run, &live, outside_content, false, 1602);
    assert!(presented_actions(&duplicate).is_empty());
    assert_eq!(
        duplicate.pointer_buttons_suppressed_no_target, 1,
        "duplicate release must return to ordinary routing after output loss"
    );
    assert_eq!(ordinary_focus(&run), before);
    run.record("overview-output-loss-settled");
    run.stop();
}
