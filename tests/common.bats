#!/usr/bin/env bats

load test_helper

@test "wsl.sh keeps the same functions as linux.sh" {
    diff -u \
        <(bash -c "source '$REPO/linux.sh'; declare -f") \
        <(bash -c "source '$REPO/wsl.sh'; declare -f")
}

@test "spark.sh shares helpers and only changes cpu, gpu, and render" {
    local fn a b
    while read -r fn; do
        case "$fn" in
            collect_cpu|read_gpu|main) continue ;;
        esac
        a=$(bash -c "source '$REPO/linux.sh'; declare -f $fn")
        b=$(bash -c "source '$REPO/spark.sh'; declare -f $fn")
        if [[ "$a" != "$b" ]]; then
            printf 'function drifted: %s\n' "$fn" >&2
            diff -u <(printf '%s\n' "$a") <(printf '%s\n' "$b") >&2 || true
            return 1
        fi
    done < <(bash -c "source '$REPO/linux.sh'; declare -F" | awk '{print $3}')
    bash -c "source '$REPO/spark.sh'; declare -f format_clock" >/dev/null
}

@test "bar graph is empty, half, full, and clamped on every target" {
    local script graph
    for script in linux.sh spark.sh wsl.sh; do
        graph=$(
            # shellcheck disable=SC1090
            source "$REPO/$script"
            CURRENT_LEN=10
            printf 'zero=%s\n' "$(bar_graph 0 10)"
            printf 'half=%s\n' "$(bar_graph 1 2)"
            printf 'full=%s\n' "$(bar_graph 10 10)"
            printf 'over=%s\n' "$(bar_graph 50 1)"
            printf 'bad=%s\n' "$(bar_graph 5 0)"
        )
        assert_eq "$(printf '%s\n' "$graph" | sed -n 's/^zero=//p')" "░░░░░░░░░░"
        assert_eq "$(printf '%s\n' "$graph" | sed -n 's/^half=//p')" "█████░░░░░"
        assert_eq "$(printf '%s\n' "$graph" | sed -n 's/^full=//p')" "██████████"
        assert_eq "$(printf '%s\n' "$graph" | sed -n 's/^over=//p')" "██████████"
        assert_eq "$(printf '%s\n' "$graph" | sed -n 's/^bad=//p')" "░░░░░░░░░░"
    done
}

@test "fit_width pads, keeps, and ellipsizes without changing the width" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    assert_eq "$(fit_width "hi" 5)" "hi   "
    assert_eq "$(fit_width "hello" 5)" "hello"
    assert_eq "$(fit_width "hello world" 8)" "hello..."
    assert_eq "$(fit_width "█░ok" 3)" "█░o"
}

@test "max_length honors the minimum and maximum data widths" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    assert_eq "$(max_length "hi")" "24"
    assert_eq "$(max_length "$(printf 'x%.0s' {1..30})")" "30"
    assert_eq "$(max_length "$(printf 'x%.0s' {1..80})")" "48"
}

@test "cpu model cleaner drops vendor noise and trailing clocks" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    assert_eq "$(clean_cpu_model "Intel(R) Xeon(R) Processor")" "Intel Xeon Processor"
    assert_eq "$(clean_cpu_model "Intel(R) Xeon(R) CPU E5-2670 0 @ 2.60GHz")" "Intel Xeon CPU E5-2670 0"
    assert_eq "$(clean_cpu_model "Intel(R) Core(TM) i7-8700 CPU @ 2.60GHz")" "Intel Core i7-8700"
    assert_eq "$(clean_cpu_model "AMD EPYC 7763 64-Core Processor")" "AMD EPYC 7763 64-Core Processor"
    assert_eq "$(clean_cpu_model "")" ""
}

@test "cpu summary uses cores, sockets, and threads" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    assert_eq "$(format_cpu_summary 4 4 1)" "4 cores / 1 socket"
    assert_eq "$(format_cpu_summary 1 1 1)" "1 core / 1 socket"
    assert_eq "$(format_cpu_summary 32 8 2)" "32 threads / 16 cores / 2 sockets"
    assert_eq "$(format_cpu_summary 8 0 1)" "8 threads"
}

@test "lscpu field lookup is exact and prefers the max clock" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    local text mhz
    text=$(cat "$REPO/tests/fixtures/lscpu-xeon.txt")
    assert_eq "$(lscpu_value "CPU MHz" "$text")" "2000.0000"
    assert_eq "$(lscpu_value "CPU max MHz" "$text")" "3300.0000"
    mhz=$(cpu_freq_mhz_from_lscpu "$text")
    assert_eq "$(mhz_to_ghz "$mhz")" "3.30 GHz"
    assert_eq "$(mhz_to_ghz "")" "n/a"
    assert_eq "$(mhz_to_ghz 0)" "n/a"
}

