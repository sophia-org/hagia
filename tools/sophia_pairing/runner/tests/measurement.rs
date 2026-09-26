#[allow(dead_code)]
#[path = "../src/measurement.rs"]
mod measurement;

use measurement::{compare, decode_run, distribution};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs;

// Synthetic timestamps exercise only the report's arithmetic and refusals.
// They are never runtime or transport evidence.
fn capture(wire: &str, count: u64, latency: u64) -> Value {
    let samples: Vec<_> = (0..count)
        .map(|i| {
            let scheduled = i * 1_000_000_000 / 120;
            json!({"offered_sequence":i+1,"request_id":i+2,"transaction":i+3,
            "scheduled_ns":scheduled,"enqueued_ns":scheduled+10,
            "settled_ns":scheduled+10+latency,"outcome":"committed"})
        })
        .collect();
    json!({"schema":1,"status":"complete","boundary":"session_enqueue_to_layout_settlement",
        "wire":wire,"kind":"move","rate_hz":120,"requested_updates":count,
        "offered":count,"admitted":count,"rejected":0,"rejected_settlements":0,"unresolved":0,"coalesced":0,"settled":count,
        "timeouts":0,"disconnects":0,"max_in_flight":1,"max_queue_depth":1,
        "elapsed_ns":count*1_000_000_000/120+latency+10,"samples":samples,"failures":[],
        "unresolved_updates":[],"error":null,"checkpoint_mode":"normal_hagia_enabled_same_filesystem",
        "frontend_acks":"supplied_through_actual_queue_correlation","pixels":"supplied_cpu_observations_no_native_presentation","acceptance":false})
}

fn decode(value: &Value) -> Result<measurement::Run, String> {
    decode_run(&serde_json::to_vec(value).unwrap())
}

fn failed_offer(sequence: u64, reason: Option<&str>) -> Value {
    let scheduled = (sequence - 1) * 1_000_000_000 / 120;
    let mut value = json!({"offered_sequence":sequence,"request_id":null,"transaction":null,
        "scheduled_ns":scheduled,"enqueued_ns":scheduled+10,"observed_ns":scheduled+100});
    if let Some(reason) = reason {
        value["reason"] = json!(reason);
    }
    value
}

fn failed_capture(reason: Option<&str>) -> Value {
    let mut value = capture("9p2000.L", 1, 1000);
    value["status"] = json!("failed");
    value["error"] = json!("test-owned failure evidence");
    value["samples"] = json!([]);
    value["settled"] = json!(0);
    value["max_in_flight"] = json!(0);
    let counter = match reason {
        Some("enqueue_refused") => {
            value["admitted"] = json!(0);
            "rejected"
        }
        Some("timed_out") => "timeouts",
        Some("disconnected") => "disconnects",
        Some("rejected_stale" | "rejected_invalid") => "rejected_settlements",
        Some("measurement_deadline") | None => "unresolved",
        _ => panic!("test reason"),
    };
    value[counter] = json!(1);
    value[if reason.is_some() {
        "failures"
    } else {
        "unresolved_updates"
    }] = json!([failed_offer(1, reason)]);
    value
}

#[test]
fn undispatched_admitted_work_is_unresolved_without_an_invented_request() {
    let value = failed_capture(None);
    let run = decode(&value).unwrap();
    assert_eq!((run.admitted, run.settled, run.max_in_flight), (1, 0, 0));
    let mut settled = capture("9p2000.L", 1, 1000);
    settled["max_in_flight"] = json!(0);
    assert!(decode(&settled).is_err());
}

#[test]
fn overflowing_or_underflowing_counters_cannot_validate_each_other() {
    let mut value = capture("9p2000.L", 1, 1000);
    value["status"] = json!("failed");
    value["coalesced"] = json!(1);
    value["timeouts"] = json!(u64::MAX);
    value["disconnects"] = json!(1);
    // Previously both sides of the conservation comparison became None.
    assert!(decode(&value).unwrap_err().contains("counters exceed"));
    for key in [
        "admitted",
        "rejected",
        "settled",
        "coalesced",
        "timeouts",
        "disconnects",
        "rejected_settlements",
        "unresolved",
    ] {
        let mut value = capture("9p2000.L", 1, 1000);
        value[key] = json!(u64::MAX);
        assert!(
            decode(&value).unwrap_err().contains("counters exceed"),
            "{key}"
        );
    }
}

