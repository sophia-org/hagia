//! Real Hagia profile replacement and rejection through Session reload owners.
//! No fabricated handoff completion, forced reload deadline or direct rollback.
//! Output IPC/native presentation and action execution are outside this fixture.
use super::*;

fn assert_checkpoint_view_count(bytes: &[u8], expected: u64) {
    assert!(bytes.len() <= 1024 * 1024);
    let json = std::str::from_utf8(bytes)
        .unwrap()
        .strip_prefix("HAGIA-POLICY-CHECKPOINT-19\n")
        .expect("frozen Hagia checkpoint version");
    let model: serde_json::Value = serde_json::from_str(json).unwrap();
    assert_eq!(model["schema"].as_u64(), Some(19));
    assert_eq!(model["settings"]["viewCount"].as_u64(), Some(expected));
}

fn published_key(config: &ConfigFixture) -> sophia_config::DesktopProfileActivationKey {
    sophia_config::DesktopProfileActivationKey::from(&config.config.desktop_profile)
}

fn stage_profile(
    wm: &mut LiveWmSession,
    config: &mut ConfigFixture,
    document: &str,
) -> sophia_config::DesktopProfileActivationKey {
    std::fs::write(
        config.config.desktop_profile_source.as_ref().unwrap(),
        document,
    )
    .unwrap();
    let old = published_key(config);
    // Generic preparation must accept the envelope. The real WM owns whether
    // these policy values are valid, including the deliberate invalid case.
    let prepared = sophia_config::load_prepared_desktop_profile(
        config.config.desktop_profile_source.as_deref(),
        sophia_config::ConfigGeneration::from_raw(old.generation().raw() + 1),
    )
    .unwrap();
    let expected = sophia_config::DesktopProfileActivationKey::from(&prepared.profile);
    assert_ne!(expected, old);
    assert_eq!(
        wm.reload_desktop_profile(&mut config.config).unwrap(),
        DesktopProfileReloadOutcome::RestartRequired
    );
    assert_eq!(published_key(config), old, "staging is not publication");
    assert_eq!(wm.public.as_ref().unwrap().profile_key, Some(expected));
    assert!(wm.desktop_reload_pending());
    expected
}

struct ProfileExpectation<'a> {
    key: sophia_config::DesktopProfileActivationKey,
    rejected: Option<sophia_config::DesktopProfileActivationKey>,
    retained: &'a BTreeMap<SurfaceId, LayerSnapshot>,
    checkpoint: &'a Path,
    saved: &'a (Vec<u8>, (u64, u64)),
}

