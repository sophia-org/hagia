//! Hagia-owned launch-origin pairing, moved from Sophia 0319356db
//! crates/sophia-session/tests/support/launch_origin_socket.rs. Mounted by the
//! overlay as a child of that module: Sophia keeps the real X child, the
//! production admission policy and the generic `exercise_x_origin` driver;
//! this module supplies the Hagia policy client through `OriginPolicy` and the
//! Hagia-only cases. Test bodies and assertions are unchanged.
use super::*;

#[test]
fn hagia_real_x_child_origin_survives_monitor_switch_and_rejection() {
    let Some(binary) = std::env::var_os("SOPHIA_HAGIA_BIN") else {
        return;
    };
    for switch_before_connect in [false, true] {
        for hidden_workspace in [false, true] {
            exercise_x_origin(
                "hagia",
                |directory, parent| Some(PolicyFixture::new(binary.clone(), directory, parent)),
                switch_before_connect,
                hidden_workspace,
            );
        }
    }
}

impl OriginPolicy for PolicyFixture {
    fn launcher_context(
        &mut self,
        origins: &Arc<Mutex<LaunchOriginRegistry>>,
        parent: SurfaceId,
    ) -> PolicyLaunchContext {
        self.cycle(origins, PolicyRequestCause::SceneChanged, true)
            .launch_contexts
            .into_iter()
            .find(|c| c.surface == parent)
            .unwrap()
    }

    fn switch_away(&mut self, origins: &Arc<Mutex<LaunchOriginRegistry>>, hidden_workspace: bool) {
        PolicyFixture::switch_away(self, origins, hidden_workspace);
    }

    fn place_child(
        &mut self,
        origins: &Arc<Mutex<LaunchOriginRegistry>>,
        parent: SurfaceId,
        surface: SurfaceId,
        hidden_workspace: bool,
    ) {
        let mut scene = self.reducer.scene().clone();
        scene.generation += 1;
        let mut child_surface = scene.surfaces[0];
        child_surface.surface = surface;
        child_surface.current_output = None;
        scene.surfaces.push(child_surface);
        self.reducer.observe_scene(scene).unwrap();
        for commit in [false, true] {
            let proposal = self.cycle(origins, PolicyRequestCause::SceneChanged, commit);
            assert_eq!(proposal.active_output, OutputId::from_raw(2));
            for expected in [parent, surface] {
                assert_eq!(
                    proposal
                        .outputs
                        .iter()
                        .any(|o| o.output == OutputId::from_raw(1)
                            && o.placements.iter().any(|p| p.surface == expected)),
                    !hidden_workspace
                );
            }
            assert_eq!(
                origins.lock().unwrap().origins([surface]).is_empty(),
                commit
            );
        }
        if hidden_workspace {
            self.cycle(
                origins,
                PolicyRequestCause::PointerFocus {
                    output: OutputId::from_raw(1),
                    target: None,
                },
                true,
            );
            let action = self.action("focus-workspace 1");
            let proposal = self.cycle(
                origins,
                PolicyRequestCause::Action {
                    activation_serial: 2,
                    action,
                },
                true,
            );
            for expected in [parent, surface] {
                assert!(
                    proposal
                        .outputs
                        .iter()
                        .any(|o| o.output == OutputId::from_raw(1)
                            && o.placements.iter().any(|p| p.surface == expected))
                );
            }
        }
    }
}

struct PolicyFixture {
    child: ChildGuard,
    transport: sophia_runtime::PolicyWmSessionTransport,
    reducer: sophia_engine::PolicyProjectionReducer,
    transaction: u64,
    actions: Vec<PolicyActionRegistration>,
}

#[test]
#[ignore = "requires explicit freshly built Hagia; private sockets only"]
fn hagia_output_bookmark_places_empty_output_after_focus_switch_and_rejected_cycle() {
    let binary = std::env::var_os("SOPHIA_HAGIA_BIN").expect("explicit Hagia binary");
    for hidden in [false, true] {
        exercise_output_bookmark(binary.clone(), hidden);
    }
}