#[test]
fn failed_and_unresolved_records_share_timing_and_nullable_identity_bounds() {
    for reason in [None, Some("measurement_deadline")] {
        let value = failed_capture(reason);
        let records = if reason.is_some() {
            "failures"
        } else {
            "unresolved_updates"
        };
        assert!(decode(&value).is_ok());
        for (key, invalid) in [
            ("offered_sequence", json!(0)),
            ("offered_sequence", json!(2)),
            ("offered_sequence", json!(u64::MAX)),
            ("scheduled_ns", json!(1)),
            ("enqueued_ns", json!(u64::MAX)),
            ("observed_ns", json!(0)),
            ("observed_ns", json!(u64::MAX)),
            ("request_id", json!(0)),
            ("request_id", json!("1")),
            ("transaction", json!(-1)),
            ("transaction", json!(false)),
        ] {
            let mut invalid_run = value.clone();
            invalid_run[records][0][key] = invalid;
            assert!(decode(&invalid_run).is_err(), "{records}.{key}");
        }
        let mut identified = value;
        identified[records][0]["request_id"] = json!(1);
        identified[records][0]["transaction"] = json!(2);
        assert!(decode(&identified).is_ok());
    }
}

#[test]
fn failure_reason_counts_match_their_own_counters() {
    for reason in [
        "enqueue_refused",
        "timed_out",
        "disconnected",
        "rejected_stale",
        "rejected_invalid",
        "measurement_deadline",
    ] {
        let mut value = failed_capture(Some(reason));
        assert!(decode(&value).is_ok(), "{reason}");
        value["failures"][0]["reason"] = json!(if reason == "timed_out" {
            "measurement_deadline"
        } else {
            "timed_out"
        });
        assert!(
            decode(&value).unwrap_err().contains("failure reasons"),
            "{reason}"
        );
        value["failures"][0]["reason"] = json!("unknown_terminal_status");
        assert!(decode(&value).is_err());
    }
    let mut missing = failed_capture(None);
    missing["unresolved_updates"] = json!([]);
    assert!(decode(&missing).unwrap_err().contains("failure reasons"));
}

#[test]
fn offered_identities_are_unique_across_all_outcome_collections() {
    let mut value = capture("9p2000.L", 3, 1000);
    value["status"] = json!("failed");
    value["samples"].as_array_mut().unwrap().truncate(1);
    value["settled"] = json!(1);
    value["unresolved"] = json!(2);
    value["unresolved_updates"] = json!([failed_offer(2, None)]);
    value["failures"] = json!([failed_offer(3, Some("measurement_deadline"))]);
    assert!(decode(&value).is_ok());
    for records in ["failures", "unresolved_updates"] {
        let mut duplicate = value.clone();
        let reason = (records == "failures").then_some("measurement_deadline");
        duplicate[records][0] = failed_offer(1, reason);
        assert!(decode(&duplicate).is_err(), "success versus {records}");
    }
    let mut duplicate = value.clone();
    duplicate["failures"][0] = failed_offer(2, Some("measurement_deadline"));
    assert!(decode(&duplicate).is_err(), "failure versus unresolved");
    for records in ["failures", "unresolved_updates"] {
        let mut duplicate = value.clone();
        let reason = (records == "failures").then_some("measurement_deadline");
        duplicate["failures"] = json!([]);
        duplicate["unresolved_updates"] = json!([]);
        duplicate[records] = json!([failed_offer(2, reason), failed_offer(2, reason)]);
        assert!(decode(&duplicate).is_err(), "duplicate within {records}");
    }
}

#[test]
fn percentiles_use_nearest_rank_and_never_hide_the_maximum() {
    let value = distribution((1..=100).rev()).unwrap();
    assert_eq!(
        (value.p50, value.p95, value.p99, value.max),
        (50, 95, 99, 100)
    );
    let one = distribution([u64::MAX]).unwrap();
    assert_eq!(one.p99, u64::MAX);
    assert!(distribution([]).is_err());
}

#[test]
fn coalesced_updates_are_counted_without_fabricated_settlements() {
    let mut value = capture("current-ipc", 3, 1000);
    value["samples"].as_array_mut().unwrap().remove(1);
    value["coalesced"] = json!(1);
    value["settled"] = json!(2);
    let run = decode(&value).unwrap();
    assert_eq!(
        (run.offered, run.admitted, run.coalesced, run.settled),
        (3, 3, 1, 2)
    );
    value["admitted"] = json!(2);
    assert!(decode(&value).is_err());
    value["admitted"] = json!(3);
    value["samples"][0]["outcome"] = json!("timed_out");
    assert!(decode(&value).is_err());
}

