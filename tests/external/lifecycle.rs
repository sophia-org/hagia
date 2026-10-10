//! Current SDK lifecycle assertions, mounted by niltempus in an explicit
//! Sophia test-source overlay. Scenes are empty or supplied occupied facts:
//! no application admission, pixels, physical input or native receipt is claimed.
use super::*;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::os::unix::fs::MetadataExt;

#[path = "occupied.rs"]
mod occupied;

#[path = "operations.rs"]
mod operations;

#[path = "slow_peer.rs"]
mod slow_peer;

#[path = "presentation.rs"]
mod presentation;

struct Lifecycle {
    // Drop the supervised child before its private profile directory.
    wm: LiveWmSession,
    source: ConfigFixture,
    layout: PersistentLiveLayout,
    output: sophia_engine::HeadlessOutput,
    checkpoint: PathBuf,
    evidence: PathBuf,
    binary: PathBuf,
    digest: String,
}

fn hash(path: &Path) -> String {
    assert!(std::fs::metadata(path).unwrap().len() <= 64 * 1024 * 1024);
    format!("{:x}", Sha256::digest(std::fs::read(path).unwrap()))
}

impl Lifecycle {
    fn new(case: &str) -> Self {
        Self::start(case, None)
    }

    /// The presentation case only: Session's native presentation ceiling is
    /// selected without any device, and the desktop profile is the case's own.
    /// Capability selection is not native presentation evidence.
    fn native_ceiling(case: &str, desktop: &str) -> Self {
        Self::start(case, Some(desktop))
    }

    fn start(case: &str, native_ceiling: Option<&str>) -> Self {
        let binary =
            std::fs::canonicalize(std::env::var_os("HAGIA_LIFECYCLE_BIN").unwrap()).unwrap();
        let digest = std::env::var("HAGIA_LIFECYCLE_SHA256").unwrap();
        assert_eq!(hash(&binary), digest);
        let evidence =
            PathBuf::from(std::env::var_os("HAGIA_LIFECYCLE_EVIDENCE").unwrap()).join(case);
        std::fs::create_dir(&evidence).expect("fresh case directory");
        let mut source = match native_ceiling {
            None => ConfigFixture::new(&[]),
            Some(desktop) => ConfigFixture::from_documents(CORE, desktop, &[]),
        };
        source.config.wm_socket_path = source.directory.join("wm.sock");
        source.config.wm_process = Some(binary.to_str().unwrap().to_owned());
        source.config.wm_process_args.clear();
        source.config.native_scanout = native_ceiling.is_some();
        let prepared = LiveWmSession::prepare_public_launch(&mut source.config).unwrap();
        let checkpoint = prepared.as_ref().unwrap().directory.checkpoint_path();
        assert!(!checkpoint.exists());
        let started = LiveWmSession::activate_public_launch(&mut source.config, prepared).unwrap();
        let output = sophia_engine::HeadlessOutput::deterministic();
        let wm = LiveWmSession::from_config(&source.config, &[output], started, None)
            .unwrap()
            .unwrap();
        let mut value = Self {
            wm,
            source,
            output,
            checkpoint,
            evidence,
            binary,
            digest,
            layout: PersistentLiveLayout::default(),
        };
        value.ready(false);
        let public = value.wm.public.as_ref().unwrap();
        assert_eq!(public.connection_epoch, 1);
        assert_eq!(public.profile_key, Some(value.profile_key()));
        assert!(!public.actions.is_empty());
        assert_eq!(
            public.accepted_configuration.as_ref().unwrap().actions,
            public.actions
        );
        assert!(value.wm.shortcuts.is_some());
        assert!(public.output_service.is_none());
        assert_ne!(
            public.selected_capabilities & sophia_protocol::SOPHIA_WM_CAPABILITY_PROFILE_ACTIVATION,
            0
        );
        assert_ne!(
            public.selected_capabilities & sophia_protocol::SOPHIA_WM_CAPABILITY_CONFIGURATION,
            0
        );
        if native_ceiling.is_none() {
            assert_eq!(
                public.selected_capabilities
                    & (sophia_protocol::SOPHIA_WM_CAPABILITY_SURFACE_INSTANCES
                        | sophia_protocol::SOPHIA_WM_CAPABILITY_PRESENTATION_ACTIONS),
                0
            );
            assert!(public.actions.iter().all(|a| a.name != "toggle-overview"));
        } else {
            // Source prediction for this offer and profile: every bit but 13
            // (pointer focus was not requested).
            assert_eq!(public.selected_capabilities, 0x7fdfff);
            assert!(public.actions.iter().any(|a| a.name == "toggle-overview"));
        }
        let spec = value.wm.supervisor.launch_spec();
        assert_eq!(spec.program, value.binary);
        assert!(spec.args.is_empty(), "ordinary Hagia, not a scripted peer");
        assert!(
            spec.environment
                .iter()
                .any(|(k, v)| k == "SOPHIA_WM_POLICY_PROFILE_ACTIVATION" && v == "required")
        );
        assert!(
            !spec
                .environment
                .iter()
                .any(|(k, _)| k == "SOPHIA_WM_SOCKET")
        );
        value.record("startup");
        value
    }

