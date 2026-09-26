//! Offline evaluation of owner-timestamped measurements. Hashes bind captures;
//! they do not attest their producer or turn a smoke run into acceptance.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::File;
use std::io::Read;
use std::path::Path;

const CAPTURE_LIMIT: u64 = 32 * 1024 * 1024;
const LOAD_LIMIT: u64 = 64 * 1024;
const MAX_UPDATES: u64 = 100_000;
const BOUNDARY: &str = "session_enqueue_to_layout_settlement";

#[derive(Debug, PartialEq)]
pub struct Sample {
    pub offered_sequence: u64,
    pub request_id: u64,
    pub transaction: u64,
    pub scheduled_ns: u64,
    pub enqueued_ns: u64,
    pub settled_ns: u64,
}

#[derive(Debug)]
pub struct Run {
    pub status: String,
    pub wire: String,
    pub kind: String,
    pub rate_hz: u64,
    pub requested_updates: u64,
    pub offered: u64,
    pub admitted: u64,
    pub rejected: u64,
    pub rejected_settlements: u64,
    pub unresolved: u64,
    pub coalesced: u64,
    pub settled: u64,
    pub timeouts: u64,
    pub disconnects: u64,
    pub max_in_flight: u64,
    pub max_queue_depth: u64,
    pub elapsed_ns: u64,
    pub samples: Vec<Sample>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Distribution {
    pub p50: u64,
    pub p95: u64,
    pub p99: u64,
    pub max: u64,
}

fn fields(value: &Value, expected: &[&str]) -> Result<(), String> {
    let object = value.as_object().ok_or("expected measurement object")?;
    if object.len() != expected.len() || expected.iter().any(|key| !object.contains_key(*key)) {
        return Err(format!("measurement fields must be exactly {expected:?}"));
    }
    Ok(())
}

fn number(value: &Value, name: &str) -> Result<u64, String> {
    value[name]
        .as_u64()
        .ok_or_else(|| format!("invalid unsigned {name}"))
}

fn choice(value: &Value, name: &str, choices: &[&str]) -> Result<String, String> {
    value[name]
        .as_str()
        .filter(|s| choices.contains(s))
        .map(str::to_owned)
        .ok_or_else(|| format!("invalid {name}"))
}

fn offered_timing(value: &Value, run: &Run, end: &str) -> Result<u64, String> {
    let sequence = number(value, "offered_sequence")?;
    if sequence == 0
        || sequence > run.offered
        || number(value, "scheduled_ns")? != (sequence - 1) * 1_000_000_000 / run.rate_hz
        || number(value, "enqueued_ns")? < number(value, "scheduled_ns")?
        || number(value, end)? < number(value, "enqueued_ns")?
        || number(value, end)? > run.elapsed_ns
    {
        return Err("invalid offer identity, absolute schedule or monotonic timing".into());
    }
    Ok(sequence)
}

fn failed_offer(value: &Value, run: &Run, seen: &mut BTreeSet<u64>) -> Result<(), String> {
    let sequence = offered_timing(value, run, "observed_ns")?;
    for key in ["request_id", "transaction"] {
        if !value[key].is_null() && value[key].as_u64().is_none_or(|id| id == 0) {
            return Err("invalid optional failure identity".into());
        }
    }
    if !seen.insert(sequence) {
        return Err("offered identity appears in more than one outcome".into());
    }
    Ok(())
}

pub fn decode_run(bytes: &[u8]) -> Result<Run, String> {
    if bytes.len() as u64 > CAPTURE_LIMIT {
        return Err("measurement capture too large".into());
    }
    let value: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    fields(
        &value,
        &[
            "schema",
            "status",
            "boundary",
            "wire",
            "kind",
            "rate_hz",
            "requested_updates",
            "offered",
            "admitted",
            "rejected",
            "rejected_settlements",
            "unresolved",
            "coalesced",
            "settled",
            "timeouts",
            "disconnects",
            "max_in_flight",
            "max_queue_depth",
            "elapsed_ns",
            "samples",
            "failures",
            "unresolved_updates",
            "error",
            "checkpoint_mode",
            "frontend_acks",
            "pixels",
            "acceptance",
        ],
    )?;
    if number(&value, "schema")? != 1 || value["boundary"] != BOUNDARY {
        return Err("unsupported measurement schema or timing boundary".into());
    }
    if value["checkpoint_mode"] != "normal_hagia_enabled_same_filesystem"
        || value["frontend_acks"] != "supplied_through_actual_queue_correlation"
        || value["pixels"] != "supplied_cpu_observations_no_native_presentation"
        || value["acceptance"] != false
        || (!value["error"].is_null() && !value["error"].is_string())
    {
        return Err("unknown workload qualification or checkpoint mode".into());
    }
    let mut run = Run {
        status: choice(&value, "status", &["complete", "failed"])?,
        wire: choice(&value, "wire", &["current-ipc", "9p2000.L"])?,
        kind: choice(&value, "kind", &["move", "resize"])?,
        rate_hz: number(&value, "rate_hz")?,
        requested_updates: number(&value, "requested_updates")?,
        offered: number(&value, "offered")?,
        admitted: number(&value, "admitted")?,
        rejected: number(&value, "rejected")?,
        rejected_settlements: number(&value, "rejected_settlements")?,
        unresolved: number(&value, "unresolved")?,
        coalesced: number(&value, "coalesced")?,
        settled: number(&value, "settled")?,
        timeouts: number(&value, "timeouts")?,
        disconnects: number(&value, "disconnects")?,
        max_in_flight: number(&value, "max_in_flight")?,
        max_queue_depth: number(&value, "max_queue_depth")?,
        elapsed_ns: number(&value, "elapsed_ns")?,
        samples: Vec::new(),
    };
    if ![60, 120].contains(&run.rate_hz) || !(1..=MAX_UPDATES).contains(&run.requested_updates) {
        return Err("rate must be 60 or 120 Hz; updates must be 1..100000".into());
    }
    let samples = value["samples"].as_array().ok_or("missing samples")?;
    // Every sum below has at most six terms, each bounded by MAX_UPDATES.
    // An overflow must never make two failed checked operations compare equal.
    if run.offered > run.requested_updates
        || [
            run.admitted,
            run.rejected,
            run.settled,
            run.coalesced,
            run.timeouts,
            run.disconnects,
            run.rejected_settlements,
            run.unresolved,
        ]
        .iter()
        .any(|count| *count > run.offered)
    {
        return Err("measurement counters exceed offered updates".into());
    }
    if (run.status == "complete" && run.offered != run.requested_updates)
        || run.admitted + run.rejected != run.offered
        || run.settled != samples.len() as u64
        || run.settled > run.admitted
        || run.admitted
            != run.settled
                + run.coalesced
                + run.timeouts
                + run.disconnects
                + run.rejected_settlements
                + run.unresolved
        || run.max_in_flight > 1
        || (run.settled > 0 && run.max_in_flight != 1)
        || run.max_queue_depth > 1
    {
        return Err(
            "incoherent offered/admitted/coalesced/settled counts or request slot bound".into(),
        );
    }
    let failures = value["failures"]
        .as_array()
        .ok_or("failures must be an array")?;
    let unresolved = value["unresolved_updates"]
        .as_array()
        .ok_or("unresolved_updates must be an array")?;
    if failures.len() as u64 > run.offered || unresolved.len() as u64 > run.offered {
        return Err("failure records exceed offered updates".into());
    }
    if run.status == "complete"
        && (!failures.is_empty()
            || run.rejected != 0
            || run.timeouts != 0
            || run.disconnects != 0
            || run.rejected_settlements != 0
            || run.unresolved != 0
            || !unresolved.is_empty()
            || !value["error"].is_null())
    {
        return Err("complete capture contains failed or unresolved work".into());
    }
    let mut seen = BTreeSet::new();
    let mut failure_counts = [0_u64; 5];
    failure_counts[4] = unresolved.len() as u64;
    for entry in unresolved {
        fields(
            entry,
            &[
                "offered_sequence",
                "request_id",
                "transaction",
                "scheduled_ns",
                "enqueued_ns",
                "observed_ns",
            ],
        )?;
        failed_offer(entry, &run, &mut seen)?;
    }
    for failure in failures {
        fields(
            failure,
            &[
                "offered_sequence",
                "reason",
                "request_id",
                "transaction",
                "scheduled_ns",
                "enqueued_ns",
                "observed_ns",
            ],
        )?;
        let reason = choice(
            failure,
            "reason",
            &[
                "enqueue_refused",
                "timed_out",
                "disconnected",
                "rejected_stale",
                "rejected_invalid",
                "measurement_deadline",
            ],
        )?;
        let category = match reason.as_str() {
            "enqueue_refused" => 0,
            "timed_out" => 1,
            "disconnected" => 2,
            "rejected_stale" | "rejected_invalid" => 3,
            "measurement_deadline" => 4,
            _ => unreachable!("validated failure reason"),
        };
        failure_counts[category] += 1;
        failed_offer(failure, &run, &mut seen)?;
    }
    if failure_counts
        != [
            run.rejected,
            run.timeouts,
            run.disconnects,
            run.rejected_settlements,
            run.unresolved,
        ]
    {
        return Err("failure reasons disagree with measurement counters".into());
    }
    let mut prior = (0, 0, 0);
    for value in samples {
        fields(
            value,
            &[
                "offered_sequence",
                "request_id",
                "transaction",
                "scheduled_ns",
                "enqueued_ns",
                "settled_ns",
                "outcome",
            ],
        )?;
        if value["outcome"] != "committed" {
            return Err("only committed settlements may enter latency percentiles".into());
        }
        let sample = Sample {
            offered_sequence: number(value, "offered_sequence")?,
            request_id: number(value, "request_id")?,
            transaction: number(value, "transaction")?,
            scheduled_ns: number(value, "scheduled_ns")?,
            enqueued_ns: number(value, "enqueued_ns")?,
            settled_ns: number(value, "settled_ns")?,
        };
        offered_timing(value, &run, "settled_ns")?;
        if sample.offered_sequence <= prior.0
            || sample.request_id <= prior.1
            || sample.transaction <= prior.2
            || !seen.insert(sample.offered_sequence)
        {
            return Err("invalid sample identity, absolute schedule or monotonic timing".into());
        }
        prior = (
            sample.offered_sequence,
            sample.request_id,
            sample.transaction,
        );
        run.samples.push(sample);
    }
    Ok(run)
}

pub fn distribution(values: impl IntoIterator<Item = u64>) -> Result<Distribution, String> {
    let mut values: Vec<_> = values.into_iter().collect();
    if values.is_empty() {
        return Err("no settled latency samples".into());
    }
    values.sort_unstable();
    // Nearest rank, with integer arithmetic: no interpolation or float rounding.
    let percentile = |percent: usize| values[(values.len() * percent).div_ceil(100) - 1];
    Ok(Distribution {
        p50: percentile(50),
        p95: percentile(95),
        p99: percentile(99),
        max: *values.last().unwrap(),
    })
}

fn stats(value: Distribution) -> Value {
    json!({"p50_ns":value.p50,"p95_ns":value.p95,"p99_ns":value.p99,"max_ns":value.max})
}

pub fn compare(ipc: &Run, files: &Run) -> Result<Value, String> {
    if ipc.wire != "current-ipc"
        || files.wire != "9p2000.L"
        || ipc.kind != files.kind
        || ipc.rate_hz != files.rate_hz
        || ipc.requested_updates != files.requested_updates
    {
        return Err("paired workloads differ".into());
    }
    let ipc_latency = distribution(ipc.samples.iter().map(|s| s.settled_ns - s.enqueued_ns))?;
    let files_latency = distribution(files.samples.iter().map(|s| s.settled_ns - s.enqueued_ns))?;
    let mut refusals = Vec::new();
    if ipc.status != "complete" || files.status != "complete" {
        refusals.push("incomplete measurement run");
    }
    if files_latency.p95 > ipc_latency.p95.saturating_add(1_000_000) {
        refusals.push("p95 regression exceeds 1 ms");
    }
    if files_latency.p99 > ipc_latency.p99.saturating_add(2_000_000) {
        refusals.push("p99 regression exceeds 2 ms");
    }
    if files_latency.p99 > 1_000_000_000 / files.rate_hz {
        refusals.push("file p99 exceeds one offered interval");
    }
    if [ipc, files]
        .iter()
        .any(|r| r.timeouts != 0 || r.disconnects != 0)
    {
        refusals.push("timeout or disconnect");
    }
    if ipc.rejected != 0 || files.rejected != 0 {
        refusals.push("offered update rejected");
    }
    if ipc.rejected_settlements != 0
        || files.rejected_settlements != 0
        || ipc.unresolved != 0
        || files.unresolved != 0
    {
        refusals.push("rejected or unresolved layout settlement");
    }
    if ipc.coalesced != files.coalesced
        || ipc.settled != files.settled
        || ipc
            .samples
            .iter()
            .map(|s| s.offered_sequence)
            .ne(files.samples.iter().map(|s| s.offered_sequence))
    {
        refusals.push("different retained updates; survivor percentiles are not equivalent work");
    }
    let describe = |run: &Run, latency: Distribution| -> Result<Value, String> {
        Ok(
            json!({"wire":run.wire,"offered":run.offered,"admitted":run.admitted,
            "rejected":run.rejected,"rejected_settlements":run.rejected_settlements,"unresolved":run.unresolved,
            "coalesced":run.coalesced,"settled":run.settled,"timeouts":run.timeouts,
            "disconnects":run.disconnects,"max_in_flight":run.max_in_flight,"max_queue_depth":run.max_queue_depth,
            "elapsed_ns":run.elapsed_ns,"latency":stats(latency),
            "enqueue_lateness":stats(distribution(run.samples.iter().map(|s| s.enqueued_ns - s.scheduled_ns))?)}),
        )
    };
    Ok(
        json!({"kind":ipc.kind,"rate_hz":ipc.rate_hz,"budgets_pass":refusals.is_empty(),
        "refusals":refusals,"current_ipc":describe(ipc,ipc_latency)?,"files":describe(files,files_latency)?}),
    )
}

pub(crate) fn read_bounded(path: &Path, limit: u64) -> Result<Vec<u8>, String> {
    let file = File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    if !file.metadata().map_err(|e| e.to_string())?.is_file() {
        return Err("capture must be a regular file".into());
    }
    let mut bytes = Vec::new();
    file.take(limit + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > limit {
        return Err("measurement input exceeds byte bound".into());
    }
    Ok(bytes)
}

fn hash(value: &Value, name: &str, len: usize) -> Result<(), String> {
    if !value[name].as_str().is_some_and(|s| {
        s.len() == len
            && s.bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    }) {
        return Err(format!("invalid {name} identity"));
    }
    Ok(())
}

fn pinned_bytes(
    root: &Path,
    entry: &Value,
    path_key: &str,
    hash_key: &str,
    limit: u64,
    paths: &mut BTreeSet<std::path::PathBuf>,
) -> Result<Vec<u8>, String> {
    let path = entry[path_key]
        .as_str()
        .ok_or_else(|| format!("missing {path_key}"))?;
    let path = root.join(path).canonicalize().map_err(|e| e.to_string())?;
    if !path.starts_with(root) || !paths.insert(path.clone()) {
        return Err(format!("{path_key} escapes campaign or is repeated"));
    }
    hash(entry, hash_key, 64)?;
    let bytes = read_bounded(&path, limit)?;
    if format!("{:x}", Sha256::digest(&bytes)) != entry[hash_key].as_str().unwrap() {
        return Err(format!("{path_key} digest mismatch"));
    }
    Ok(bytes)
}

fn validate_load(bytes: &[u8], load: &str, recipe_hash: &Value) -> Result<(), String> {
    let value: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    fields(
        &value,
        &[
            "schema",
            "recipe",
            "workers",
            "blocks_per_worker",
            "elapsed_ns",
        ],
    )?;
    let recipe = value["recipe"].as_str().ok_or("missing load recipe")?;
    if number(&value, "schema")? != 1
        || format!("{:x}", Sha256::digest(recipe.as_bytes())) != recipe_hash.as_str().unwrap()
    {
        return Err("load schema or recipe identity mismatch".into());
    }
    let workers = if load == "idle" { 0 } else { 2 };
    let blocks = value["blocks_per_worker"]
        .as_array()
        .ok_or("load progress must be an array")?;
    if number(&value, "workers")? != workers
        || blocks.len() as u64 != workers
        || blocks
            .iter()
            .any(|value| value.as_u64().is_none_or(|n| n == 0))
        || number(&value, "elapsed_ns")? == 0
    {
        return Err("load worker count, progress or elapsed time is invalid".into());
    }
    Ok(())
}

/// Only manifests emitted by the runner carry source/process custody evidence.
/// This reader checks a captured campaign; it cannot authenticate its producer.
pub fn report(manifest: &Path) -> Result<Value, String> {
    let manifest = manifest.canonicalize().map_err(|e| e.to_string())?;
    let root = manifest.parent().ok_or("manifest has no parent")?;
    let document: Value =
        serde_json::from_slice(&read_bounded(&manifest, 256 * 1024)?).map_err(|e| e.to_string())?;
    fields(&document, &["schema", "mode", "identity", "runs"])?;
    if number(&document, "schema")? != 1 {
        return Err("unsupported campaign schema".into());
    }
    let mode = choice(&document, "mode", &["smoke", "acceptance"])?;
    let identity = &document["identity"];
    fields(
        identity,
        &[
            "sophia_commit",
            "hagia_sha256",
            "overlay_sha256",
            "test_binary_sha256",
            "workload_sha256",
            "machine_sha256",
            "load_recipe_sha256",
            "build_mode",
        ],
    )?;
    hash(identity, "sophia_commit", 40)?;
    for key in [
        "hagia_sha256",
        "overlay_sha256",
        "test_binary_sha256",
        "workload_sha256",
        "machine_sha256",
        "load_recipe_sha256",
    ] {
        hash(identity, key, 64)?;
    }
    choice(identity, "build_mode", &["debug", "release"])?;
    let runs = document["runs"]
        .as_array()
        .ok_or("campaign runs must be an array")?;
    if runs.is_empty() || runs.len() > 80 {
        return Err("campaign requires 1..80 captures".into());
    }
    let mut groups = BTreeMap::new();
    let mut paths = BTreeSet::new();
    for (index, entry) in runs.iter().enumerate() {
        fields(
            entry,
            &[
                "ordinal",
                "pair",
                "load",
                "path",
                "sha256",
                "load_path",
                "load_sha256",
            ],
        )?;
        if number(entry, "ordinal")? != index as u64 + 1 {
            return Err("campaign execution order is not contiguous".into());
        }
        let pair = number(entry, "pair")?;
        if !(1..=5).contains(&pair) {
            return Err("pair must be 1..5".into());
        }
        let load = choice(entry, "load", &["idle", "cpu"])?;
        let bytes = pinned_bytes(root, entry, "path", "sha256", CAPTURE_LIMIT, &mut paths)?;
        let run = decode_run(&bytes)?;
        let load_bytes = pinned_bytes(
            root,
            entry,
            "load_path",
            "load_sha256",
            LOAD_LIMIT,
            &mut paths,
        )?;
        validate_load(&load_bytes, &load, &identity["load_recipe_sha256"])?;
        let key = (run.kind.clone(), run.rate_hz, load, pair);
        groups
            .entry(key)
            .or_insert_with(Vec::new)
            .push((index, run));
    }
    let mut pairs = Vec::new();
    for ((kind, rate, load, pair), runs) in &groups {
        let wires: Vec<_> = runs.iter().map(|(_, r)| r.wire.as_str()).collect();
        let expected = if pair % 2 == 1 {
            ["current-ipc", "9p2000.L"]
        } else {
            ["9p2000.L", "current-ipc"]
        };
        if wires != expected || runs[1].0 != runs[0].0 + 1 {
            return Err("pairs must be adjacent and alternate execution order".into());
        }
        let (ipc, files) = if pair % 2 == 1 {
            (&runs[0].1, &runs[1].1)
        } else {
            (&runs[1].1, &runs[0].1)
        };
        if mode == "acceptance" && [ipc, files].iter().any(|r| r.admitted < 10_000) {
            return Err("acceptance needs 10000 admitted updates in every run".into());
        }
        let mut comparison = compare(ipc, files)?;
        comparison["load"] = json!(load);
        comparison["pair"] = json!(pair);
        pairs.push(comparison);
        let _ = (kind, rate);
    }
    if mode == "acceptance" && groups.len() != 40 {
        return Err(
            "acceptance requires five pairs for each move/resize, 60/120 Hz, idle/CPU condition"
                .into(),
        );
    }
    let budgets_pass = pairs.iter().all(|p| p["budgets_pass"] == true);
    Ok(
        json!({"schema":1,"mode":mode,"identity":identity,"pairs":pairs,"budgets_pass":budgets_pass,
        "latency_gate_pass":mode == "acceptance" && budgets_pass,
        "physical_acceptance":false,"full_t249_acceptance":false,
        "qualifications":["captured Session owner timings, not input-to-photon", "hashes bind bytes, not producer authenticity",
            "smoke cannot satisfy the latency gate", "CPU, allocation, copied bytes, wakes and round-trip measurements remain separate"]}),
    )
}
