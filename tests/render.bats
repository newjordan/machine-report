#!/usr/bin/env bats

load test_helper

@test "linux fixture render is aligned and uses the parsed fields" {
    use_fixtures
    run bash "$REPO/linux.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "LINUX MACHINE REPORT"
    assert_contains "$output" "Ubuntu 24.04 Noble"
    assert_contains "$output" "Linux 9.9.9-test"
    assert_contains "$output" "testhost"
    assert_contains "$output" "10.1.2.3"
    assert_contains "$output" "local"
    assert_contains "$output" "1.1.1.1"
    assert_contains "$output" "2606:4700:4700::1111"
    assert_contains "$output" "frosty"
    assert_contains "$output" "Intel Xeon CPU E5-2670 0"
    assert_contains "$output" "32 threads / 16 cores / 2 sockets"
    assert_contains "$output" "Linux Workstation"
    assert_contains "$output" "3.30 GHz"
    assert_contains "$output" "50.00/100.00 GiB [50.0%]"
    assert_contains "$output" "4.00/8.00 GiB [50.0%]"
    assert_contains "$output" "Wed Nov 25 18:00:00 2026"
    assert_contains "$output" "LOGIN FROM"
    assert_contains "$output" "192.168.1.10"
    assert_contains "$output" "1h 1m"
    assert_not_contains "$output" "GPU MEM"
    assert_not_contains "$output" " GB "
}

@test "a full ipv6 address is not ellipsized" {
    use_fixtures
    export MACHINE_REPORT_IP="ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
    run bash "$REPO/linux.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
}

@test "a long processor name stays inside the box" {
    use_fixtures
    local long
    long=$(printf 'X%.0s' {1..70})
    cat > "$BATS_TEST_TMPDIR/lscpu-long.txt" <<EOF
Model name: $long
Core(s) per socket: 4
Socket(s): 1
CPU max MHz: 1000.0000
EOF
    export MACHINE_REPORT_LSCPU_FILE="$BATS_TEST_TMPDIR/lscpu-long.txt"
    export MACHINE_REPORT_NPROC=4
    run bash "$REPO/linux.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "XXX..."
    assert_not_contains "$output" "$long"
}

@test "load above the cpu count fills the bar and does not widen the row" {
    use_fixtures
    printf '40 40 40 1/1 1\n' > "$BATS_TEST_TMPDIR/load"
    export MACHINE_REPORT_LOADAVG="$BATS_TEST_TMPDIR/load"
    export MACHINE_REPORT_NPROC=4
    run bash "$REPO/linux.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    local line
    line=$(printf '%s\n' "$output" | grep 'LOAD  1m')
    [[ "$line" == *"█"* ]]
    [[ "$line" != *"░"* ]]
}

@test "discrete gpu row shows memory and a quoted name" {
    use_fixtures
    export MACHINE_REPORT_GPU_CSV='"NVIDIA A100, SXM", 50, 70, 120.5, 2048, 8192'
    run bash "$REPO/linux.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "NVIDIA A100, SXM"
    assert_contains "$output" "70 °C"
    assert_contains "$output" "120.50 W"
    assert_contains "$output" "2.00/8.00 GiB [25.0%]"
    assert_contains "$output" "GPU USAGE"
}

@test "discrete gpu hides memory rows when nvidia-smi reports N/A" {
    use_fixtures
    export MACHINE_REPORT_GPU_CSV='NVIDIA Weird, 0, 41, [N/A], [N/A], [N/A]'
    run bash "$REPO/linux.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "NVIDIA Weird"
    assert_contains "$output" "41 °C"
    assert_contains "$output" "n/a"
    assert_not_contains "$output" "GPU MEM"
    assert_not_contains "$output" "GPU USAGE"
}

@test "spark fixture shows the hybrid cpu and the graphics clock" {
    use_fixtures
    export MACHINE_REPORT_LSCPU_FILE="$REPO/tests/fixtures/lscpu-spark.txt"
    export MACHINE_REPORT_NPROC=20
    export MACHINE_REPORT_GPU_CSV='NVIDIA GB10, 12, 58, 15.27, 2411'
    run bash "$REPO/spark.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "DGX SPARK MACHINE REPORT"
    assert_contains "$output" "NVIDIA GB10 Grace Blackwell"
    assert_contains "$output" "Cortex-X925 + Cortex-A725"
    assert_contains "$output" "20 (10P + 10E)"
    assert_contains "$output" "NVIDIA DGX Spark"
    assert_contains "$output" "3.90 GHz"
    assert_contains "$output" "58 °C"
    assert_contains "$output" "15.27 W"
    assert_contains "$output" "2411 MHz"
    assert_contains "$output" "GPU CLOCK"
    assert_not_contains "$output" "GPU MEM"
}

@test "spark script on a single-model cpu omits the arch row" {
    use_fixtures
    run bash "$REPO/spark.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "Intel Xeon CPU E5-2670 0"
    assert_not_contains "$output" "ARCH"
}

@test "wsl fixture uses the wsl identity and the linux cpu summary" {
    use_fixtures
    run bash "$REPO/wsl.sh"
    [ "$status" -eq 0 ]
    assert_box_aligned "$output"
    assert_contains "$output" "WSL2 MACHINE REPORT"
    assert_contains "$output" "WSL2 on Windows"
    assert_contains "$output" "32 threads / 16 cores / 2 sockets"
    assert_not_contains "$output" "ARCH"
}

@test "live banners stay aligned, including under the C locale" {
    local script
    for script in linux.sh spark.sh wsl.sh; do
        run bash "$REPO/$script"
        [ "$status" -eq 0 ]
        assert_box_aligned "$output"
        assert_contains "$output" "GiB"
        run env LC_ALL=C bash "$REPO/$script"
        [ "$status" -eq 0 ]
        assert_box_aligned "$output"
    done
}