    fn profile_key(&self) -> sophia_config::DesktopProfileActivationKey {
        (&self.source.config.desktop_profile).into()
    }

    fn record(&self, phase: &str) {
        let public = self.wm.public.as_ref().unwrap();
        let protection = self.wm.supervisor.protection_evidence().unwrap();
        assert_eq!(self.wm.supervisor.peer_id(), Some(protection.peer_pid));
        assert!(
            protection
                .roles
                .contains(&sophia_runtime::ProtectionDomainRole::SpatialPolicy)
        );
        let mut log = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.evidence.join("observations.txt"))
            .unwrap();
        writeln!(log, "phase={phase} epoch={} profile={:?} capabilities={} actions={} peer={} protection={protection:?}",
            public.connection_epoch, public.profile_key, public.selected_capabilities, public.actions.len(), protection.peer_pid).unwrap();
        if self.checkpoint.exists() {
            std::fs::copy(
                &self.checkpoint,
                self.evidence.join(format!("{phase}.checkpoint")),
            )
            .unwrap();
        }
        std::fs::copy(
            self.source.config.desktop_profile_source.as_ref().unwrap(),
            self.evidence.join(format!("{phase}.desktop.kdl")),
        )
        .unwrap();
    }

    fn ready(&mut self, restart: bool) {
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            if restart {
                assert!(
                    self.wm
                        .poll_public_restart(&mut self.layout, self.output)
                        .unwrap()
                        .is_none()
                );
            }
            assert!(
                self.wm
                    .poll_public_request(&mut self.layout, self.output, false)
                    .unwrap()
                    .is_none()
            );
            self.wm
                .settle_desktop_reload(&mut self.source.config, true)
                .unwrap();
            let public = self.wm.public.as_ref().unwrap();
            if public.configured
                && public.transport_ready
                && !self.wm.desktop_reload_pending()
                && !self.wm.force_transport_restart
                && public.in_flight_request.is_none()
            {
                return;
            }
            assert!(!self.wm.degraded);
            assert!(Instant::now() < deadline, "configuration/Ready deadline");
            std::thread::sleep(Duration::from_millis(2));
        }
    }

    fn cycle(&mut self, enqueue: bool) {
        if enqueue {
            self.wm.enqueue_relayout(&self.layout, self.output).unwrap();
        }
        let proposal = self.proposal();
        assert!(proposal.layers.is_empty());
        self.commit(proposal);
    }

    fn proposal(&mut self) -> LiveWmProposal {
        let deadline = Instant::now() + Duration::from_secs(5);
        let proposal = loop {
            if let Some(proposal) = self
                .wm
                .poll_public_request(&mut self.layout, self.output, true)
                .unwrap()
            {
                break proposal;
            }
            assert!(Instant::now() < deadline, "fresh projection deadline");
            assert!(!self.wm.degraded && !self.wm.force_transport_restart);
            std::thread::sleep(Duration::from_millis(2));
        };
        assert_eq!(
            proposal.policy_settlement.unwrap().connection_epoch,
            self.wm.public.as_ref().unwrap().connection_epoch
        );
        let identity = proposal.policy_settlement.unwrap();
        std::fs::write(
            self.evidence.join(format!(
                "projection-e{}-r{}.txt",
                identity.connection_epoch, identity.request_id
            )),
            format!(
                "identity={identity:?}\nfocus={:?}\nlayers={:#?}\nscene={:#?}\n",
                proposal.focus,
                proposal.layers,
                self.wm.public.as_ref().unwrap().reducer.scene()
            ),
        )
        .unwrap();
        proposal
    }

    fn commit(&mut self, proposal: LiveWmProposal) {
        let previous = std::fs::metadata(&self.checkpoint).ok().map(|m| m.ino());
        let result = self.layout.commit_proposal(proposal);
        assert_eq!(result.update.commit.outcome, TransactionOutcome::Committed);
        self.wm
            .apply_commit_result(result, None, self.output.id)
            .unwrap();
        self.ready(false);
        // Ready belongs to transport custody; checkpoint fsync/rename belongs
        // to the peer. Observe that separate completion before reading it.
        let deadline = Instant::now() + Duration::from_secs(5);
        while Some(self.checkpoint().1) == previous {
            assert!(
                Instant::now() < deadline,
                "committed checkpoint replacement deadline"
            );
            std::thread::sleep(Duration::from_millis(2));
        }
    }

    fn checkpoint(&self) -> (Vec<u8>, u64) {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if let Ok(file) = std::fs::File::open(&self.checkpoint) {
                // One open file binds bytes and inode across atomic rename.
                let inode = file.metadata().unwrap().ino();
                let mut bytes = Vec::new();
                file.take(1024 * 1024).read_to_end(&mut bytes).unwrap();
                assert!(bytes.len() < 1024 * 1024);
                return (bytes, inode);
            }
            assert!(Instant::now() < deadline, "checkpoint deadline");
            std::thread::sleep(Duration::from_millis(2));
        }
    }

    fn views(&self, expected: u64) {
        let bytes = self.checkpoint().0;
        let json = std::str::from_utf8(&bytes)
            .unwrap()
            .strip_prefix("HAGIA-POLICY-CHECKPOINT-19\n")
            .unwrap();
        let model: serde_json::Value = serde_json::from_str(json).unwrap();
        assert_eq!(model["settings"]["viewCount"].as_u64(), Some(expected));
    }

    fn stop(mut self) {
        self.wm.public.as_mut().unwrap().worker.take();
        self.wm.supervisor.request_termination().unwrap();
        let deadline = Instant::now() + Duration::from_secs(5);
        while !self.wm.supervisor.poll_termination().unwrap() {
            assert!(Instant::now() < deadline, "child reap deadline");
            std::thread::sleep(Duration::from_millis(2));
        }
        assert!(self.wm.supervisor.peer_id().is_none());
        assert_eq!(hash(&self.binary), self.digest);
        std::fs::write(
            self.evidence.join("RESULT"),
            format!(
                "PASS child_reaped=true surfaces={} native=false\n",
                self.layout.layers.len()
            ),
        )
        .unwrap();
    }
}

