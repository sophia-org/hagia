//! Serial, isolated measurement orchestration. Workload and load are recorded
//! before launch; a smoke is deliberately too small to satisfy the gate.
use crate::acceptance::{self, Options};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::{
    Arc, Barrier,
    atomic::{AtomicBool, Ordering},
};
use std::time::Instant;

const TEST: &str = "normal_hagia_session_drag_measurement";
const LOAD: &str = "v1: two nice-19 CPU workers; wrapping xorshift/multiply u64 blocks of 16384 iterations; seeds 1 and 2; start barrier before fixture spawn; stop after fixture exit; no affinity pin";

pub(crate) fn exercise(
    repo: &Path,
    options: &Options,
    deadline: Instant,
    binary: &Path,
    binary_hash: &str,
    identity: &Value,
    phases: &mut Vec<Value>,
) -> Result<(), String> {
    let listing = acceptance::read_log(&options.output.join("required-list.log"))?;
    let test = crate::legacy::named_test(&listing, TEST)?;
    let mode = options
        .measure
        .as_deref()
        .ok_or("measurement mode missing")?;
    let updates = if mode == "smoke" { 16 } else { 10_000 };
    let pair_count = if mode == "smoke" { 1 } else { 5 };
    let machine = json!({"cpuinfo":fs::read_to_string("/proc/cpuinfo").map_err(|e|e.to_string())?,
        "kernel":fs::read_to_string("/proc/version").map_err(|e|e.to_string())?,
        "cpu_affinity":fs::read_to_string("/proc/self/status").map_err(|e|e.to_string())?.lines()
            .find(|line|line.starts_with("Cpus_allowed_list:")).ok_or("missing CPU affinity")?,
        "nice":19,"cargo_jobs":2,"load":LOAD,"measurement_thread":"Session fixture owner",
        "physical_input":false,"native_retirement":false});
    let machine_bytes = serde_json::to_vec_pretty(&machine).map_err(|e| e.to_string())?;
    fs::write(
        options.output.join("measurement-machine.json"),
        &machine_bytes,
    )
    .map_err(|e| e.to_string())?;
    let mut manifest = json!({"schema":1,"mode":mode,"identity":{
        "sophia_commit":identity["sophia_commit"],"hagia_sha256":identity["hagia_sha256"],
        "overlay_sha256":identity["overlay_manifest_sha256"],"test_binary_sha256":binary_hash,
        "workload_sha256":format!("{:x}",Sha256::digest(include_bytes!("../../fixtures/policy_hagia_drag_measurement.rs"))),
        "machine_sha256":format!("{:x}",Sha256::digest(&machine_bytes)),
        "load_recipe_sha256":format!("{:x}",Sha256::digest(LOAD.as_bytes())),
        "build_mode":if mode == "smoke" { "debug" } else { "release" }},"runs":[]});
    let manifest_path = options.output.join("measurement-manifest.json");
    write_json(&manifest_path, &manifest)?;
    let runner = std::env::current_exe().map_err(|e| e.to_string())?;
    let mut ordinal = 0;
    for kind in ["move", "resize"] {
        for rate in [60, 120] {
            for load in ["idle", "cpu"] {
                for pair in 1..=pair_count {
                    let wires = if pair % 2 == 1 {
                        ["current-ipc", "9p2000.L"]
                    } else {
                        ["9p2000.L", "current-ipc"]
                    };
                    for wire in wires {
                        ordinal += 1;
                        if acceptance::digest(binary)? != binary_hash {
                            return Err("measurement test binary changed before launch".into());
                        }
                        let relative = format!("cases/measure-{ordinal:02}");
                        let evidence = options.output.join(&relative);
                        fs::create_dir(&evidence).map_err(|e| e.to_string())?;
                        let log = options.output.join(format!("measure-{ordinal:02}.log"));
                        let start = Instant::now();
                        let environment = [
                            (
                                "SOPHIA_HAGIA_FILE_EVIDENCE",
                                evidence.to_string_lossy().into_owned(),
                            ),
                            ("HAGIA_MEASURE_WIRE", wire.to_owned()),
                            ("HAGIA_MEASURE_KIND", kind.to_owned()),
                            ("HAGIA_MEASURE_RATE_HZ", rate.to_string()),
                            ("HAGIA_MEASURE_UPDATES", updates.to_string()),
                        ];
                        // The load threads live inside the same PID namespace and
                        // outer deadline as the fixture; neither can outlive it.
                        let result = acceptance::stage_with_env(
                            repo,
                            options,
                            deadline,
                            runner.to_str().ok_or("runner path must be UTF-8")?,
                            &[
                                "--measurement-worker",
                                if load == "cpu" { "2" } else { "0" },
                                evidence
                                    .join("load.json")
                                    .to_str()
                                    .ok_or("evidence path must be UTF-8")?,
                                binary.to_str().ok_or("test path must be UTF-8")?,
                                &test,
                            ],
                            &log,
                            &environment,
                        )
                        .and_then(|()| acceptance::read_log(&log))
                        .and_then(|text| acceptance::require_exactly_one(&text));
                        let binary_after = acceptance::digest(binary);
                        let wire_label = if wire == "current-ipc" {
                            "ipc"
                        } else {
                            "files"
                        };
                        let path =
                            format!("{relative}/drag-{kind}-{rate}-{wire_label}/measurement.json");
                        let capture = (|| {
                            let bytes = crate::measurement::read_bounded(
                                &options.output.join(&path),
                                32 * 1024 * 1024,
                            )?;
                            let load_path = format!("{relative}/load.json");
                            let load_bytes = crate::measurement::read_bounded(
                                &options.output.join(&load_path),
                                64 * 1024,
                            )?;
                            // Index exact raw bytes before judging them. An interrupted
                            // fixture may honestly retain inconsistent partial counters.
                            manifest["runs"].as_array_mut().unwrap().push(json!({"ordinal":ordinal,"pair":pair,
                                "load":load,"path":path,"sha256":format!("{:x}",Sha256::digest(&bytes)),
                                "load_path":load_path,"load_sha256":format!("{:x}",Sha256::digest(&load_bytes))}));
                            write_json(&manifest_path, &manifest)?;
                            let run = crate::measurement::decode_run(&bytes)?;
                            if run.wire != wire
                                || run.kind != kind
                                || run.rate_hz != rate
                                || run.requested_updates != updates
                            {
                                return Err(
                                    "fixture capture differs from commanded workload".to_owned()
                                );
                            }
                            Ok(())
                        })();
                        phases.push(json!({"name":format!("measure-{ordinal:02}"),"log":log,
                            "kind":kind,"rate_hz":rate,"load":load,"pair":pair,"wire":wire,
                            "elapsed_msec":start.elapsed().as_millis(),"error":result.as_ref().err(),
                            "capture_error":capture.as_ref().err(),"binary_after":binary_after.as_ref().ok(),
                            "binary_identity_error":binary_after.as_ref().err()}));
                        write_json(
                            &options.output.join("measurement-phases.json"),
                            &json!(phases),
                        )?;
                        // Preserve the first process failure after collecting identities
                        // and partial capture evidence, even if parsing also refused.
                        result?;
                        if binary_after? != binary_hash {
                            return Err("measurement test binary changed during case".into());
                        }
                        capture?;
                    }
                }
            }
        }
    }
    let report = crate::measurement::report(&manifest_path)?;
    write_json(&options.output.join("measurement-report.json"), &report)?;
    if report["budgets_pass"] != true {
        return Err("measurement exceeded a predeclared budget; captures retained".into());
    }
    Ok(())
}

