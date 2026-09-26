//! Legacy interoperability fixtures remain Hagia-owned. Mount only the exact
//! reviewed source recipe, and run named cases from pinned test executables.
use crate::acceptance::{digest, listed_binary, read_log, require_exactly_one};
use crate::overlay::hash;
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

const MOUNTS: &str = include_str!("../../legacy/MOUNTS.tsv");
const FILES: &[(&str, &str)] = &[
    (
        "runtime/pointer_focus_hagia.rs",
        include_str!("../../legacy/runtime/pointer_focus_hagia.rs"),
    ),
    (
        "runtime/presentation_hagia.rs",
        include_str!("../../legacy/runtime/presentation_hagia.rs"),
    ),
    (
        "session/delegated_policy.rs",
        include_str!("../../legacy/session/delegated_policy.rs"),
    ),
    (
        "session/pregraphics_activation.rs",
        include_str!("../../legacy/session/pregraphics_activation.rs"),
    ),
    (
        "session/hagia_launch_origin.rs",
        include_str!("../../legacy/session/hagia_launch_origin.rs"),
    ),
    (
        "session/targeted_policy.rs",
        include_str!("../../legacy/session/targeted_policy.rs"),
    ),
    (
        "session/policy_partial_projection_socket.rs",
        include_str!("../../legacy/session/policy_partial_projection_socket.rs"),
    ),
];

struct Mount<'a> {
    source: &'a str,
    destination: &'a str,
    parent: &'a str,
    anchor: &'a str,
    lines: &'a str,
}

fn mounts() -> Result<Vec<Mount<'static>>, String> {
    MOUNTS
        .lines()
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(|line| {
            let fields: Vec<_> = line.split('\t').collect();
            if fields.len() != 5 || !FILES.iter().any(|(name, _)| *name == fields[0]) {
                return Err("invalid embedded legacy mount recipe".into());
            }
            Ok(Mount {
                source: fields[0],
                destination: fields[1],
                parent: fields[2],
                anchor: fields[3],
                lines: fields[4],
            })
        })
        .collect()
}

pub fn validate(source: &Path, compatibility: &Value) -> Result<(), String> {
    for mount in mounts()? {
        let text = fs::read_to_string(source.join(mount.parent)).map_err(|e| e.to_string())?;
        if hash(text.as_bytes())
            != compatibility["legacy_mount_sha256"][mount.parent]
                .as_str()
                .unwrap_or("")
            || text.lines().filter(|line| *line == mount.anchor).count() != 1
            || source.join(mount.destination).exists()
        {
            return Err(format!(
                "legacy pairing mount context differs: {}",
                mount.parent
            ));
        }
    }
    Ok(())
}

pub fn apply(scratch: &Path) -> Result<Vec<Value>, String> {
    let mut files = Vec::new();
    let mut parents = BTreeSet::new();
    for mount in mounts()? {
        let contents = FILES
            .iter()
            .find(|(name, _)| *name == mount.source)
            .unwrap()
            .1;
        if scratch.join(mount.destination).exists() {
            return Err(format!(
                "legacy destination already exists: {}",
                mount.destination
            ));
        }
        fs::write(scratch.join(mount.destination), contents).map_err(|e| e.to_string())?;
        files.push(json!({"path": mount.destination, "sha256": hash(contents.as_bytes()), "kind": "fixture"}));
        let path = scratch.join(mount.parent);
        let mut text = fs::read_to_string(&path).map_err(|e| e.to_string())?;
        if text.lines().filter(|line| *line == mount.anchor).count() != 1 {
            return Err(format!("ambiguous legacy mount anchor: {}", mount.parent));
        }
        text.push('\n');
        text.push_str(&mount.lines.replace("\\n", "\n"));
        text.push('\n');
        fs::write(path, &text).map_err(|e| e.to_string())?;
        parents.insert(mount.parent);
    }
    for parent in parents {
        files.push(json!({"path": parent, "sha256": hash(&fs::read(scratch.join(parent)).map_err(|e| e.to_string())?), "kind": "mount"}));
    }
    Ok(files)
}

pub(crate) fn named_test(list: &str, suffix: &str) -> Result<String, String> {
    let matches: Vec<_> = list
        .lines()
        .filter_map(|line| line.strip_suffix(": test"))
        .filter(|name| name.rsplit("::").next() == Some(suffix))
        .collect();
    if matches.len() != 1 {
        return Err(format!("legacy test missing or ambiguous: {suffix}"));
    }
    Ok(matches[0].to_owned())
}