#[test]
#[ignore = "requires current ordinary Hagia, isolated external overlay and fresh evidence"]
fn sdk_lifecycle_startup() {
    let run = Lifecycle::new("startup");
    assert!(
        !run.checkpoint.exists(),
        "startup alone does not commit a model"
    );
    run.stop();
}

#[test]
#[ignore = "requires current ordinary Hagia, isolated external overlay and fresh evidence"]
fn sdk_lifecycle_profile_rollback() {
    let mut run = Lifecycle::new("profile");
    let document =
        std::fs::read_to_string(run.source.config.desktop_profile_source.as_ref().unwrap())
            .unwrap();
    run.cycle(true);
    let mut accepted = run.profile_key();
    for (views, valid, epoch) in [(8, true, 2), (10, false, 4)] {
        let saved = run.checkpoint();
        let catalog = run.wm.public.as_ref().unwrap().actions.clone();
        std::fs::write(
            run.source.config.desktop_profile_source.as_ref().unwrap(),
            format!("{document}\npolicy {{ view-count {views}; }}\n"),
        )
        .unwrap();
        assert_eq!(
            run.wm
                .reload_desktop_profile(&mut run.source.config)
                .unwrap(),
            DesktopProfileReloadOutcome::RestartRequired
        );
        let candidate = run.wm.public.as_ref().unwrap().profile_key.unwrap();
        assert_ne!(candidate, accepted);
        assert_eq!(run.profile_key(), accepted, "staging cannot publish");
        run.ready(true);
        assert_eq!(run.wm.public.as_ref().unwrap().connection_epoch, epoch);
        assert_eq!(
            run.checkpoint(),
            saved,
            "no model commit during profile exchange"
        );
        if valid {
            accepted = candidate;
        }
        assert_eq!(run.profile_key(), accepted);
        assert_eq!(run.wm.public.as_ref().unwrap().profile_key, Some(accepted));
        if !valid {
            assert_eq!(run.wm.public.as_ref().unwrap().actions, catalog);
            assert_eq!(run.wm.desktop_reload_rollbacks, 1);
        }
        run.record(if valid { "replacement" } else { "rollback" });
        run.cycle(false); // Restart queued this scene, not the fixture.
        run.cycle(false); // Restored checkpoint requests its own Dirty continuation.
        run.views(8);
    }
    run.stop();
}

#[test]
#[ignore = "requires current ordinary Hagia, isolated external overlay and fresh evidence"]
fn sdk_lifecycle_restart() {
    let mut run = Lifecycle::new("restart");
    run.cycle(true);
    let profile = run.profile_key();
    let catalog = run.wm.public.as_ref().unwrap().actions.clone();
    for epoch in [2, 3] {
        let saved = run.checkpoint();
        let peer = run.wm.supervisor.peer_id();
        if epoch == 2 {
            // Only this fixture's protected child is terminated. The real
            // supervisor observes its exit and chooses automatic recovery.
            run.wm.supervisor.request_termination().unwrap();
            let deadline = Instant::now() + Duration::from_secs(5);
            while run.wm.public.as_ref().unwrap().connection_epoch < epoch {
                assert!(
                    run.wm
                        .poll_public_restart(&mut run.layout, run.output)
                        .unwrap()
                        .is_none()
                );
                assert!(!run.wm.degraded);
                assert!(
                    Instant::now() < deadline,
                    "automatic restart observes private child exit"
                );
                std::thread::sleep(Duration::from_millis(2));
            }
        } else {
            assert_eq!(run.wm.begin_control_restart(run.output).unwrap(), epoch);
        }
        run.ready(true);
        assert_eq!(run.wm.public.as_ref().unwrap().connection_epoch, epoch);
        assert_ne!(run.wm.supervisor.peer_id(), peer);
        assert_eq!(run.profile_key(), profile);
        assert_eq!(run.wm.public.as_ref().unwrap().actions, catalog);
        assert_eq!(run.checkpoint(), saved);
        run.record(if epoch == 2 { "automatic" } else { "requested" });
        run.cycle(false);
        run.cycle(false);
        run.views(9);
    }
    run.stop();
}
