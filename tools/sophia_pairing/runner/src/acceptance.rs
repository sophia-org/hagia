//! Optional Hagia-owned pairing on a pinned Sophia base plus a test overlay.
//! Each ignored fixture runs explicitly; missing inputs or zero tests refuse.
//! Physical retirement, application execution and performance are separate.
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, File};
use std::io::Read;
use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use sha2::{Digest, Sha256};

const PREFIX: &str = "live_session::reload::tests::desktop_launch_reload::policy_hagia_session::";
const REQUIRED: &[&str] = &[
    "protected_normal_hagia_admits_profile_configuration_and_catalog_over_files",
    "normal_hagia_held_resize_commits_then_answers_a_fresh_request",
    "normal_hagia_timed_out_session_action_keeps_checkpoint_and_answers_next_request",
    "normal_hagia_current_ipc_and_files_preserve_layout_settlement",
    "real_hagia_resize_reaches_cpu_production_engine_commit",
    "real_hagia_timeout_keeps_cpu_production_state",
    "normal_hagia_committed_action_returns_intent_and_answers_next_request",
    "normal_hagia_behavior_corpus_matches_over_current_ipc_and_files",
    "normal_hagia_checkpoint_restore_survives_automatic_and_control_restart_on_both_wires",
    "normal_hagia_behavior_coverage_matches_over_current_ipc_and_files",
    "normal_hagia_receipts_follow_mirrored_backend_completion_on_both_wires",
    "normal_hagia_profile_replacement_and_rejection_roll_back_on_both_wires",
];
const LOG_LIMIT: u64 = 32 * 1024 * 1024;

struct Options {
    source: PathBuf,
    binary: PathBuf,
    sha256: String,
    output: PathBuf,
    target: PathBuf,
    timeout: Duration,
}

/// A gate owns only its lock, never an existing caller's target contents.
struct TargetLease(PathBuf);