type Judge = fn(&str) -> Result<(), String>;

pub fn exercise(
    phase: &mut impl FnMut(&str, &str, &[&str], Judge) -> Result<(), String>,
    output: &Path,
    target: &Path,
) -> Result<(), String> {
    let runtime = [
        (
            "hagia_pointer_focus_real_socket_commits_rejects_and_retries",
            false,
        ),
        (
            "hagia_pointer_focus_old_server_reports_the_setting_before_admission",
            false,
        ),
        (
            "hagia_without_presentation_actions_keeps_ordinary_policy_available",
            false,
        ),
        (
            "hagia_overview_publishes_generic_records_and_accepts_exact_targeted_actions",
            false,
        ),
        (
            "hagia_overview_timeout_retains_the_committed_publication",
            false,
        ),
        (
            "hagia_overview_revoked_receipt_closes_on_the_next_cycle",
            false,
        ),
        (
            "hagia_overview_reconnect_starts_closed_and_reuses_no_authority",
            false,
        ),
    ];
    let native = [
        (
            "hagia_real_x_child_origin_survives_monitor_switch_and_rejection",
            false,
        ),
        (
            "hagia_output_bookmark_places_empty_output_after_focus_switch_and_rejected_cycle",
            true,
        ),
        (
            "hagia_real_partial_pointer_projection_preserves_untouched_output",
            false,
        ),
        (
            "two_output_click_queue_reaches_hagia_without_active_output_retargeting",
            true,
        ),
    ];
    let pregraphics = [
        (
            "hagia_pregraphics_profile_admission_rejects_invalid_policy_values",
            false,
        ),
        (
            "hagia_pregraphics_profile_admission_activates_every_owner",
            false,
        ),
    ];
    for (family, selection, cases) in [
        (
            "runtime",
            &["-p", "sophia-runtime", "--test", "policy_transport"][..],
            &runtime[..],
        ),
        (
            "native",
            &[
                "-p",
                "sophia-session",
                "--features",
                "native-session",
                "--lib",
            ][..],
            &native[..],
        ),
        (
            "pregraphics",
            &[
                "-p",
                "sophia-session",
                "--features",
                "atomic-scanout-live",
                "--lib",
            ][..],
            &pregraphics[..],
        ),
    ] {
        let list_name = format!("legacy-{family}-list");
        let mut command = vec!["test", "--offline", "--locked", "-j", "2"];
        command.extend_from_slice(selection);
        command.extend(["--", "--list"]);
        phase(&list_name, "cargo", &command, |_| Ok(()))?;
        let list = read_log(&output.join(format!("{list_name}.log")))?;
        let binary = listed_binary(
            &list,
            target,
            if family == "runtime" {
                "tests/policy_transport.rs"
            } else {
                "unittests src/lib.rs"
            },
        )?;
        let hash = digest(&binary)?;
        let tests: Vec<_> = cases
            .iter()
            .map(|(suffix, ignored)| named_test(&list, suffix).map(|name| (name, ignored)))
            .collect::<Result<_, _>>()?;
        fs::write(
            output.join(format!("legacy-{family}-test-binary.json")),
            serde_json::to_vec_pretty(&json!({"path": binary, "sha256": hash, "tests": tests}))
                .map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        if family == "runtime" {
            // This reducer-only boundary is deliberately not an acceptance
            // case: epoch authority lives in the joined Session path.
            phase(
                "legacy-runtime-ignored-list",
                binary.to_str().ok_or("test path must be UTF-8")?,
                &["--list", "--ignored"],
                |text| {
                    named_test(
                        text,
                        "hagia_overview_old_epoch_identity_is_refused_after_reconnect",
                    )
                    .map(|_| ())
                },
            )?;
        }
        for (index, (name, ignored)) in tests.iter().enumerate() {
            if digest(&binary)? != hash {
                return Err("legacy test executable changed before case".into());
            }
            let mut args = vec![name.as_str(), "--exact", "--nocapture", "--test-threads=1"];
            if **ignored {
                args.push("--ignored");
            }
            phase(
                &format!("legacy-{family}-{index:02}"),
                binary.to_str().ok_or("test path must be UTF-8")?,
                &args,
                require_exactly_one,
            )?;
            if digest(&binary)? != hash {
                return Err("legacy test executable changed after case".into());
            }
        }
    }
    Ok(())
}