@test "cpu frequency falls back to /proc/cpuinfo" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    local text
    text=$(cat "$REPO/tests/fixtures/lscpu-no-mhz.txt")
    MACHINE_REPORT_CPUINFO="$REPO/tests/fixtures/cpuinfo"
    assert_eq "$(cpu_freq_mhz_from_lscpu "$text")" "2400"
    assert_eq "$(mhz_to_ghz 2400)" "2.40 GHz"
}

@test "lastlog columns survive a missing from-address and an ipv6 peer" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    local header rec time from
    header=$(lastlog_header)
    rec=$(parse_lastlog_record "$header" "")
    assert_eq "$rec" $'unavailable\t'

    rec=$(parse_lastlog_record "$header" "frosty                                              **Never logged in**")
    IFS=$'\t' read -r time from <<<"$rec"
    assert_eq "$time" "Never logged in"
    assert_eq "$from" ""

    local row
    row=$(printf '%-17s%-9s%-43s%s' "frosty" "pts/0" "192.168.1.10" "Wed Nov 25 18:00:00 +0000 2026")
    rec=$(parse_lastlog_record "$header" "$row")
    IFS=$'\t' read -r time from <<<"$rec"
    assert_eq "$time" "Wed Nov 25 18:00:00 2026"
    assert_eq "$from" "192.168.1.10"

    row=$(printf '%-17s%-9s%-43s%s' "frosty" "tty1" "" "Wed Nov 25 18:22:01 -0500 2026")
    rec=$(parse_lastlog_record "$header" "$row")
    IFS=$'\t' read -r time from <<<"$rec"
    assert_eq "$time" "Wed Nov 25 18:22:01 2026"
    assert_eq "$from" ""

    row=$(printf '%-17s%-9s%-43s%s' "frosty" "pts/0" "spark-2949.lan" "Thu Jan  2 03:04:05 +0000 2026")
    rec=$(parse_lastlog_record "$header" "$row")
    IFS=$'\t' read -r time from <<<"$rec"
    assert_eq "$time" "Thu Jan 2 03:04:05 2026"
    assert_eq "$from" "spark-2949.lan"

    row=$(printf '%-17s%-9s%-43s%s' "frosty" "pts/0" "2001:db8::10" "Wed Nov 25 18:00:00 +0000 2026")
    rec=$(parse_lastlog_record "$header" "$row")
    IFS=$'\t' read -r time from <<<"$rec"
    assert_eq "$from" "2001:db8::10"
}

@test "uptime formatting drops zero units and keeps a zero-minute host" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    assert_eq "$(format_uptime_seconds 0)" "0m"
    assert_eq "$(format_uptime_seconds 45)" "0m"
    assert_eq "$(format_uptime_seconds 90)" "1m"
    assert_eq "$(format_uptime_seconds 3661)" "1h 1m"
    assert_eq "$(format_uptime_seconds 86400)" "1d"
    assert_eq "$(format_uptime_seconds 90000)" "1d 1h"
    assert_eq "$(format_uptime_seconds 90061)" "1d 1h 1m"
    assert_eq "$(format_uptime_seconds abc)" "n/a"
}

@test "memory falls back when MemAvailable is missing and disk reads the last columns" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    MACHINE_REPORT_MEMINFO="$REPO/tests/fixtures/meminfo"
    assert_eq "$(read_mem_kb)" "4194304 8388608"
    MACHINE_REPORT_MEMINFO="$REPO/tests/fixtures/meminfo-noavail"
    assert_eq "$(read_mem_kb)" "400000 1000000"
    MACHINE_REPORT_DF_FILE="$REPO/tests/fixtures/df.txt"
    assert_eq "$(read_disk_mib)" "51200 102400"
    MACHINE_REPORT_DF_FILE="$REPO/tests/fixtures/df-long.txt"
    assert_eq "$(read_disk_mib)" "1024 4096"
    assert_eq "$(format_pair_gib 51200 102400 1024)" "50.00/100.00 GiB [50.0%]"
    assert_eq "$(format_pair_gib 0 0 1024)" "n/a"
}

@test "os name capitalizes the codename and tolerates a missing one" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    MACHINE_REPORT_OS_RELEASE="$REPO/tests/fixtures/os-release"
    assert_eq "$(read_os_name)" "Ubuntu 24.04 Noble"
    MACHINE_REPORT_OS_RELEASE="$REPO/tests/fixtures/os-release-fedora"
    assert_eq "$(read_os_name)" "Fedora Linux 41"
    MACHINE_REPORT_OS_RELEASE="$BATS_TEST_TMPDIR/missing"
    assert_eq "$(read_os_name)" "Unknown"
}

@test "quoted gpu csv keeps commas in the name and blanks N/A numbers" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    local line
    line=$(csv_to_tsv '"NVIDIA A100, SXM", 10, 40, 100.5, 1024, 4096')
    assert_eq "$line" $'NVIDIA A100, SXM\t10\t40\t100.5\t1024\t4096'
    assert_eq "$(numeric_or_blank " [N/A] ")" ""
    assert_eq "$(numeric_or_blank " 15.27 W ")" "15.27"
    assert_eq "$(format_power "15.27")" "15.27 W"
    assert_eq "$(format_power "")" "n/a"
    assert_eq "$(format_temp 58)" "58 °C"
}

