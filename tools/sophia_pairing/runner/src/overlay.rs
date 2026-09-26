//! Private test access is confined to a pinned scratch checkout. The caller's
//! checkout is read only; no permanent include hook or Session API is added.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const COMPATIBILITY: &str = include_str!("../../compatibility.json");
const MOUNT: &str = "crates/sophia-session/tests/support/desktop_launch_reload.rs";
const QID_MOUNT: &str = "crates/sophia-session/src/live_session/policy_transport_worker/ninep.rs";
const DIRECTORY: &str = "crates/sophia-session/tests/support/external_wm_acceptance";
const SESSION_MANIFEST: &str = "crates/sophia-session/Cargo.toml";
const CARGO_LOCK: &str = "Cargo.lock";
const MOUNT_TEXT: &str = "\n// Optional Hagia-owned pairing overlay; absent from the Sophia base.\n#[path = \"external_wm_acceptance/policy_hagia_session.rs\"]\nmod policy_hagia_session;\n";
const QID_TEXT: &str = "\n#[path = \"../../../tests/support/external_wm_acceptance/policy_file_qid_observation.rs\"]\npub(in crate::live_session) mod qid_observation;\n";
const FIXTURES: &[(&str, &str)] = &[
    (
        "policy_hagia_session.rs",
        include_str!("../../fixtures/policy_hagia_session.rs"),
    ),
    (
        "policy_hagia_layout.rs",
        include_str!("../../fixtures/policy_hagia_layout.rs"),
    ),
    (
        "policy_hagia_cpu.rs",
        include_str!("../../fixtures/policy_hagia_cpu.rs"),
    ),
    (
        "policy_hagia_operation.rs",
        include_str!("../../fixtures/policy_hagia_operation.rs"),
    ),
    (
        "policy_hagia_recovery.rs",
        include_str!("../../fixtures/policy_hagia_recovery.rs"),
    ),
    (
        "policy_hagia_profile_recovery.rs",
        include_str!("../../fixtures/policy_hagia_profile_recovery.rs"),
    ),
    (
        "policy_hagia_corpus.rs",
        include_str!("../../fixtures/policy_hagia_corpus.rs"),
    ),
    (
        "policy_hagia_behavior.rs",
        include_str!("../../fixtures/policy_hagia_behavior.rs"),
    ),
    (
        "policy_hagia_presentation.rs",
        include_str!("../../fixtures/policy_hagia_presentation.rs"),
    ),
    (
        "policy_file_qid_observation.rs",
        include_str!("../../fixtures/policy_file_qid_observation.rs"),
    ),
];

pub fn compatibility() -> Result<Value, String> {
    serde_json::from_str(COMPATIBILITY).map_err(|e| e.to_string())
}

pub fn validate_source(source: &Path) -> Result<(), String> {
    let expected = compatibility()?;
    let head = git(source, &["rev-parse", "HEAD"])?;
    if head.trim() != expected["sophia_commit"].as_str().unwrap_or("") {
        return Err(format!(
            "pairing requires Sophia {}, found {}",
            expected["sophia_commit"],
            head.trim()
        ));
    }
    if !git(source, &["status", "--porcelain", "--untracked-files=all"])?.is_empty() {
        return Err(
            "pairing requires a clean Sophia checkout; preserve or commit source first".into(),
        );
    }
    validate_mount(
        &fs::read(source.join(MOUNT)).map_err(|e| e.to_string())?,
        &expected,
    )?;
    if hash(&fs::read(source.join(QID_MOUNT)).map_err(|e| e.to_string())?)
        != expected["qid_mount_sha256"].as_str().unwrap_or("")
    {
        return Err("Sophia Qid test mount differs from its pinned context".into());
    }
    if source.join(DIRECTORY).exists() {
        return Err("Sophia base already contains the external overlay".into());
    }
    for (path, field) in [
        (SESSION_MANIFEST, "session_manifest_sha256"),
        (CARGO_LOCK, "cargo_lock_sha256"),
    ] {
        if hash(&fs::read(source.join(path)).map_err(|e| e.to_string())?)
            != expected[field].as_str().unwrap_or("")
        {
            return Err(format!(
                "pairing dependency overlay context changed: {path}"
            ));
        }
    }
    crate::legacy::validate(source, &expected)?;
    Ok(())
}

fn validate_mount(bytes: &[u8], expected: &Value) -> Result<(), String> {
    if hash(bytes) != expected["mount_sha256"].as_str().unwrap_or("") {
        return Err("Sophia test mount differs from its pinned context".into());
    }
    if String::from_utf8_lossy(bytes).contains("mod policy_hagia_session;") {
        return Err("Sophia base already mounts the Hagia pairing".into());
    }
    Ok(())
}

