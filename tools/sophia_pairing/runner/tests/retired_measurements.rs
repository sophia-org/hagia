use std::process::Command;

#[test]
fn retired_ipc_comparison_refuses_before_source_or_binary_access() {
    for mode in ["smoke", "acceptance"] {
        let output = Command::new(env!("CARGO_BIN_EXE_hagia-sophia-pairing"))
            .env_clear()
            .arg(format!("--measure={mode}"))
            .output()
            .unwrap();
        assert!(!output.status.success());
        assert!(output.stdout.is_empty());
        assert!(
            String::from_utf8(output.stderr)
                .unwrap()
                .contains("IPC/files measurement runs are retired")
        );
    }
}
