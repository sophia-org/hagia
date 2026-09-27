mod acceptance;
mod legacy;
mod measurement;
mod measurement_run;
mod overlay;

fn main() -> std::process::ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    // The comparative IPC/files campaign cannot qualify a 9P-only product.
    // Historical report parsing below remains available without running peers.
    if arguments.iter().any(|arg| arg.starts_with("--measure=")) {
        eprintln!(
            "IPC/files measurement runs are retired; use --report-measurements only for historical evidence"
        );
        return std::process::ExitCode::FAILURE;
    }
    // Standalone CPU load workers are wire-neutral; they do not run a paired campaign.
    if arguments.first().map(String::as_str) == Some("--measurement-worker") {
        return match measurement_run::worker(&arguments[1..]) {
            Ok(()) => std::process::ExitCode::SUCCESS,
            Err(error) => {
                eprintln!("Hagia measurement worker: {error}");
                std::process::ExitCode::FAILURE
            }
        };
    }
    if let [argument] = arguments.as_slice()
        && let Some(path) = argument.strip_prefix("--report-measurements=")
    {
        return match measurement::report(std::path::Path::new(path)) {
            Ok(report) => {
                println!("{}", serde_json::to_string_pretty(&report).unwrap());
                if report["budgets_pass"] == true {
                    std::process::ExitCode::SUCCESS
                } else {
                    std::process::ExitCode::FAILURE
                }
            }
            Err(error) => {
                eprintln!("Hagia measurement report: {error}");
                std::process::ExitCode::FAILURE
            }
        };
    }
    if arguments == ["--help"] {
        println!(
            "Optional Hagia/Sophia pairing on an isolated source overlay.\n\
Usage: hagia-sophia-pairing --sophia-root=CHECKOUT --hagia-bin=EXECUTABLE\n\
  --hagia-sha256=HASH --output=FRESH_DIRECTORY --target-dir=EXCLUSIVE_CACHE\n\
  [--timeout=3600]\n\
Offline timing report: hagia-sophia-pairing --report-measurements=MANIFEST\n\
The supported Sophia revision and frozen Hagia identity are in compatibility.json.\n\
The checkout must be clean at that revision. No live session or hardware access."
        );
        return std::process::ExitCode::SUCCESS;
    }
    let result = std::env::current_dir()
        .map_err(|e| e.to_string())
        .and_then(|cwd| acceptance::run(&cwd, &arguments));
    match result {
        Ok(lines) => {
            for line in lines {
                println!("{line}");
            }
            std::process::ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("Hagia pairing: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}
