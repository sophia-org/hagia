mod acceptance;
mod legacy;
mod overlay;

fn main() -> std::process::ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments == ["--help"] {
        println!(
            "Optional Hagia/Sophia pairing on an isolated source overlay.\n\
Usage: hagia-sophia-pairing --sophia-root=CHECKOUT --hagia-bin=EXECUTABLE\n\
  --hagia-sha256=HASH --output=FRESH_DIRECTORY --target-dir=EXCLUSIVE_CACHE\n\
  [--timeout=3600]\n\
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
