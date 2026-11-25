#!/usr/bin/env bats

load test_helper

setup() {
    HOME_DIR="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME_DIR"
    printf 'echo kept\n' > "$HOME_DIR/.bashrc"
    chmod 644 "$HOME_DIR/.bashrc"
}

@test "help exits zero and mentions uninstall" {
    run bash "$REPO/install.sh" --help
    [ "$status" -eq 0 ]
    assert_contains "$output" "--uninstall"
    assert_contains "$output" "--no-preview"
}

@test "unknown arguments and path-like targets are rejected" {
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" --not-a-flag
    [ "$status" -eq 2 ]
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" --target=../linux
    [ "$status" -eq 2 ]
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" --target=
    [ "$status" -eq 2 ]
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" --target=notreal --no-preview
    [ "$status" -eq 1 ]
    [[ ! -L "$HOME_DIR/.machine_report.sh" ]]
}

@test "install is idempotent, preserves bashrc mode, and uninstalls" {
    local before after
    before=$(stat -c %a "$HOME_DIR/.bashrc")
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" linux --no-preview
    [ "$status" -eq 0 ]
    assert_contains "$output" "Added bashrc snippet."
    [[ "$(readlink -f "$HOME_DIR/.machine_report.sh")" == "$REPO/linux.sh" ]]
    cp "$HOME_DIR/.bashrc" "$BATS_TEST_TMPDIR/bashrc1"

    run env HOME="$HOME_DIR" bash "$REPO/install.sh" linux --no-preview
    [ "$status" -eq 0 ]
    assert_contains "$output" "bashrc snippet already current."
    cmp "$BATS_TEST_TMPDIR/bashrc1" "$HOME_DIR/.bashrc"
    [ "$(grep -c '>>> machine-report >>>' "$HOME_DIR/.bashrc")" -eq 1 ]
    assert_contains "$(cat "$HOME_DIR/.bashrc")" "echo kept"
    assert_contains "$(cat "$HOME_DIR/.bashrc")" "-t 1"
    bash -n "$HOME_DIR/.bashrc"

    run env HOME="$HOME_DIR" bash "$REPO/install.sh" --uninstall
    [ "$status" -eq 0 ]
    after=$(stat -c %a "$HOME_DIR/.bashrc")
    assert_eq "$before" "$after"
    [[ ! -e "$HOME_DIR/.machine_report.sh" && ! -L "$HOME_DIR/.machine_report.sh" ]]
    run grep -F "machine-report" "$HOME_DIR/.bashrc"
    [ "$status" -ne 0 ]
    assert_contains "$(cat "$HOME_DIR/.bashrc")" "echo kept"

    run env HOME="$HOME_DIR" bash "$REPO/install.sh" --uninstall
    [ "$status" -eq 0 ]
    assert_contains "$output" "not installed"
}

@test "a regular file at the symlink path is backed up" {
    printf 'manual report\n' > "$HOME_DIR/.machine_report.sh"
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" spark --no-preview
    [ "$status" -eq 0 ]
    [[ -L "$HOME_DIR/.machine_report.sh" ]]
    [[ "$(readlink -f "$HOME_DIR/.machine_report.sh")" == "$REPO/spark.sh" ]]
    local bak
    bak=$(echo "$HOME_DIR"/.machine_report.sh.bak.*)
    [[ -f "$bak" ]]
    assert_contains "$(cat "$bak")" "manual report"
}

@test "preview runs the linked report" {
    run env HOME="$HOME_DIR" bash "$REPO/install.sh" wsl
    [ "$status" -eq 0 ]
    assert_contains "$output" "WSL2 MACHINE REPORT"
    assert_box_aligned "$(printf '%s\n' "$output" | sed -n '/^┌/,$p')"
}

@test "auto-detect prefers GB10, then WSL, then generic linux" {
    # shellcheck disable=SC1091
    source "$REPO/install.sh"
    local bin="$BATS_TEST_TMPDIR/bin" version result
    mkdir -p "$bin"
    version="$BATS_TEST_TMPDIR/version"
    cat > "$bin/nvidia-smi" <<'EOF'
#!/bin/bash
printf '%s\n' "GPU 0: NVIDIA GB10 (UUID: GPU-test)"
EOF
    chmod +x "$bin/nvidia-smi"
    printf '%s\n' "Linux version 6.6 microsoft WSL2" > "$version"
    result=$(PATH="$bin:$PATH" MACHINE_REPORT_PROC_VERSION="$version" detect_target)
    assert_eq "$result" "spark"

    cat > "$bin/nvidia-smi" <<'EOF'
#!/bin/bash
printf '%s\n' "GPU 0: NVIDIA GeForce RTX 4090 (UUID: GPU-test)"
EOF
    result=$(PATH="$bin:$PATH" MACHINE_REPORT_PROC_VERSION="$version" detect_target)
    assert_eq "$result" "wsl"

    printf '%s\n' "Linux version 6.12.0 generic" > "$version"
    result=$(PATH="$bin:$PATH" MACHINE_REPORT_PROC_VERSION="$version" detect_target)
    assert_eq "$result" "linux"
}

@test "install refuses to run without HOME" {
    run env -u HOME bash "$REPO/install.sh" --help
    [ "$status" -eq 0 ]
    run env -u HOME bash "$REPO/install.sh" linux --no-preview
    [ "$status" -ne 0 ]
}