fn await_profile(
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    config: &mut ConfigFixture,
    output: sophia_engine::HeadlessOutput,
    expected: ProfileExpectation<'_>,
    identity: &mut std::fs::File,
) -> u64 {
    let ProfileExpectation {
        key: expected,
        rejected,
        retained,
        checkpoint,
        saved,
    } = expected;
    let started = Instant::now();
    let deadline = started + Duration::from_secs(15);
    let mut restart_max = Duration::ZERO;
    let mut request_max = Duration::ZERO;
    let mut publication_max = Duration::ZERO;
    let published_before = published_key(config);
    let catalog_before = wm.public.as_ref().unwrap().actions.clone();
    let configuration_before = wm.public.as_ref().unwrap().accepted_configuration.clone();
    assert_eq!(
        configuration_before.as_ref().unwrap().actions,
        catalog_before
    );
    let commands_before = wm.command_registry.generation;
    let mut rejected_peer = None;
    let mut last_epoch = 0;
    loop {
        assert!(
            Instant::now() < deadline,
            "fixed profile observation deadline"
        );
        let call = Instant::now();
        assert!(wm.poll_public_restart(layout, output).unwrap().is_none());
        restart_max = restart_max.max(call.elapsed());
        assert!(
            Instant::now() < deadline,
            "restart owner exceeded observation budget: {restart_max:?}"
        );
        let public = wm.public.as_ref().unwrap();
        if public.connection_epoch != last_epoch {
            last_epoch = public.connection_epoch;
            let protection = wm.supervisor.protection_evidence().unwrap();
            assert_eq!(wm.supervisor.peer_id(), Some(protection.peer_pid));
            assert!(
                protection
                    .roles
                    .contains(&sophia_runtime::ProtectionDomainRole::SpatialPolicy)
            );
            writeln!(
                identity,
                "replacement_epoch={last_epoch} profile={:?} protection={protection:?}",
                public.profile_key
            )
            .unwrap();
        }
        if let Some(rejected) = rejected
            && public.profile_key == Some(rejected)
        {
            assert!(!public.configured);
            rejected_peer = wm.supervisor.peer_id();
            assert_ne!(published_key(config), rejected);
        }
        let call = Instant::now();
        assert!(
            wm.poll_public_request(layout, output, false)
                .unwrap()
                .is_none()
        );
        request_max = request_max.max(call.elapsed());
        let public = wm.public.as_ref().unwrap();
        let current_configuration_published = public.configured
            && public
                .accepted_configuration
                .as_ref()
                .is_some_and(|value| value.connection_epoch == public.connection_epoch);
        if current_configuration_published {
            assert_eq!(public.profile_key, Some(expected));
            assert_eq!(published_key(config), expected);
        } else {
            // Restart revokes the callable catalog immediately. The accepted
            // configuration (including its catalog) remains retained until the
            // real idle-input publication owner accepts the replacement.
            assert!(public.actions.is_empty());
            assert_eq!(published_key(config), published_before);
            assert_eq!(public.accepted_configuration, configuration_before);
            assert_eq!(wm.command_registry.generation, commands_before);
        }
        let call = Instant::now();
        wm.settle_desktop_reload(&mut config.config, true).unwrap();
        publication_max = publication_max.max(call.elapsed());
        assert_eq!(&layout.layers, retained);
        assert_eq!(&await_checkpoint(checkpoint), saved);
        let public = wm.public.as_ref().unwrap();
        assert!(
            Instant::now() < deadline,
            "owner calls exceeded fixed observation budget: restart={restart_max:?} request={request_max:?} publication={publication_max:?}"
        );
        if public.configured
            && public.transport_ready
            && !wm.desktop_reload_pending()
            && !wm.force_transport_restart
            && public.profile_key == Some(expected)
            && published_key(config) == expected
        {
            if rejected.is_some() {
                assert!(
                    rejected_peer.is_some(),
                    "real rejected candidate was launched"
                );
                assert_ne!(wm.supervisor.peer_id(), rejected_peer);
            }
            writeln!(identity, "profile_observation_ms={} restart_call_max_ms={} request_call_max_ms={} publication_call_max_ms={} deadline_ms=15000 renewed=false hard_preemption=false", started.elapsed().as_millis(), restart_max.as_millis(), request_max.as_millis(), publication_max.as_millis()).unwrap();
            // The fixed observation deadline is checked around owner calls;
            // it cannot preempt a blocked syscall or strengthen supervisor
            // cleanup guarantees. The outer test process has its own timeout.
            return public.connection_epoch;
        }
        assert!(
            !wm.degraded,
            "normal Hagia profile recovery must not degrade"
        );
        assert!(
            Instant::now() < deadline,
            "real profile replacement/rollback deadline"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
}

struct RetainedProfileState<'a> {
    retained: &'a mut BTreeMap<SurfaceId, LayerSnapshot>,
    saved: &'a mut (Vec<u8>, (u64, u64)),
}

fn commit_restored_profile(
    wm: &mut LiveWmSession,
    layout: &mut PersistentLiveLayout,
    output: sophia_engine::HeadlessOutput,
    checkpoint: &Path,
    RetainedProfileState { retained, saved }: RetainedProfileState<'_>,
    identity: &mut std::fs::File,
) {
    // The real restart owner supplied the first scene; the real restored WM
    // supplies Dirty after settlement. Neither continuation is fixture-enqueued.
    let first = next_proposal(wm, layout, output);
    let first_request = wm
        .public
        .as_ref()
        .unwrap()
        .in_flight_request
        .clone()
        .unwrap();
    assert_restored_layers(&first, retained);
    commit_reconciled(wm, layout, output, first, retained, identity);
    *saved = replaced_checkpoint(checkpoint, saved.1);
    let next = next_proposal(wm, layout, output);
    let next_request = wm
        .public
        .as_ref()
        .unwrap()
        .in_flight_request
        .clone()
        .unwrap();
    assert!(next_request.policy_generation > first_request.policy_generation);
    assert_eq!(
        next_request.connection_epoch,
        first_request.connection_epoch
    );
    assert_restored_layers(&next, retained);
    commit_reconciled(wm, layout, output, next, retained, identity);
    await_ready(wm, layout, output);
    *saved = replaced_checkpoint(checkpoint, saved.1);
}

fn profile_recovery(case: &str, transport: WmTransportSelection) -> Vec<u8> {
    with_normal_hagia_transport(
        case,
        transport,
        |wm, layout, config, output, checkpoint, identity| {
            let original_document =
                std::fs::read_to_string(config.config.desktop_profile_source.as_ref().unwrap())
                    .unwrap();
            retain_existing_surface(layout);
            wm.enqueue_relayout(layout, output).unwrap();
            let initial = next_proposal(wm, layout, output);
            let mut controls = crate::session_control::SessionControlQueue::default();
            assert!(layout.stage(initial, &mut controls).unwrap().is_none());
            acknowledge_frontend_controls(layout, &mut controls);
            assert!(!layout.pending_is_ready());
            matching_pixels(layout);
            assert!(layout.pending_is_ready());
            assert!(wm.prepare_public_layout_commit(layout).unwrap());
            let result = layout.resolve_pending().unwrap();
            assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
            assert!(
                wm.apply_commit_result(result, None, output.id)
                    .unwrap()
                    .session_action
                    .is_none()
            );
            await_ready(wm, layout, output);
            let mut saved = await_checkpoint(checkpoint);
            let mut retained = layout.layers.clone();
            wm.enqueue_relayout(layout, output).unwrap();
            let focused = next_proposal(wm, layout, output);
            assert_eq!(
                wm.public
                    .as_ref()
                    .unwrap()
                    .reducer
                    .scene()
                    .outputs
                    .iter()
                    .find(|entry| entry.output == output.id)
                    .unwrap()
                    .focus,
                Some(SURFACE)
            );
            commit_reconciled(wm, layout, output, focused, &mut retained, identity);
            await_ready(wm, layout, output);
            saved = replaced_checkpoint(checkpoint, saved.1);
            let old_peer = wm.supervisor.peer_id();
            let old_key = published_key(config);
            let selected = wm.public.as_ref().unwrap().selected_capabilities;
            let allocator = wm.public.as_ref().unwrap().wm_filesystem_qids.clone();

            // This changes only an empty view-count setting, preserving the active
            // window's geometry while exercising actual staged profile replacement.
            let accepted_document = format!("{original_document}\npolicy {{ view-count 8; }}\n");
            let accepted_key = stage_profile(wm, config, &accepted_document);
            let accepted_epoch = await_profile(
                wm,
                layout,
                config,
                output,
                ProfileExpectation {
                    key: accepted_key,
                    rejected: None,
                    retained: &retained,
                    checkpoint,
                    saved: &saved,
                },
                identity,
            );
            assert_eq!(accepted_epoch, 2);
            assert_ne!(wm.supervisor.peer_id(), old_peer);
            assert_eq!(
                accepted_key.generation().raw(),
                old_key.generation().raw() + 1
            );
            assert_eq!(wm.public.as_ref().unwrap().selected_capabilities, selected);
            commit_restored_profile(
                wm,
                layout,
                output,
                checkpoint,
                RetainedProfileState {
                    retained: &mut retained,
                    saved: &mut saved,
                },
                identity,
            );
            let accepted_spec = wm.supervisor.launch_spec().clone();
            let accepted_catalog = wm.public.as_ref().unwrap().actions.clone();
            let accepted_commands = wm.command_registry.generation;
            let watermark = qid_observation::watermark(&allocator);
            let evidence =
                PathBuf::from(std::env::var_os("SOPHIA_HAGIA_FILE_EVIDENCE").unwrap()).join(case);
            std::fs::write(evidence.join("accepted.checkpoint"), &saved.0).unwrap();
            assert_checkpoint_view_count(&saved.0, 8);

            // Sophia admits the generic profile structure, while normal Hagia
            // rejects its out-of-range view count. No fake response or deadline.
            let rejected_document = format!("{original_document}\npolicy {{ view-count 10; }}\n");
            let rejected_key = stage_profile(wm, config, &rejected_document);
            let restored_epoch = await_profile(
                wm,
                layout,
                config,
                output,
                ProfileExpectation {
                    key: accepted_key,
                    rejected: Some(rejected_key),
                    retained: &retained,
                    checkpoint,
                    saved: &saved,
                },
                identity,
            );
            assert_eq!(restored_epoch, 4);
            assert_eq!(wm.supervisor.launch_spec(), &accepted_spec);
            assert_eq!(wm.public.as_ref().unwrap().actions, accepted_catalog);
            assert_eq!(wm.command_registry.generation, accepted_commands);
            assert_eq!(wm.public.as_ref().unwrap().selected_capabilities, selected);
            assert!(wm.public.as_ref().unwrap().output_service.is_none());
            assert!(qid_observation::same_owner(
                &allocator,
                &wm.public.as_ref().unwrap().wm_filesystem_qids
            ));
            if transport == WmTransportSelection::NineP2000L {
                assert!(qid_observation::watermark(&allocator) > watermark);
            }
            assert!(wm.pending_policy_launch_spec.is_none());
            let public = wm.public.as_mut().unwrap();
            let dirty_before = public.pending_dirty_outputs.clone();
            assert!(
                public
                    .admit_dirty(PolicyDirtyRequest {
                        connection_epoch: accepted_epoch,
                        policy_generation: u64::MAX,
                        affected_outputs: vec![output.id],
                    })
                    .is_err(),
                "old epoch is refused by the actual Dirty admission owner"
            );
            assert_eq!(public.pending_dirty_outputs, dirty_before);
            commit_restored_profile(
                wm,
                layout,
                output,
                checkpoint,
                RetainedProfileState {
                    retained: &mut retained,
                    saved: &mut saved,
                },
                identity,
            );
            writeln!(identity, "accepted_profile={accepted_key:?}\nrejected_profile={rejected_key:?}\nrestored_profile={:?}\naccepted_epoch={accepted_epoch}\nrollback_epoch={restored_epoch}\nrollback=actual_reload_supervisor_owners\nrejection_timing=files_preconnect_legacy_handoff\noutput_service=none\nnative_receipt=false\nexecutor_called=false", published_key(config)).unwrap();
            assert_checkpoint_view_count(&saved.0, 8);
            writeln!(identity, "stale_dirty=direct_owner_negative_not_wire\nold_socket_handles=not_exercised\naccepted_model_view_count=8").unwrap();
            saved.0
        },
    )
}

#[test]
#[ignore = "requires exact frozen normal Hagia and explicit fresh evidence inputs"]
fn normal_hagia_profile_replacement_and_rejection_roll_back_on_both_wires() {
    let ipc = profile_recovery("profile-recovery-ipc", WmTransportSelection::CurrentIpc);
    let files = profile_recovery("profile-recovery-files", WmTransportSelection::NineP2000L);
    assert_eq!(
        ipc, files,
        "same accepted profile/checkpoint after real rollback"
    );
}