impl Drop for TargetLease {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

pub fn run(cwd: &Path, args: &[String]) -> Result<Vec<String>, String> {
    let options = options(cwd, args)?;
    crate::overlay::validate_source(&options.source)?;
    let compatibility = crate::overlay::compatibility()?;
    if digest(&options.binary)? != options.sha256
        || compatibility["hagia_sha256"].as_str() != Some(options.sha256.as_str())
    {
        return Err("Hagia executable does not match --hagia-sha256".into());
    }
    fs::create_dir_all(&options.target).map_err(|e| format!("create target: {e}"))?;
    let lock = options.target.join(".hagia-pairing.lock");
    File::create_new(&lock)
        .map_err(|e| format!("exclusive gate target {}: {e}", lock.display()))?;
    let _lease = TargetLease(lock);
    for path in [
        options.output.clone(),
        options.output.join("tmp"),
        options.output.join("tmp/config"),
        options.output.join("tmp/runtime"),
        options.output.join("cases"),
    ] {
        fs::DirBuilder::new()
            .mode(0o700)
            .create(&path)
            .map_err(|e| format!("create fresh evidence {}: {e}", path.display()))?;
    }
    let deadline = Instant::now() + options.timeout;
    let repo = match crate::overlay::prepare(&options.source, &options.output) {
        Ok(repo) => repo,
        Err(error) => {
            fs::write(
                options.output.join("report.json"),
                serde_json::to_vec_pretty(
                    &json!({"schema": 1, "status": "fail", "phase": "overlay", "error": error}),
                )
                .map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
            return Err(error);
        }
    };
    let before = identity(&repo, &options)?;
    let mut phases = Vec::new();
    write_report(&options, &before, None, &phases, "running", None)?;
    let result = exercise(&repo, &options, deadline, &before, &mut phases);
    let after = identity(&repo, &options);
    let result = result.and_then(|()| {
        crate::overlay::validate_source(&options.source)?;
        if after.as_ref().is_ok_and(|after| *after == before) {
            Ok(())
        } else {
            Err(
                "source or Hagia executable changed during acceptance; evidence is not coherent"
                    .into(),
            )
        }
    });
    write_report(
        &options,
        &before,
        after.as_ref().ok(),
        &phases,
        if result.is_ok() { "pass" } else { "fail" },
        result.as_ref().err().map(String::as_str),
    )?;
    result?;
    Ok(vec![format!(
        "Hagia pairing: PASS; pinned Sophia base plus recorded test overlay; physical acceptance and performance not claimed; {}",
        options.output.join("report.json").display()
    )])
}

fn exercise(
    repo: &Path,
    options: &Options,
    deadline: Instant,
    before: &Value,
    phases: &mut Vec<Value>,
) -> Result<(), String> {
    let mut phase = |name: &str,
                     program: &str,
                     args: &[&str],
                     judgment: fn(&str) -> Result<(), String>| {
        let log = options.output.join(format!("{name}.log"));
        let start = Instant::now();
        let result = stage(repo, options, deadline, program, args, &log)
            .and_then(|()| read_log(&log))
            .and_then(|text| judgment(&text));
        phases.push(json!({"name": name, "log": log, "elapsed_msec": start.elapsed().as_millis(),
            "status": if result.is_ok() { "pass" } else { "fail" }, "error": result.as_ref().err()}));
        write_report(options, before, None, phases, "running", None)?;
        result
    };
    phase(
        "isolation",
        "sh",
        &[
            "-c",
            "test ! -e /dev/dri && test ! -e /dev/input && test -z \"${DISPLAY-}\" && test -z \"${SOPHIA_WM_SOCKET-}\" && test -z \"${SOPHIA_WM_9P_SOCKET-}\"",
        ],
        |_| Ok(()),
    )?;
    phase(
        "protocol",
        "cargo",
        &[
            "test",
            "--offline",
            "--locked",
            "-j",
            "2",
            "-p",
            "sophia-protocol",
            "--tests",
            "--",
            "--test-threads=1",
        ],
        require_nonempty,
    )?;
    let session = [
        "test",
        "--offline",
        "--locked",
        "-j",
        "2",
        "-p",
        "sophia-session",
        "--features",
        "native-session",
        "--lib",
    ];
    let mut listing = session.to_vec();
    listing.extend([PREFIX, "--", "--list", "--ignored"]);
    phase("required-list", "cargo", &listing, |text| {
        required_tests(text).map(|_| ())
    })?;
    let tests = required_tests(&read_log(&options.output.join("required-list.log"))?)?;
    let test_binary = listed_binary(
        &read_log(&options.output.join("required-list.log"))?,
        &options.target,
        "unittests src/lib.rs",
    )?;
    let test_hash = digest(&test_binary)?;
    fs::write(
        options.output.join("test-binary.json"),
        serde_json::to_vec_pretty(&json!({"path": test_binary, "sha256": test_hash}))
            .map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    for (index, test) in tests.iter().enumerate() {
        let args = [
            test,
            "--exact",
            "--ignored",
            "--nocapture",
            "--test-threads=1",
        ];
        if digest(&test_binary)? != test_hash {
            return Err("paired test executable changed before a required case".into());
        }
        phase(
            &format!("owner-{index:02}"),
            test_binary
                .to_str()
                .ok_or("test executable path must be UTF-8")?,
            &args,
            require_exactly_one,
        )?;
        if digest(&test_binary)? != test_hash {
            return Err("paired test executable changed between required cases".into());
        }
    }
    crate::legacy::exercise(&mut phase, &options.output, &options.target)?;
    phase(
        "strict",
        "cargo",
        &[
            "clippy",
            "--offline",
            "--locked",
            "-j",
            "2",
            "-p",
            "sophia-session",
            "--features",
            "native-session",
            "--all-targets",
            "--",
            "-D",
            "warnings",
        ],
        |_| Ok(()),
    )?;
    phase(
        "strict-runtime",
        "cargo",
        &[
            "clippy",
            "--offline",
            "--locked",
            "-j",
            "2",
            "-p",
            "sophia-runtime",
            "--all-targets",
            "--",
            "-D",
            "warnings",
        ],
        |_| Ok(()),
    )?;
    // Cargo rebuilds this checkout's xtask rather than accepting an old binary.
    phase(
        "layout",
        "cargo",
        &[
            "run",
            "--offline",
            "--locked",
            "-j",
            "2",
            "-p",
            "xtask",
            "--",
            "check",
            "layout",
        ],
        |_| Ok(()),
    )?;
    phase("format", "cargo", &["fmt", "--all", "--check"], |_| Ok(()))?;
    let overlay: Value = serde_json::from_slice(
        &fs::read(options.output.join("overlay.json")).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    let mut format_args = vec![
        "--check",
        "--edition",
        "2024",
        "--config",
        "skip_children=true",
    ];
    for file in overlay["files"]
        .as_array()
        .ok_or("invalid overlay file manifest")?
    {
        let path = file["path"].as_str().ok_or("invalid overlay path")?;
        // Base mount files can contain pre-existing formatting debt. Check
        // injected fixtures directly; preserve and hash the base plus mounts.
        if file["kind"] == "fixture" && path.ends_with(".rs") {
            format_args.push(path);
        }
    }
    phase("overlay-format", "rustfmt", &format_args, |_| Ok(()))?;
    phase("whitespace", "git", &["diff", "--check"], |_| Ok(()))?;
    Ok(())
}

fn options(repo: &Path, args: &[String]) -> Result<Options, String> {
    let mut values = BTreeMap::new();
    for argument in args {
        let (key, value) = argument.split_once('=').ok_or("expected --name=value")?;
        if ![
            "--sophia-root",
            "--hagia-bin",
            "--hagia-sha256",
            "--output",
            "--target-dir",
            "--timeout",
        ]
        .contains(&key)
            || value.is_empty()
            || values.insert(key, value).is_some()
        {
            return Err(format!("invalid or duplicate pairing option {argument:?}"));
        }
    }
    let path = |key: &str| -> Result<PathBuf, String> {
        let value = values
            .get(key)
            .ok_or_else(|| format!("pairing requires {key}"))?;
        let path = PathBuf::from(value);
        Ok(if path.is_absolute() {
            path
        } else {
            repo.join(path)
        })
    };
    let binary = path("--hagia-bin")?
        .canonicalize()
        .map_err(|e| format!("required Hagia: {e}"))?;
    let metadata = fs::metadata(&binary).map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.permissions().mode() & 0o111 == 0 {
        return Err("Hagia must be an executable regular file".into());
    }
    let sha256 = values
        .get("--hagia-sha256")
        .ok_or("pairing requires --hagia-sha256")?
        .to_string();
    if sha256.len() != 64
        || !sha256
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    {
        return Err("Hagia SHA256 must be 64 lowercase hexadecimal digits".into());
    }
    let seconds = values
        .get("--timeout")
        .unwrap_or(&"3600")
        .parse::<u64>()
        .map_err(|_| "invalid timeout")?;
    if !(1..=7200).contains(&seconds) {
        return Err("timeout must be 1..7200 seconds".into());
    }
    let output = path("--output")?;
    if output.exists() {
        return Err("WM acceptance requires a fresh evidence directory".into());
    }
    Ok(Options {
        source: path("--sophia-root")?
            .canonicalize()
            .map_err(|e| e.to_string())?,
        binary,
        sha256,
        output,
        target: path("--target-dir")?,
        timeout: Duration::from_secs(seconds),
    })
}

fn stage(
    repo: &Path,
    options: &Options,
    deadline: Instant,
    program: &str,
    args: &[&str],
    log: &Path,
) -> Result<(), String> {
    let remaining = deadline
        .checked_duration_since(Instant::now())
        .ok_or("WM acceptance deadline expired")?;
    let stdout = File::create(log).map_err(|e| e.to_string())?;
    let stderr = stdout.try_clone().map_err(|e| e.to_string())?;
    // Killing the PID-namespace init collects its descendants, including a
    // hung protected peer. A bounded phase never falls back to the host.
    let mut command = Command::new("nice");
    command
        .args([
            "-n",
            "19",
            "timeout",
            "--signal=KILL",
            &format!("{:.3}s", remaining.as_secs_f64()),
        ])
        .args([
            "bwrap",
            "--die-with-parent",
            "--unshare-pid",
            "--bind",
            "/",
            "/",
            "--dev",
            "/dev",
            "--proc",
            "/proc",
            "--tmpfs",
            "/run/user",
            "--bind",
        ])
        .arg(options.output.join("tmp"))
        .arg("/tmp")
        .args(["--", program])
        .args(args)
        .current_dir(repo)
        .env("CARGO_BUILD_JOBS", "2")
        .env("RUSTUP_TOOLCHAIN", "1.96.1")
        .env("CARGO_TERM_COLOR", "never")
        .env("CARGO_TARGET_DIR", &options.target)
        .env("XDG_CONFIG_HOME", "/tmp/config")
        .env("XDG_RUNTIME_DIR", "/tmp/runtime")
        .env("TMPDIR", "/tmp")
        .env("SOPHIA_HAGIA_FILE_BIN", &options.binary)
        .env("SOPHIA_HAGIA_BIN", &options.binary)
        .env("SOPHIA_HAGIA_FILE_SHA256", &options.sha256)
        .env("SOPHIA_HAGIA_FILE_EVIDENCE", options.output.join("cases"))
        .stdin(Stdio::null())
        .stdout(stdout)
        .stderr(stderr);
    for name in [
        "DISPLAY",
        "XAUTHORITY",
        "WAYLAND_DISPLAY",
        "WAYLAND_SOCKET",
        "DBUS_SESSION_BUS_ADDRESS",
        "SOPHIA_WM_SOCKET",
        "SOPHIA_WM_9P_SOCKET",
        "SOPHIA_OUTPUT_SOCKET",
        "SOPHIA_SHELL_SOCKET",
        "SOPHIA_DESKTOP_PROFILE",
        "SOPHIA_RUN_REAL_ATOMIC_SCANOUT_SMOKE",
        "HAGIA_POLICY_CANDIDATE",
        "HAGIA_POLICY_CHECKPOINT",
        "HAGIA_POLICY_PROFILE_ACTIVATION",
        "HAGIA_POLICY_FAULT_AFTER",
        "HAGIA_POLICY_TRACE",
    ] {
        command.env_remove(name);
    }
    let status = command
        .status()
        .map_err(|e| format!("start isolated phase: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "WM acceptance phase exited {status}; {}",
            log.display()
        ))
    }
}

pub(crate) fn required_tests(list: &str) -> Result<Vec<String>, String> {
    let mut tests = BTreeSet::new();
    for test in list
        .lines()
        .filter_map(|line| line.strip_suffix(": test"))
        .filter(|line| line.starts_with(PREFIX))
    {
        if !tests.insert(test.to_owned()) {
            return Err(format!("duplicate required test {test}"));
        }
    }
    for required in REQUIRED {
        if tests
            .iter()
            .filter(|name| name.rsplit("::").next() == Some(required))
            .count()
            != 1
        {
            return Err(format!(
                "required normal-Hagia test missing or ambiguous: {required}"
            ));
        }
    }
    Ok(tests.into_iter().collect())
}

pub(crate) fn require_exactly_one(log: &str) -> Result<(), String> {
    if summaries(log)? == [(1, 0, 0)] {
        Ok(())
    } else {
        Err("required owner fixture must report exactly 1 passed, 0 failed, 0 ignored".into())
    }
}

fn require_nonempty(log: &str) -> Result<(), String> {
    let counts = summaries(log)?;
    if counts.iter().any(|c| c.0 > 0) && counts.iter().all(|c| c.1 == 0) {
        Ok(())
    } else {
        Err("protocol phase ran no tests or reported failures".into())
    }
}

fn summaries(log: &str) -> Result<Vec<(usize, usize, usize)>, String> {
    log.lines()
        .filter(|line| line.starts_with("test result: "))
        .map(|line| {
            let line = line
                .strip_prefix("test result: ok. ")
                .ok_or("test phase contains a failed result")?;
            let mut fields = line.split(';');
            let mut count = |label: &str| -> Result<usize, String> {
                fields
                    .next()
                    .and_then(|field| field.trim().strip_suffix(label))
                    .and_then(|value| value.parse().ok())
                    .ok_or_else(|| format!("invalid test summary: {line}"))
            };
            Ok((count(" passed")?, count(" failed")?, count(" ignored")?))
        })
        .collect()
}

pub(crate) fn read_log(path: &Path) -> Result<String, String> {
    let mut text = String::new();
    File::open(path)
        .map_err(|e| e.to_string())?
        .take(LOG_LIMIT + 1)
        .read_to_string(&mut text)
        .map_err(|e| e.to_string())?;
    if text.len() as u64 > LOG_LIMIT {
        return Err(format!("log exceeds acceptance bound: {}", path.display()));
    }
    Ok(text)
}

pub(crate) fn digest(path: &Path) -> Result<String, String> {
    let mut hash = Sha256::new();
    let mut file = File::open(path).map_err(|e| e.to_string())?;
    let mut bytes = [0; 65536];
    loop {
        let count = file.read(&mut bytes).map_err(|e| e.to_string())?;
        if count == 0 {
            break;
        }
        hash.update(&bytes[..count]);
    }
    Ok(format!("{:x}", hash.finalize()))
}

fn identity(repo: &Path, options: &Options) -> Result<Value, String> {
    let git = |args: &[&str]| -> Result<Vec<u8>, String> {
        let result = Command::new("timeout")
            .current_dir(repo)
            .args(["--signal=KILL", "60s", "git"])
            .args(args)
            .output()
            .map_err(|e| e.to_string())?;
        if !result.status.success() {
            return Err("cannot determine source identity".into());
        }
        Ok(result.stdout)
    };
    let status = git(&["status", "--porcelain"])?;
    if status
        .split(|b| *b == b'\n')
        .any(|line| line.starts_with(b"??"))
    {
        return Err("stage or commit untracked source before WM acceptance".into());
    }
    Ok(
        json!({"sophia_commit": String::from_utf8(git(&["rev-parse", "HEAD"])?).map_err(|e| e.to_string())?.trim(),
        "test_overlay": !status.is_empty(), "overlay_manifest_sha256": digest(&options.output.join("overlay.json"))?,
        "diff_sha256": format!("{:x}", Sha256::digest(git(&["diff", "HEAD", "--binary"])?)),
        "runner_sha256": digest(&std::env::current_exe().map_err(|e| e.to_string())?)?,
        "hagia_binary": options.binary, "hagia_sha256": digest(&options.binary)?}),
    )
}

fn write_report(
    options: &Options,
    before: &Value,
    after: Option<&Value>,
    phases: &[Value],
    status: &str,
    error: Option<&str>,
) -> Result<(), String> {
    fs::write(options.output.join("report.json"), serde_json::to_vec_pretty(&json!({
        "schema": 1, "status": status, "error": error, "identity": before, "final_identity": after,
        "phases": phases, "device_hidden": true, "cargo_jobs": 2, "serial_tests": true,
        "source_description": "pinned Sophia base plus Hagia-owned test overlay",
        "wm_transport": ["current-ipc", "9p2000.L"], "output_transport": "current-ipc",
        "native_acceptance": false, "performance_claim": false, "application_execution_claim": false,
        "hash_then_exec_window": true, "descriptor_pinned_exec": false,
        "supplied_facts": ["historical admission", "CPU pixels", "frontend acknowledgements"],
    })).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

pub(crate) fn listed_path<'a>(log: &'a str, entry: &str) -> Result<&'a str, String> {
    let launches: Vec<_> = log
        .lines()
        .filter_map(|line| line.trim_start().strip_prefix("Running "))
        .collect();
    if launches.len() != 1 {
        return Err("required listing must name exactly one test executable".into());
    }
    launches[0]
        .strip_prefix(entry)
        .and_then(|line| line.strip_prefix(" ("))
        .and_then(|line| line.strip_suffix(')'))
        .filter(|path| !path.is_empty())
        .ok_or_else(|| format!("required listing did not launch {entry}"))
}

pub(crate) fn listed_binary(log: &str, target: &Path, entry: &str) -> Result<PathBuf, String> {
    let binary = PathBuf::from(listed_path(log, entry)?)
        .canonicalize()
        .map_err(|e| e.to_string())?;
    if !binary.starts_with(target.canonicalize().map_err(|e| e.to_string())?) {
        return Err("test executable is outside the private target".into());
    }
    Ok(binary)
}