#[test]
fn malformed_identity_schedule_or_counts_cannot_improve_a_result() {
    for (field, value) in [
        ("request_id", 0),
        ("offered_sequence", 0),
        ("scheduled_ns", 1),
        ("enqueued_ns", u64::MAX),
        ("settled_ns", 0),
    ] {
        let mut run = capture("9p2000.L", 2, 1000);
        run["samples"][0][field] = json!(value);
        assert!(decode(&run).is_err(), "{field}");
    }
    for (field, value) in [
        ("settled", 1),
        ("coalesced", 1),
        ("rejected", 1),
        ("max_in_flight", 2),
        ("max_queue_depth", 2),
        ("offered", 1),
    ] {
        let mut run = capture("9p2000.L", 2, 1000);
        run[field] = json!(value);
        assert!(decode(&run).is_err(), "{field}");
    }
    let mut run = capture("9p2000.L", 2, 1000);
    run["samples"][1]["transaction"] = run["samples"][0]["transaction"].clone();
    assert!(decode(&run).is_err());
    run = capture("9p2000.L", 2, 1000);
    run["unexpected"] = json!(true);
    assert!(decode(&run).is_err());
    let mut bytes = serde_json::to_vec(&capture("9p2000.L", 2, 1000)).unwrap();
    bytes.push(b'x');
    assert!(decode_run(&bytes).is_err());
}

#[test]
fn budgets_are_inclusive_and_each_pair_must_pass() {
    let ipc = decode(&capture("current-ipc", 100, 1_000_000)).unwrap();
    let mut values = capture("9p2000.L", 100, 2_000_000);
    // p95 is exactly +1 ms; p99 exactly +2 ms.
    for i in 95..100 {
        values["samples"][i]["settled_ns"] =
            json!(values["samples"][i]["enqueued_ns"].as_u64().unwrap() + 3_000_000);
    }
    assert_eq!(
        compare(&ipc, &decode(&values).unwrap()).unwrap()["budgets_pass"],
        true
    );
    values["samples"][94]["settled_ns"] =
        json!(values["samples"][94]["enqueued_ns"].as_u64().unwrap() + 2_000_001);
    assert_eq!(
        compare(&ipc, &decode(&values).unwrap()).unwrap()["budgets_pass"],
        false
    );
    let equal_slow = decode(&capture("current-ipc", 100, 8_333_334)).unwrap();
    let slow_files = decode(&capture("9p2000.L", 100, 8_333_334)).unwrap();
    let result = compare(&equal_slow, &slow_files).unwrap();
    assert_eq!(
        result["refusals"],
        json!(["file p99 exceeds one offered interval"])
    );
}

struct Directory(std::path::PathBuf);
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

const LOAD_RECIPE: &str = "synthetic load evidence for report validation only";

fn load_capture(workers: u64) -> Value {
    json!({"schema":1,"recipe":LOAD_RECIPE,"workers":workers,
        "blocks_per_worker":vec![1; workers as usize],"elapsed_ns":1000})
}

