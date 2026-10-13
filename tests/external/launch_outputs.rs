//! Supplied process/output observations through production Session owners and
//! ordinary Hagia. No application launch, frontend delivery or device use.
use super::*;
use crate::launch_origin::ProcessIdentity;

const PROFILE: &str = "schema 1\nshell { enabled #false; }\nsession { terminal \"terminal\"; browser \"brave-origin\"; startup \"panel\"; }\nshortcut { profile \"default\"; }\npolicy { focus-follows-mouse #true; }\n";
const CHILD: SurfaceId = SurfaceId::new(59, 1);

fn admission(id: u64) -> ClientAdmissionContext {
    ClientAdmissionContext::new(
        ClientAdmissionId::from_raw(id),
        NamespaceContext::new(
            NamespaceId::from_raw(2),
            NamespaceProfile::ClassicShared,
            NamespaceCapabilities::NONE,
        )
        .unwrap(),
        ClientAuthProvenance::new(ClientAuthenticationMethod::PeerCredentials, 1).unwrap(),
    )
    .unwrap()
}

fn process(pid: u32) -> ProcessIdentity {
    ProcessIdentity {
        pid,
        start_time: u64::from(pid),
    }
}

fn second(run: &Lifecycle) -> sophia_engine::HeadlessOutput {
    sophia_engine::HeadlessOutput {
        id: OutputId::from_raw(run.output.id.raw() + 1),
        ..run.output
    }
}