@test "machine ip skips virtual interfaces and falls through when ip is absent" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    local bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    ln -s "$(command -v awk)" "$bin/awk"

    cat > "$bin/ip" <<'EOF'
#!/bin/bash
case "$*" in
    *-4*)
        printf '%s\n' "2: docker0 inet 172.17.0.1/16 scope global docker0"
        printf '%s\n' "3: br-abcd inet 172.18.0.1/16 scope global br-abcd"
        printf '%s\n' "4: veth123 inet 172.19.0.1/16 scope global veth123"
        printf '%s\n' "5: enp0s3 inet 10.9.8.7/24 scope global enp0s3"
        printf '%s\n' "5: enp0s3 inet 10.9.8.8/24 scope global enp0s3"
        ;;
    *-6*)
        printf '%s\n' "6: veth1 inet6 2001:db8::1/64 scope global"
        printf '%s\n' "7: eth0 inet6 2001:db8::10/64 scope global"
        ;;
esac
EOF
    chmod +x "$bin/ip"
    assert_eq "$(PATH="$bin:$PATH" get_ip_addr)" "10.9.8.7"

    cat > "$bin/ip" <<'EOF'
#!/bin/bash
case "$*" in
    *-4*) exit 0 ;;
    *-6*)
        printf '%s\n' "2: veth1 inet6 2001:db8::1/64 scope global"
        printf '%s\n' "3: eth0 inet6 fe80::1/64 scope global"
        printf '%s\n' "4: eth0 inet6 2001:db8::10/64 scope global"
        ;;
esac
EOF
    assert_eq "$(PATH="$bin:$PATH" get_ip_addr)" "2001:db8::10"

    cat > "$bin/ip" <<'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$bin/ifconfig" <<'EOF'
#!/bin/bash
export PATH="/usr/bin:/bin"
cat <<'OUT'
docker0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 172.17.0.1  netmask 255.255.0.0  broadcast 172.17.255.255
enp0s3: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet6 fe80::1  prefixlen 64  scopeid 0x20<link>
        inet 198.51.100.20  netmask 255.255.255.0  broadcast 198.51.100.255
lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
OUT
EOF
    chmod +x "$bin/ifconfig"
    assert_eq "$(PATH="$bin" get_ip_addr)" "198.51.100.20"

    rm -f "$bin/ifconfig"
    cat > "$bin/hostname" <<'EOF'
#!/bin/bash
if [[ "$1" == "-I" ]]; then
    printf '%s\n' "fe80::1 169.254.1.1 10.8.8.8"
    exit 0
fi
printf '%s\n' "testhost"
EOF
    chmod +x "$bin/hostname"
    assert_eq "$(PATH="$bin" get_ip_addr)" "10.8.8.8"
}

@test "client address prefers the ssh peer and says local otherwise" {
    # shellcheck disable=SC1091
    source "$REPO/linux.sh"
    unset SSH_CONNECTION SSH_CLIENT
    SSH_CONNECTION="203.0.113.9 54432 10.0.0.5 22"
    assert_eq "$(read_client_ip)" "203.0.113.9"
    unset SSH_CONNECTION
    SSH_CLIENT="2001:db8::5 54432 22"
    assert_eq "$(read_client_ip)" "2001:db8::5"
    unset SSH_CLIENT
    assert_eq "$(read_client_ip)" "local"
}

@test "spark hybrid lscpu becomes a GB10 label and a P+E summary" {
    # shellcheck disable=SC1091
    source "$REPO/spark.sh"
    MACHINE_REPORT_LSCPU_FILE="$REPO/tests/fixtures/lscpu-spark.txt"
    MACHINE_REPORT_NPROC=20
    collect_cpu
    assert_eq "$cpu_model" "NVIDIA GB10 Grace Blackwell"
    assert_eq "$cpu_arch" "Cortex-X925 + Cortex-A725"
    assert_eq "$cpu_summary" "20 (10P + 10E)"
    assert_eq "$cpu_freq_str" "3.90 GHz"

    MACHINE_REPORT_LSCPU_FILE="$REPO/tests/fixtures/lscpu-xeon.txt"
    MACHINE_REPORT_NPROC=32
    collect_cpu
    assert_eq "$cpu_model" "Intel Xeon CPU E5-2670 0"
    assert_eq "$cpu_arch" ""
    assert_eq "$cpu_summary" "32 threads / 16 cores / 2 sockets"
}

@test "spark clock formatter rounds to whole megahertz" {
    # shellcheck disable=SC1091
    source "$REPO/spark.sh"
    assert_eq "$(format_clock 2411)" "2411 MHz"
    assert_eq "$(format_clock "")" "n/a"
}
