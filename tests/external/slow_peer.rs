//! A live but stalled ordinary peer. The fixture pauses only its own protected
//! Hagia process with SIGSTOP, so Session's unmodified twelve-second response
//! deadline, not a process exit, must replace it. Occupied facts and layout
//! completion are supplied as in `occupied.rs`; no application runs and no
//! native presentation, AbortSettlement or paused-peer ESTALE is observed.
use super::*;
use sophia_protocol::*;
use std::sync::Mutex;

/// Session evidence lines, captured so the restart is bound to its reason.
static SESSION_LINES: Mutex<Vec<String>> = Mutex::new(Vec::new());

fn capture(line: &str) {
    SESSION_LINES.lock().unwrap().push(line.to_owned());
}

/// State, parent, start time and command name from `/proc/PID/stat`. `None`
/// only when the process is absent (ENOENT, or ESRCH in a teardown race); any
/// other read error fails rather than being mistaken for absence.
fn stat(pid: u32) -> Option<(char, u32, u64, String)> {
    let text = match std::fs::read_to_string(format!("/proc/{pid}/stat")) {
        Ok(text) => text,
        Err(error)
            if error.kind() == std::io::ErrorKind::NotFound || error.raw_os_error() == Some(3) =>
        {
            return None;
        }
        Err(error) => panic!("/proc/{pid}/stat: {error}"),
    };
    let open = text.find('(').unwrap();
    let close = text.rfind(')').unwrap();
    let comm = text[open + 1..close].to_owned();
    let fields: Vec<_> = text[close + 2..].split_whitespace().collect();
    Some((
        fields[0].chars().next().unwrap(),
        fields[1].parse().unwrap(),
        fields[19].parse().unwrap(),
        comm,
    ))
}

/// Owns the pause of one exact process. Drop resumes it if that same process
/// still exists, so a failed assertion cannot leave the fixture peer stopped;
/// the runner's PID namespace and outer timeout bound anything else.
struct PausedPeer {
    pid: u32,
    started: u64,
}

impl PausedPeer {
    fn pause(pid: u32, started: u64) -> Self {
        let paused = Self { pid, started };
        rustix::process::kill_process(
            rustix::process::Pid::from_raw(pid as i32).unwrap(),
            rustix::process::Signal::STOP,
        )
        .unwrap();
        paused
    }

    /// This exact process, not a reused PID, still has a /proc entry; a zombie
    /// awaiting its reaper still counts.
    fn present(&self) -> Option<char> {
        stat(self.pid)
            .filter(|(_, _, started, _)| *started == self.started)
            .map(|(state, ..)| state)
    }
}

impl Drop for PausedPeer {
    fn drop(&mut self) {
        if self.present().is_some() {
            let _ = rustix::process::kill_process(
                rustix::process::Pid::from_raw(self.pid as i32).unwrap(),
                rustix::process::Signal::CONT,
            );
        }
    }
}

fn enqueue_focus_next(run: &mut Lifecycle) {
    let action = run
        .wm
        .public
        .as_ref()
        .unwrap()
        .actions
        .iter()
        .find(|a| a.name == "focus-next")
        .unwrap()
        .action;
    assert!(matches!(
        run.wm
            .enqueue_action(action, &run.layout, run.output)
            .unwrap(),
        LiveOrderedWmActionAdmission::Admitted { .. }
    ));
}