fn exercise_output_bookmark(binary: std::ffi::OsString, hidden: bool) {
    let directory =
        std::env::temp_dir().join(format!("sophia-output-origin-{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let origins = Arc::new(Mutex::new(LaunchOriginRegistry::default()));
    origins.lock().unwrap().set_epoch(1);
    let mut policy = PolicyFixture::new(binary, &directory, SurfaceId::new(10, 1));
    let mut empty = policy.reducer.scene().clone();
    let template = empty.surfaces[0];
    empty.generation += 1;
    empty.surfaces.clear();
    for output in &mut empty.outputs {
        output.focus = None;
    }
    policy.reducer.observe_scene(empty).unwrap();
    let first = policy.cycle(&origins, PolicyRequestCause::SceneChanged, true);
    assert_eq!(first.output_launch_contexts.len(), 2);
    let destination = first
        .output_launch_contexts
        .iter()
        .find(|c| c.output.raw() == 1)
        .copied()
        .unwrap();
    policy.switch_away(&origins, hidden);
    let surface = SurfaceId::new(20, 1);
    let admission = ClientAdmissionContext::new(
        ClientAdmissionId::from_raw(20),
        NamespaceContext::new(
            NamespaceId::from_raw(1),
            NamespaceProfile::ClassicShared,
            NamespaceCapabilities::NONE,
        )
        .unwrap(),
        ClientAuthProvenance::new(ClientAuthenticationMethod::PeerCredentials, 1).unwrap(),
    )
    .unwrap();
    {
        let mut registry = origins.lock().unwrap();
        registry.admit(
            admission,
            crate::launch_origin::ProcessIdentity {
                pid: 20,
                start_time: 20,
            },
            &[],
        );
        registry.observe_toplevel(surface, admission);
        assert!(registry.register_catalog_origin(
            surface,
            TransactionId::from_raw(90),
            destination
        ));
    }
    let mut scene = policy.reducer.scene().clone();
    scene.generation += 1;
    let mut child = template;
    child.surface = surface;
    child.current_output = None;
    scene.surfaces.push(child);
    policy.reducer.observe_scene(scene).unwrap();
    for commit in [false, true] {
        let proposal = policy.cycle(&origins, PolicyRequestCause::SceneChanged, commit);
        assert_eq!(proposal.active_output.raw(), 2);
        assert_eq!(
            proposal
                .outputs
                .iter()
                .any(|o| o.output.raw() == 1 && o.placements.iter().any(|p| p.surface == surface)),
            !hidden
        );
        assert!(
            !proposal
                .outputs
                .iter()
                .any(|o| o.output.raw() == 2 && o.placements.iter().any(|p| p.surface == surface))
        );
        assert_eq!(
            origins.lock().unwrap().origins([surface]).is_empty(),
            commit
        );
    }
    if hidden {
        policy.cycle(
            &origins,
            PolicyRequestCause::PointerFocus {
                output: OutputId::from_raw(1),
                target: None,
            },
            true,
        );
        let action = policy.action("focus-workspace 1");
        let proposal = policy.cycle(
            &origins,
            PolicyRequestCause::Action {
                activation_serial: 2,
                action,
            },
            true,
        );
        assert!(
            proposal
                .outputs
                .iter()
                .any(|o| o.output.raw() == 1 && o.placements.iter().any(|p| p.surface == surface))
        );
    }
    drop(policy);
    std::fs::remove_dir_all(directory).unwrap();
}
impl PolicyFixture {
    fn new(binary: std::ffi::OsString, directory: &std::path::Path, parent: SurfaceId) -> Self {
        use std::os::unix::fs::PermissionsExt;
        let mut transport = sophia_runtime::PolicyWmSessionTransport::bind_for_supervised_uid(
            directory.join("policy"),
            rustix::process::geteuid().as_raw(),
        )
        .unwrap();
        let profile = directory.join("desktop.kdl");
        std::fs::write(
            &profile,
            "schema 1\npolicy { focus-follows-mouse #true; }\n",
        )
        .unwrap();
        std::fs::set_permissions(&profile, std::fs::Permissions::from_mode(0o600)).unwrap();
        let mut command = Command::new(binary);
        for (name, _) in std::env::vars_os() {
            if name.to_string_lossy().starts_with("SOPHIA_")
                || name.to_string_lossy().starts_with("HAGIA_")
            {
                command.env_remove(name);
            }
        }
        let child = ChildGuard(
            command
                .arg(format!("--config={}", profile.display()))
                .arg(format!("--socket={}", transport.socket_path().display()))
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .spawn()
                .unwrap(),
        );
        transport.authorize_supervised_pid(child.0.id()).unwrap();
        transport.accept_and_negotiate(1, WAIT).unwrap();
        assert_ne!(
            transport.selected_capabilities() & SOPHIA_WM_CAPABILITY_LAUNCH_ORIGIN,
            0
        );
        let sophia_runtime::PolicyClientEvent::Configuration {
            transaction,
            configuration,
        } = transport.receive_client_event_within(WAIT).unwrap()
        else {
            panic!("missing configuration")
        };
        transport
            .send_configuration_outcome(
                transaction,
                configuration.generation,
                PolicyProjectionOutcome::Committed,
            )
            .unwrap();
        let bounds = Rect {
            x: 0,
            y: 0,
            width: 1280,
            height: 960,
        };
        let mut right = bounds;
        right.x = 1280;
        let scene = PolicySceneSnapshot {
            generation: 1,
            active_output: OutputId::from_raw(1),
            outputs: vec![
                PolicyOutputSnapshot {
                    policy_key: None,
                    output: OutputId::from_raw(1),
                    generation: 1,
                    focus: Some(parent),
                    bounds,
                    work_area: bounds,
                },
                PolicyOutputSnapshot {
                    policy_key: None,
                    output: OutputId::from_raw(2),
                    generation: 1,
                    focus: None,
                    bounds: right,
                    work_area: right,
                },
            ],
            surfaces: vec![PolicySurfaceSnapshot {
                surface: parent,
                generation: 1,
                current_output: Some(OutputId::from_raw(1)),
                kind: PolicySurfaceKind::Toplevel,
                capabilities: LayoutNodeCapabilities::STANDARD_TOPLEVEL,
                constraints: SurfaceConstraints {
                    min_size: None,
                    max_size: None,
                },
                exact_size: None,
                requested_state: PolicyPresentationState::default(),
                current_state: PolicyPresentationState::default(),
                transient_owner: None,
                geometry: bounds,
            }],
            session_operations: vec![],
        };
        let mut reducer = sophia_engine::PolicyProjectionReducer::new(scene).unwrap();
        reducer.connect(1).unwrap();
        Self {
            child,
            transport,
            reducer,
            transaction: 100,
            // This fixture provides policy actions only; no session launch or
            // logout operation is advertised in its snapshot.
            actions: configuration
                .actions
                .into_iter()
                .filter(|action| action.session_operation_slot.is_none())
                .collect(),
        }
    }
    fn action(&self, name: &str) -> WmActionId {
        self.actions.iter().find(|a| a.name == name).unwrap().action
    }
    fn switch_away(&mut self, origins: &Arc<Mutex<LaunchOriginRegistry>>, hidden_workspace: bool) {
        if hidden_workspace {
            let action = self.action("focus-workspace 2");
            let proposal = self.cycle(
                origins,
                PolicyRequestCause::Action {
                    activation_serial: 1,
                    action,
                },
                true,
            );
            assert!(proposal.outputs.iter().all(|o| o.placements.is_empty()));
        }
        let proposal = self.cycle(
            origins,
            PolicyRequestCause::PointerFocus {
                output: OutputId::from_raw(2),
                target: None,
            },
            true,
        );
        assert_eq!(proposal.active_output, OutputId::from_raw(2));
    }
    fn cycle(
        &mut self,
        origins: &Arc<Mutex<LaunchOriginRegistry>>,
        cause: PolicyRequestCause,
        commit: bool,
    ) -> PolicyProjectionProposal {
        let request = self
            .reducer
            .issue_request_with_cause(vec![OutputId::from_raw(1), OutputId::from_raw(2)], cause)
            .unwrap();
        let pending = origins
            .lock()
            .unwrap()
            .origins(self.reducer.scene().surfaces.iter().map(|s| s.surface));
        let mut snapshot = encode_wm_v1_policy_snapshot(
            TransactionId::from_raw(self.transaction),
            1,
            self.reducer.scene(),
            &self.actions,
            &[],
            self.transport.selected_capabilities(),
        )
        .unwrap();
        append_wm_launch_origins(
            &mut snapshot,
            &pending,
            self.transport.selected_capabilities(),
        )
        .unwrap();
        self.transport
            .send_snapshot(
                snapshot.transaction,
                &snapshot.begin,
                &snapshot.chunks,
                &snapshot.end,
            )
            .unwrap();
        self.transport
            .send_projection_request(TransactionId::from_raw(self.transaction + 1), &request)
            .unwrap();
        self.transaction += 2;
        let proposal = loop {
            match self.transport.receive_client_event_within(WAIT).unwrap() {
                sophia_runtime::PolicyClientEvent::Projection(
                    sophia_runtime::QueuedPolicyProjection::Admitted(transfer),
                ) => break decode_wm_v1_policy_projection(&transfer.into_wire_transfer()).unwrap(),
                sophia_runtime::PolicyClientEvent::ProjectionPending => {}
                event => panic!("unexpected event: {event:?}"),
            }
        };
        let staged = self.reducer.stage_proposal(&proposal).unwrap();
        let outcome = if commit {
            self.reducer.commit_staged(staged)
        } else {
            self.reducer.timeout(request.request_id)
        };
        assert_eq!(
            outcome,
            if commit {
                PolicyProjectionOutcome::Committed
            } else {
                PolicyProjectionOutcome::TimedOut
            }
        );
        if commit {
            let mut origins = origins.lock().unwrap();
            origins.publish(1, &proposal.launch_contexts);
            origins.publish_outputs(1, &proposal.output_launch_contexts);
            origins.committed(pending.iter().map(|c| c.surface));
        }
        self.transport
            .send_projection_outcome(
                proposal.transaction,
                request.request_id,
                self.reducer.scene().generation,
                outcome,
            )
            .unwrap();
        proposal
    }
}
impl Drop for PolicyFixture {
    fn drop(&mut self) {
        let _ = self.transport.disconnect();
        let _ = self.child.0.kill();
    }
}