fn write_json(path: &Path, value: &Value) -> Result<(), String> {
    fs::write(
        path,
        serde_json::to_vec_pretty(value).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())
}

/// Internal subprocess mode, run only inside the caller's isolated stage.
pub fn worker(args: &[String]) -> Result<(), String> {
    let [workers, report, binary, test] = args else {
        return Err("invalid measurement worker arguments".into());
    };
    let workers: usize = workers.parse().map_err(|_| "invalid load worker count")?;
    if ![0, 2].contains(&workers) {
        return Err("load workers must be zero or two".into());
    }
    let stopping = Arc::new(AtomicBool::new(false));
    let barrier = Arc::new(Barrier::new(workers + 1));
    let start = Instant::now();
    let (status, counts) = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..workers)
            .map(|id| {
                let stopping = &stopping;
                let barrier = &barrier;
                scope.spawn(move || {
                    let mut value = id as u64 + 1;
                    let mut blocks = 0_u64;
                    barrier.wait();
                    while !stopping.load(Ordering::Relaxed) {
                        for _ in 0..16384 {
                            value ^= value << 13;
                            value ^= value >> 7;
                            value ^= value << 17;
                            value = value.wrapping_mul(0x2545_f491_4f6c_dd1d);
                        }
                        std::hint::black_box(value);
                        blocks = blocks.saturating_add(1);
                    }
                    blocks
                })
            })
            .collect();
        barrier.wait();
        let status = Command::new(binary)
            .args([
                test,
                "--exact",
                "--ignored",
                "--nocapture",
                "--test-threads=1",
            ])
            .status();
        stopping.store(true, Ordering::Relaxed);
        let counts: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        (status, counts)
    });
    write_json(
        Path::new(report),
        &json!({"schema":1,"recipe":LOAD,"workers":workers,
        "blocks_per_worker":counts,"elapsed_ns":start.elapsed().as_nanos()}),
    )?;
    let status = status.map_err(|e| e.to_string())?;
    if !status.success() {
        return Err(format!("measurement test exited {status}"));
    }
    if counts.contains(&0) {
        return Err("CPU load worker made no progress".into());
    }
    Ok(())
}