pub fn prepare(source: &Path, output: &Path) -> Result<PathBuf, String> {
    validate_source(source)?;
    let base = compatibility()?;
    let scratch = output.join("sophia");
    // --shared avoids another object-store copy. Checkout materializes all
    // tracked bytes; its complete diff is pinned before/after the run.
    checked(
        Command::new("git")
            .args(["clone", "--shared", "--no-checkout"])
            .arg(source)
            .arg(&scratch),
    )?;
    git(
        &scratch,
        &[
            "checkout",
            "--detach",
            base["sophia_commit"].as_str().unwrap(),
        ],
    )?;
    validate_source(&scratch)?;
    fs::create_dir(scratch.join(DIRECTORY)).map_err(|e| e.to_string())?;
    let mut files = Vec::new();
    for (name, contents) in FIXTURES {
        fs::write(scratch.join(DIRECTORY).join(name), contents).map_err(|e| e.to_string())?;
        files.push(
            json!({"path": format!("{DIRECTORY}/{name}"), "sha256": hash(contents.as_bytes()), "kind": "fixture"}),
        );
    }
    let mut mount = fs::read(scratch.join(MOUNT)).map_err(|e| e.to_string())?;
    validate_mount(&mount, &base)?;
    mount.extend_from_slice(MOUNT_TEXT.as_bytes());
    fs::write(scratch.join(MOUNT), &mount).map_err(|e| e.to_string())?;
    files.push(json!({"path": MOUNT, "sha256": hash(&mount)}));
    let mut qid_mount = fs::read(scratch.join(QID_MOUNT)).map_err(|e| e.to_string())?;
    qid_mount.extend_from_slice(QID_TEXT.as_bytes());
    fs::write(scratch.join(QID_MOUNT), &qid_mount).map_err(|e| e.to_string())?;
    files.push(json!({"path": QID_MOUNT, "sha256": hash(&qid_mount)}));
    // Profile JSON is a Hagia-specific assertion. Its dependency exists only
    // in this scratch test manifest; locked resolution cannot touch production.
    for (path, context, replacement) in [
        (
            SESSION_MANIFEST,
            "[dev-dependencies]\n",
            "[dev-dependencies]\nserde_json = \"1\"\n",
        ),
        (
            CARGO_LOCK,
            "name = \"sophia-session\"\nversion = \"0.1.0\"\ndependencies = [\n \"rustix\",\n",
            "name = \"sophia-session\"\nversion = \"0.1.0\"\ndependencies = [\n \"rustix\",\n \"serde_json\",\n",
        ),
    ] {
        let text = fs::read_to_string(scratch.join(path)).map_err(|e| e.to_string())?;
        if text.matches(context).count() != 1 {
            return Err(format!("ambiguous dependency overlay context: {path}"));
        }
        let text = text.replacen(context, replacement, 1);
        fs::write(scratch.join(path), &text).map_err(|e| e.to_string())?;
        files.push(json!({"path": path, "sha256": hash(text.as_bytes())}));
    }
    files.extend(crate::legacy::apply(&scratch)?);
    let manifest = json!({"schema": 1, "base": base, "files": files,
        "private_test_overlay": true, "unmodified_sophia_claim": false});
    let manifest_bytes = serde_json::to_vec_pretty(&manifest).map_err(|e| e.to_string())?;
    fs::write(output.join("overlay.json"), &manifest_bytes).map_err(|e| e.to_string())?;
    fs::write(
        output.join("overlay.sha256"),
        format!("{}\n", hash(&manifest_bytes)),
    )
    .map_err(|e| e.to_string())?;
    let mut add = vec!["add", "--"];
    for file in manifest["files"]
        .as_array()
        .ok_or("invalid file manifest")?
    {
        add.push(file["path"].as_str().ok_or("invalid file path")?);
    }
    git(&scratch, &add)?;
    let patch = git(&scratch, &["diff", "HEAD", "--binary"])?;
    fs::write(output.join("overlay.patch"), patch).map_err(|e| e.to_string())?;
    Ok(scratch)
}

pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn git(repo: &Path, args: &[&str]) -> Result<String, String> {
    checked(Command::new("git").current_dir(repo).args(args))
}

fn checked(command: &mut Command) -> Result<String, String> {
    // These local source operations have their own bound; they never fetch.
    let mut bounded = Command::new("timeout");
    bounded
        .args(["--signal=KILL", "60s"])
        .arg(command.get_program())
        .args(command.get_args())
        .stdin(Stdio::null());
    if let Some(cwd) = command.get_current_dir() {
        bounded.current_dir(cwd);
    }
    let result = bounded.output().map_err(|e| e.to_string())?;
    if !result.status.success() {
        return Err(format!(
            "source operation failed: {}",
            String::from_utf8_lossy(&result.stderr)
        ));
    }
    String::from_utf8(result.stdout).map_err(|e| e.to_string())
}