#[test]
#[ignore = "requires current ordinary Hagia and isolated external overlay"]
fn sdk_slow_peer_response_deadline() {
    let _ = crate::install_session_output(crate::SessionOutput::new(capture, capture));
    let mut run = Lifecycle::new("slow-peer");
    occupied::populate(&mut run);
    let epoch = run.wm.public.as_ref().unwrap().connection_epoch;
    let saved = run.checkpoint();
    let committed = run.wm.public.as_ref().unwrap().reducer.committed();
    let layers = run.layout.layers.clone();

    // Prove the exact fixture peer before signalling it: the supervisor's
    // protected leader is this test's child, and the peer is that leader's child.
    let protection = run.wm.supervisor.protection_evidence().unwrap().clone();
    let peer = protection.peer_pid;
    assert_eq!(run.wm.supervisor.peer_id(), Some(peer));
    let (_, leader_parent, _, _) = stat(protection.supervisor_pid).unwrap();
    assert_eq!(
        leader_parent,
        std::process::id(),
        "protected leader is ours"
    );
    let (state, parent, started, comm) = stat(peer).unwrap();
    assert_eq!(
        parent, protection.supervisor_pid,
        "peer is the leader's child"
    );
    assert_eq!(comm, "hagia");
    assert!(matches!(state, 'S' | 'R'), "peer runs before the pause");
    let paused = PausedPeer::pause(peer, started);
    let deadline = Instant::now() + Duration::from_secs(2);
    loop {
        let (state, _, now_started, _) = stat(peer).unwrap();
        assert_eq!(now_started, started);
        if state == 'T' {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "peer did not reach the stopped state"
        );
        std::thread::sleep(Duration::from_millis(2));
    }
    let mut log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(run.evidence.join("observations.txt"))
        .unwrap();
    writeln!(
        log,
        "phase=paused peer={peer} leader={} started={started} state=T",
        protection.supervisor_pid
    )
    .unwrap();

    // One explicit action: Session sends its cycle, then waits for a
    // projection that the paused peer cannot send.
    enqueue_focus_next(&mut run);
    let sent = Instant::now();
    let outer = sent + Duration::from_secs(40);
    loop {
        assert!(
            run.wm
                .poll_public_request(&mut run.layout, run.output, true)
                .unwrap()
                .is_none(),
            "a paused peer cannot answer"
        );
        if run.wm.force_transport_restart {
            break;
        }
        assert!(
            Instant::now() < outer,
            "stalled peer must be replaced by the transport deadline"
        );
        std::thread::sleep(Duration::from_millis(10));
    }
    let detected = sent.elapsed();
    // The leader is alive: recovery is the transport deadline, not an exit.
    assert!(run.wm.supervisor.poll().unwrap().is_none());
    assert_eq!(stat(peer).unwrap().0, 'T');
    assert!(
        detected >= Duration::from_secs(12),
        "restart came before the response deadline: {detected:?}"
    );
    let reason = "status=restart_requested reason=public_transport_failed error=WM file response deadline expired";
    let lines = SESSION_LINES.lock().unwrap().clone();
    let first = lines
        .iter()
        .find(|line| line.contains("status=restart_requested"))
        .expect("restart request was recorded");
    assert!(first.contains(reason), "{first}");
    // Nothing committed while stalled.
    assert_eq!(run.checkpoint(), saved);
    assert_eq!(run.layout.layers, layers);
    assert_eq!(
        run.wm.public.as_ref().unwrap().reducer.committed(),
        committed
    );
    assert!(run.wm.public.as_ref().unwrap().in_flight_request.is_some());

    let restart = Instant::now();
    let deadline = restart + Duration::from_secs(15);
    while run.wm.public.as_ref().unwrap().connection_epoch == epoch {
        assert!(run.poll_restart().unwrap().is_none());
        assert!(Instant::now() < deadline, "slow-peer restart deadline");
        std::thread::sleep(Duration::from_millis(2));
    }
    let replaced = restart.elapsed();
    let public = run.wm.public.as_ref().unwrap();
    assert!(
        public.in_flight_request.is_none(),
        "stalled request must lose its authority"
    );
    assert!(public.pending_operation.is_none() && public.expected_operation_slot.is_none());
    assert!(public.deferred_command.is_none());
    assert!(public.staged.is_none() && public.prepared.is_none());
    assert_eq!(public.connection_epoch, epoch + 1);
    assert_ne!(run.wm.supervisor.peer_id(), Some(peer));
    // Bounded reap observation: absent, not merely a zombie still exiting.
    let reaped = Instant::now() + Duration::from_secs(5);
    let mut last = paused.present();
    while last.is_some() {
        assert!(
            Instant::now() < reaped,
            "paused peer was not reaped: {last:?}"
        );
        std::thread::sleep(Duration::from_millis(2));
        last = paused.present();
    }
    drop(paused);
    writeln!(
        log,
        "phase=replaced detected_ms={} restart_ms={} observation_only=true first_restart_line={first}",
        detected.as_millis(),
        replaced.as_millis()
    )
    .unwrap();
    std::fs::write(
        run.evidence.join("session-lines.txt"),
        lines.join("\n") + "\n",
    )
    .unwrap();
    assert_eq!(
        run.checkpoint(),
        saved,
        "a stalled peer cannot promote work"
    );

    // The successor restores through its own scene/Dirty exchange.
    run.ready(true);
    for _ in 0..2 {
        let next = run.proposal();
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
        run.commit(next);
        assert_eq!(
            run.wm.public.as_ref().unwrap().reducer.committed(),
            committed
        );
    }
    occupied::assert_checkpoint(&run);
    // A fresh explicit action is answered by the successor.
    enqueue_focus_next(&mut run);
    let next = run.proposal();
    assert_eq!(next.policy_settlement.unwrap().connection_epoch, epoch + 1);
    run.commit(next);
    occupied::assert_checkpoint(&run);
    run.record("slow-peer-replaced");
    run.stop();
}