fn topology(run: &mut Lifecycle, outputs: &[sophia_engine::HeadlessOutput]) {
    assert_eq!(
        run.wm
            .update_output_work_areas(&run.layout, outputs, run.output)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    run.commit(proposal);
    assert_eq!(
        run.wm
            .public
            .as_ref()
            .unwrap()
            .reducer
            .scene()
            .outputs
            .len(),
        outputs.len()
    );
}

fn activate_empty(run: &mut Lifecycle, output: OutputId) {
    let saved = run.checkpoint();
    let before = run.wm.public.as_ref().unwrap().active_output;
    assert_eq!(
        run.wm
            .enqueue_pointer_focus(crate::live_session::PresentedPointerFocus {
                output,
                target: None
            }),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    assert_eq!(run.checkpoint(), saved);
    assert_eq!(
        run.wm.public.as_ref().unwrap().active_output,
        before,
        "empty-output activation waits for commit"
    );
    assert_eq!(proposal.focus, None);
    run.commit(proposal);
    assert_eq!(run.wm.public.as_ref().unwrap().active_output, output);
}

fn observe_child(run: &mut Lifecycle, surface: SurfaceId, peer: ClientAdmissionContext) {
    let client = sophia_x_authority::XServerFrontendClientId::from_raw(peer.client_id.raw());
    let intent = SurfacePresentationIntent {
        surface,
        kind: SurfacePresentationIntentKind::Request,
        role: SurfacePresentationRole::PolicyManaged,
        surface_kind: LayoutNodeKind::Toplevel,
        placement_preference: SurfacePlacementPreference::Default,
        presentation_owner: None,
        stack_rank: 3,
        geometry: Rect {
            x: 20,
            y: 20,
            width: 160,
            height: 120,
        },
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
            surface,
            client,
            admission: Some(peer),
        });
    batch.presentation_intents.push(intent);
    batch.surface_presentations.push(
        sophia_x_authority::XAuthoritySurfacePresentationObservation {
            surface,
            role: intent.role,
            kind: intent.surface_kind,
            placement_preference: intent.placement_preference,
            owner: None,
            stack_rank: intent.stack_rank,
            mapped: true,
            geometry: intent.geometry,
            constraints: intent.constraints,
            generation: intent.generation,
        },
    );
    assert!(
        !run.layout
            .observe_authority_batch(&batch)
            .client_route_invalid
    );
    run.wm
        .public
        .as_ref()
        .unwrap()
        .launch_origins
        .lock()
        .unwrap()
        .observe_toplevel(surface, peer);
}

fn logical_output(checkpoint: &serde_json::Value, output: OutputId) -> u64 {
    checkpoint["activeOutputs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["output"].as_u64() == Some(output.raw()))
        .unwrap()["logical"]
        .as_u64()
        .unwrap()
}

fn home_output(checkpoint: &serde_json::Value, surface: SurfaceId) -> u64 {
    let key = (u64::from(surface.generation()) << 32) | u64::from(surface.index());
    let window = checkpoint["surfaces"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["key"].as_u64() == Some(key))
        .unwrap()["window"]
        .as_u64()
        .unwrap();
    checkpoint["windows"]
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["id"].as_u64() == Some(window))
        .unwrap()["homeOutput"]
        .as_u64()
        .unwrap()
}

fn tags(checkpoint: &serde_json::Value, surface: SurfaceId) -> serde_json::Value {
    let key = (u64::from(surface.generation()) << 32) | u64::from(surface.index());
    let window = checkpoint["surfaces"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["key"].as_u64() == Some(key))
        .unwrap()["window"]
        .as_u64()
        .unwrap();
    checkpoint["windowTags"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["owner"].as_u64() == Some(window))
        .unwrap()["tags"]
        .clone()
}

fn keyed_topology(run: &mut Lifecycle, entries: &[(sophia_engine::HeadlessOutput, &str, u64)]) {
    use sophia_backend_live::{
        LibdrmNativeOutputCapability, LibdrmNativeOutputTiming,
        LibdrmNativeVrrPropertyDiscoveryStatus,
    };
    let outputs = entries
        .iter()
        .map(|(output, _, _)| *output)
        .collect::<Vec<_>>();
    let policy = output_realization::OutputPolicyLayout {
        bounds: wm_output_bounds(&outputs),
        primary: run.output.id,
        keys: entries
            .iter()
            .map(|(_, connector, key)| ((*connector).to_owned(), *key))
            .collect(),
        capabilities: entries
            .iter()
            .map(|(output, connector, _)| {
                let mode = LibdrmNativeOutputTiming::new(
                    output.size.width as u32,
                    output.size.height as u32,
                    60_000,
                );
                LibdrmNativeOutputCapability::new(
                    output.id,
                    output.id.raw() as u32,
                    *connector,
                    [mode],
                    Some(mode),
                    mode,
                    LibdrmNativeVrrPropertyDiscoveryStatus::Unsupported,
                )
                .unwrap()
            })
            .collect(),
        timings: BTreeMap::new(),
    };
    let previous = run.wm.public.as_ref().unwrap().reducer.scene().generation;
    assert!(matches!(
        run.wm
            .update_output_work_areas_for_realization(&run.layout, &outputs, &policy)
            .unwrap(),
        LiveWmRequestAdmission::Admitted | LiveWmRequestAdmission::Duplicate
    ));
    assert!(
        run.wm.public.as_ref().unwrap().reducer.scene().generation > previous,
        "changed output facts must advance even when startup relayout coalesces"
    );
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_output_replacement_preserves_exact_authority() {
    let assignments = (1..=9)
        .map(|slot| format!("workspace {slot} output-key={};", (slot - 1) / 3 + 1))
        .collect::<String>();
    let profile = PROFILE.replace(
        "focus-follows-mouse #true;",
        &format!("focus-follows-mouse #true; view-count 3; {assignments}"),
    );
    let mut run = Lifecycle::with_profile("output-replacement", &profile);
    let first = run.output;
    let other = second(&run);
    keyed_topology(&mut run, &[(first, "DP-A", 1), (other, "DP-B", 2)]);
    let proposal = run.proposal();
    run.commit(proposal);
    populate(&mut run);
    let moving = focus(&run).unwrap();
    let proposal = action(&mut run, "move-to-output-next");
    assert_eq!(
        proposal
            .layers
            .iter()
            .find(|l| l.surface == moving)
            .unwrap()
            .output,
        Some(other.id)
    );
    run.commit(proposal);
    let before = model(&run);
    assert_eq!(
        home_output(&before, moving),
        logical_output(&before, other.id)
    );
    let publication = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .reducer
        .indicator_publication();
    let snapshot =
        crate::shell_indicator_projection::indicator_snapshot(&publication, Some(other.id), 91);
    let workspace = snapshot
        .indicators
        .iter()
        .find(|i| i.output == other.id && i.slot == 1)
        .unwrap();
    let action = WmActionId::from_raw(workspace.action);
    let admitted = run.wm.enqueue_indicator_action(action, other.id).unwrap();
    assert_eq!(admitted.admission, LiveWmRequestAdmission::Admitted);
    let stale = run.wm.public.as_ref().unwrap().queue.back().unwrap().cause;
    let old_generation = run.wm.public.as_ref().unwrap().output_generations[&other.id];
    let requests = run.wm.requests;
    let saved = run.checkpoint();
    keyed_topology(&mut run, &[(first, "DP-A", 1), (other, "DP-C", 3)]);
    let public = run.wm.public.as_ref().unwrap();
    assert!(public.output_generations[&other.id] > old_generation);
    assert!(
        !crate::live_session::policy_cause_subject_is_live(stale, public.reducer.scene()),
        "queued action must reject the predecessor output generation"
    );
    assert_eq!(run.checkpoint(), saved);
    let proposal = run.proposal();
    assert!(
        matches!(proposal.source, Some(LiveWmProposalSource::Relayout)),
        "replacement must withdraw the stale action before peer dispatch"
    );
    run.commit(proposal);
    assert_eq!(run.wm.requests, requests + 1);
    let scene = run.wm.public.as_ref().unwrap().reducer.scene();
    assert_eq!(
        scene
            .outputs
            .iter()
            .find(|o| o.output == first.id)
            .unwrap()
            .policy_key,
        Some(1)
    );
    assert_eq!(
        scene
            .outputs
            .iter()
            .find(|o| o.output == other.id)
            .unwrap()
            .policy_key,
        Some(3)
    );
    assert!(scene.outputs.iter().all(|o| o.policy_key != Some(2)));
    keyed_topology(&mut run, &[(first, "DP-A", 1)]);
    let proposal = run.proposal();
    run.commit(proposal);
    let checkpoint = model(&run);
    for surface in SURFACES {
        assert_eq!(
            home_output(&checkpoint, surface),
            logical_output(&checkpoint, first.id),
            "lost-output windows must move to the surviving logical output"
        );
    }
    assert_eq!(
        run.wm
            .enqueue_indicator_action(action, other.id)
            .unwrap()
            .admission,
        LiveWmRequestAdmission::Duplicate
    );
    keyed_topology(&mut run, &[(first, "DP-A", 1), (other, "DP-C", 3)]);
    let proposal = run.proposal();
    run.commit(proposal);
    let scene = run.wm.public.as_ref().unwrap().reducer.scene();
    assert_eq!(
        scene
            .outputs
            .iter()
            .find(|o| o.output == other.id)
            .unwrap()
            .policy_key,
        Some(3)
    );
    assert!(
        scene
            .outputs
            .iter()
            .find(|o| o.output == other.id)
            .unwrap()
            .generation
            > old_generation
    );
    let checkpoint = model(&run);
    let first_logical = logical_output(&checkpoint, first.id);
    let first_view = checkpoint["outputs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["id"].as_u64() == Some(first_logical))
        .unwrap()["activeView"]
        .clone();
    let public = run.wm.public.as_ref().unwrap();
    let generation = public.output_generations[&other.id];
    let publication = public.reducer.indicator_publication();
    let snapshot =
        crate::shell_indicator_projection::indicator_snapshot(&publication, Some(other.id), 91);
    let workspace = snapshot
        .indicators
        .iter()
        .find(|i| i.output == other.id && i.slot == 1)
        .unwrap();
    let action = WmActionId::from_raw(workspace.action);
    let saved = run.checkpoint();
    let admitted = run.wm.enqueue_indicator_action(action, other.id).unwrap();
    assert_eq!(admitted.admission, LiveWmRequestAdmission::Admitted);
    let proposal = run.proposal();
    assert!(
        matches!(run.wm.public.as_ref().unwrap().in_flight_request.as_ref().unwrap().cause,
        PolicyRequestCause::OutputAction { activation_serial, action: actual, output, output_generation }
        if Some(activation_serial) == admitted.activation_serial && actual == action && output == other.id && output_generation == generation)
    );
    assert_eq!(run.checkpoint(), saved);
    run.commit(proposal);
    let checkpoint = model(&run);
    assert_eq!(
        checkpoint["activeOutput"].as_u64(),
        Some(logical_output(&checkpoint, other.id))
    );
    assert_eq!(
        checkpoint["outputs"]
            .as_array()
            .unwrap()
            .iter()
            .find(|o| o["id"].as_u64() == Some(first_logical))
            .unwrap()["activeView"],
        first_view,
        "output action must not borrow its sibling's workspace"
    );
    let logical = logical_output(&checkpoint, other.id);
    let selected = checkpoint["outputs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["id"].as_u64() == Some(logical))
        .unwrap();
    assert_eq!(selected["activeView"].as_u64(), Some(workspace.indicator));
    assert_eq!(selected["policyKey"].as_u64(), Some(3));
    run.record("logical-output-replaced");
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_output_launch_context_survives_workspace_change() {
    let mut run = Lifecycle::with_profile("output-launch-context", PROFILE);
    populate(&mut run);
    let first = run.output;
    let other = second(&run);
    topology(&mut run, &[first, other]);
    let origins = run.wm.public.as_ref().unwrap().launch_origins.clone();
    let captured = *origins
        .lock()
        .unwrap()
        .output_contexts()
        .iter()
        .find(|c| c.output == first.id)
        .unwrap();
    let original_tags = tags(&model(&run), SURFACES[0]);
    let publication = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .reducer
        .indicator_publication();
    let snapshot =
        crate::shell_indicator_projection::indicator_snapshot(&publication, Some(first.id), 91);
    let workspace = snapshot
        .indicators
        .iter()
        .find(|i| i.output == first.id && i.slot == 2)
        .unwrap();
    let action = WmActionId::from_raw(workspace.action);
    assert_eq!(
        run.wm
            .enqueue_indicator_action(action, first.id)
            .unwrap()
            .admission,
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    run.commit(proposal);
    assert_ne!(
        origins
            .lock()
            .unwrap()
            .output_contexts()
            .iter()
            .find(|c| c.output == first.id)
            .unwrap()
            .token,
        captured.token,
        "workspace switch must publish a different launch destination"
    );
    activate_empty(&mut run, other.id);
    origins
        .lock()
        .unwrap()
        .admit(admission(2), process(200), &[]);
    observe_child(&mut run, CHILD, admission(2));
    {
        let mut registry = origins.lock().unwrap();
        for invalid in [
            PolicyOutputLaunchContext {
                epoch: captured.epoch + 1,
                ..captured
            },
            PolicyOutputLaunchContext {
                output_generation: captured.output_generation + 1,
                ..captured
            },
        ] {
            assert!(
                !registry.register_catalog_origin(CHILD, TransactionId::from_raw(721), invalid),
                "stale output launch identity must refuse without attribution"
            );
            assert!(registry.origins([CHILD]).is_empty());
        }
        // The catalog queue's capture/authorization has its own generic gate;
        // here its supplied saved record reaches the actual attribution owner.
        assert!(registry.register_catalog_origin(CHILD, TransactionId::from_raw(721), captured));
    }
    let saved = run.checkpoint();
    assert_eq!(
        run.wm
            .enqueue_manage(CHILD, &run.layout, run.output)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    assert!(
        !proposal.layers.iter().any(|l| l.surface == CHILD),
        "frozen workspace is hidden; launch must not borrow the current view"
    );
    assert_eq!(run.checkpoint(), saved);
    run.commit(proposal);
    let checkpoint = model(&run);
    assert_eq!(
        home_output(&checkpoint, CHILD),
        logical_output(&checkpoint, first.id)
    );
    assert_eq!(
        tags(&checkpoint, CHILD),
        original_tags,
        "catalog launch must retain the captured workspace tags"
    );
    assert_eq!(
        checkpoint["activeOutput"].as_u64(),
        Some(logical_output(&checkpoint, other.id))
    );
    assert!(origins.lock().unwrap().catalog_attribution(CHILD).is_none());
    run.record("frozen-output-context-committed");
    // Hidden placement settles policy while visual admission remains pending.
    // A replacement peer must be offered that question again, before any new
    // commit can incidentally clear the predecessor's settlement cache.
    assert!(run.layout.manage_settlements.contains_key(&CHILD));
    assert_eq!(run.layout.next_unmanaged_surface(), None);
    let saved = run.checkpoint();
    let epoch = run.wm.public.as_ref().unwrap().connection_epoch + 1;
    run.wm.supervisor.request_termination().unwrap();
    let deadline = Instant::now() + Duration::from_secs(5);
    while run.wm.public.as_ref().unwrap().connection_epoch < epoch {
        assert!(run.poll_restart().unwrap().is_none());
        assert!(!run.wm.degraded);
        assert!(Instant::now() < deadline, "pending Manage restart deadline");
        std::thread::sleep(Duration::from_millis(2));
    }
    assert_eq!(
        run.layout.next_unmanaged_surface(),
        Some(CHILD),
        "restart must rearm the pending hidden Manage before a new commit"
    );
    run.ready(true);
    assert_eq!(run.checkpoint(), saved);
    for _ in 0..2 {
        let proposal = run.proposal();
        run.commit(proposal);
    }
    assert_eq!(run.layout.next_unmanaged_surface(), Some(CHILD));
    assert_eq!(
        run.wm
            .enqueue_manage(CHILD, &run.layout, run.output)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    assert!(
        matches!(proposal.source, Some(LiveWmProposalSource::Manage(surface)) if surface == CHILD)
    );
    run.commit(proposal);
    assert_eq!(
        run.layout.next_unmanaged_surface(),
        None,
        "the fresh answer must stop the hidden admission re-ask loop"
    );
    assert_eq!(tags(&model(&run), CHILD), original_tags);
    run.record("pending-manage-rearmed");
    run.stop();
}

#[test]
#[ignore = "requires ordinary Hagia and isolated external overlay"]
fn sdk_launch_origin_survives_focus_change() {
    let mut run = Lifecycle::with_profile("launch-origin", PROFILE);
    populate(&mut run);
    let other = second(&run);
    let first = run.output;
    topology(&mut run, &[first, other]);
    // Supplied process identities enter the same registry as authenticated X
    // admission. The independent real-X-child test owns ancestry capture.
    let origins = run.wm.public.as_ref().unwrap().launch_origins.clone();
    {
        let mut registry = origins.lock().unwrap();
        registry.admit(admission(1), process(100), &[]);
        for surface in SURFACES {
            registry.observe_toplevel(surface, admission(1));
        }
        registry.focused(Some(SURFACES[0]));
    }
    run.wm.enqueue_relayout(&run.layout, run.output).unwrap();
    let proposal = run.proposal();
    let published = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .staged_launch_contexts
        .iter()
        .find(|c| c.surface == SURFACES[0])
        .copied()
        .unwrap();
    run.commit(proposal);
    origins
        .lock()
        .unwrap()
        .admit(admission(2), process(200), &[process(100)]);
    activate_empty(&mut run, other.id);
    assert_eq!(
        model(&run)["activeOutput"].as_u64(),
        Some(logical_output(&model(&run), other.id))
    );
    observe_child(&mut run, CHILD, admission(2));
    assert_eq!(
        origins.lock().unwrap().origins([CHILD]),
        vec![PolicyLaunchContext {
            surface: CHILD,
            ..published
        }],
        "child must retain the origin frozen before focus changed"
    );
    let saved = run.checkpoint();
    assert_eq!(
        run.wm
            .enqueue_manage(CHILD, &run.layout, run.output)
            .unwrap(),
        LiveWmRequestAdmission::Admitted
    );
    let proposal = run.proposal();
    assert!(
        matches!(proposal.source, Some(LiveWmProposalSource::Manage(surface)) if surface == CHILD)
    );
    assert_eq!(
        proposal
            .layers
            .iter()
            .find(|l| l.surface == CHILD)
            .unwrap()
            .output,
        Some(first.id),
        "frozen launch destination must beat the current empty output"
    );
    assert_eq!(run.checkpoint(), saved);
    run.commit(proposal);
    let checkpoint = model(&run);
    assert_eq!(
        home_output(&checkpoint, CHILD),
        logical_output(&checkpoint, first.id)
    );
    assert_eq!(
        checkpoint["activeOutput"].as_u64(),
        Some(logical_output(&checkpoint, other.id)),
        "background launch must not steal the active output"
    );
    assert!(
        origins.lock().unwrap().origins([CHILD]).is_empty(),
        "only committed placement consumes the frozen token"
    );
    run.record("frozen-origin-committed");
    run.stop();
}