fn campaign() -> (Directory, Value) {
    let path = std::env::temp_dir().join(format!(
        "hagia-measure-report-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir(&path).unwrap();
    let mut runs = Vec::new();
    for (i, wire) in ["current-ipc", "9p2000.L"].iter().enumerate() {
        let name = format!("run-{i}.json");
        let bytes = serde_json::to_vec(&capture(wire, 4, 1000)).unwrap();
        fs::write(path.join(&name), &bytes).unwrap();
        let load_name = format!("load-{i}.json");
        let load_bytes = serde_json::to_vec(&load_capture(0)).unwrap();
        fs::write(path.join(&load_name), &load_bytes).unwrap();
        runs.push(json!({"ordinal":i+1,"pair":1,"load":"idle","path":name,
            "sha256":format!("{:x}",Sha256::digest(&bytes)),"load_path":load_name,
            "load_sha256":format!("{:x}",Sha256::digest(&load_bytes))}));
    }
    let hash = "a".repeat(64);
    let manifest = json!({"schema":1,"mode":"smoke","identity":{"sophia_commit":"a".repeat(40),
        "hagia_sha256":hash,"overlay_sha256":hash,"test_binary_sha256":hash,"workload_sha256":hash,
        "machine_sha256":hash,"load_recipe_sha256":format!("{:x}",Sha256::digest(LOAD_RECIPE.as_bytes())),
        "build_mode":"release"},"runs":runs});
    (Directory(path), manifest)
}

fn replace_load(directory: &Directory, manifest: &mut Value, index: usize, value: &Value) {
    let bytes = serde_json::to_vec(value).unwrap();
    fs::write(
        directory
            .0
            .join(manifest["runs"][index]["load_path"].as_str().unwrap()),
        &bytes,
    )
    .unwrap();
    manifest["runs"][index]["load_sha256"] = json!(format!("{:x}", Sha256::digest(&bytes)));
}

fn report(directory: &Directory, manifest: &Value) -> Result<Value, String> {
    let path = directory.0.join("manifest.json");
    fs::write(&path, serde_json::to_vec(manifest).unwrap()).unwrap();
    measurement::report(&path)
}

#[test]
fn small_complete_capture_is_only_a_smoke_report() {
    let (dir, mut manifest) = campaign();
    let result = report(&dir, &manifest).unwrap();
    assert_eq!(result["budgets_pass"], true);
    assert_eq!(result["latency_gate_pass"], false);
    manifest["mode"] = json!("acceptance");
    assert!(
        report(&dir, &manifest)
            .unwrap_err()
            .contains("10000 admitted")
    );
}

#[test]
fn manifest_requires_adjacent_alternating_pairs_and_pinned_bytes() {
    let (dir, manifest) = campaign();
    let mut invalid = manifest.clone();
    invalid["runs"][1]["ordinal"] = json!(3);
    assert!(report(&dir, &invalid).is_err());
    invalid = manifest.clone();
    invalid["runs"][0]["pair"] = json!(2);
    invalid["runs"][1]["pair"] = json!(2);
    assert!(report(&dir, &invalid).unwrap_err().contains("alternate"));
    invalid = manifest.clone();
    invalid["runs"][1]["sha256"] = json!("b".repeat(64));
    assert!(report(&dir, &invalid).unwrap_err().contains("digest"));
    invalid = manifest.clone();
    invalid["runs"].as_array_mut().unwrap().pop();
    assert!(report(&dir, &invalid).is_err());
    fs::write(dir.0.join("run-1.json"), b"{}").unwrap();
    assert!(report(&dir, &manifest).is_err());
}

#[test]
fn every_cpu_run_requires_two_progressing_workers_and_the_pinned_recipe() {
    let (dir, mut manifest) = campaign();
    for index in 0..2 {
        manifest["runs"][index]["load"] = json!("cpu");
        replace_load(&dir, &mut manifest, index, &load_capture(2));
    }
    assert!(report(&dir, &manifest).is_ok());
    for (key, invalid) in [
        ("workers", json!(0)),
        ("workers", json!(1)),
        ("workers", json!(3)),
        ("blocks_per_worker", json!([])),
        ("blocks_per_worker", json!([1])),
        ("blocks_per_worker", json!([1, 0])),
        ("blocks_per_worker", json!([1, "2"])),
        ("blocks_per_worker", json!([1, 2, 3])),
        ("elapsed_ns", json!(0)),
        ("elapsed_ns", json!(-1)),
        ("schema", json!(2)),
        ("recipe", json!("different recipe")),
    ] {
        let mut invalid_manifest = manifest.clone();
        let mut load = load_capture(2);
        load[key] = invalid;
        replace_load(&dir, &mut invalid_manifest, 1, &load);
        assert!(report(&dir, &invalid_manifest).is_err(), "{key}");
    }
}

#[test]
fn idle_load_evidence_has_no_workers_or_progress_entries() {
    let (dir, manifest) = campaign();
    assert!(report(&dir, &manifest).is_ok());
    for load in [load_capture(2), {
        let mut value = load_capture(0);
        value["blocks_per_worker"] = json!([1]);
        value
    }] {
        let mut invalid = manifest.clone();
        replace_load(&dir, &mut invalid, 0, &load);
        assert!(report(&dir, &invalid).is_err());
    }
}

#[test]
fn load_artifacts_are_bounded_unique_inside_the_campaign_and_digest_bound() {
    let (dir, manifest) = campaign();
    let mut invalid = manifest.clone();
    invalid["runs"][0]["load_sha256"] = json!("b".repeat(64));
    assert!(report(&dir, &invalid).unwrap_err().contains("digest"));
    invalid = manifest.clone();
    invalid["runs"][1]["load_path"] = invalid["runs"][0]["load_path"].clone();
    assert!(report(&dir, &invalid).unwrap_err().contains("repeated"));
    let (outside, _) = campaign();
    invalid = manifest.clone();
    invalid["runs"][0]["load_path"] = json!(outside.0.join("load-0.json"));
    assert!(report(&dir, &invalid).unwrap_err().contains("escapes"));
    invalid = manifest.clone();
    invalid["runs"][0]
        .as_object_mut()
        .unwrap()
        .remove("load_path");
    assert!(report(&dir, &invalid).is_err());
    let oversized = vec![b' '; 64 * 1024 + 1];
    fs::write(dir.0.join("load-0.json"), &oversized).unwrap();
    invalid = manifest.clone();
    invalid["runs"][0]["load_sha256"] = json!(format!("{:x}", Sha256::digest(&oversized)));
    assert!(report(&dir, &invalid).unwrap_err().contains("byte bound"));
    fs::write(dir.0.join("load-0.json"), b"{}").unwrap();
    assert!(report(&dir, &manifest).unwrap_err().contains("digest"));
}
