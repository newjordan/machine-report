#!/usr/bin/env bash

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_eq() {
    if [[ "$1" != "$2" ]]; then
        printf 'expected [%s]\n     got [%s]\n' "$2" "$1" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'missing [%s]\n%s\n' "$needle" "$haystack" >&2
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'unexpected [%s]\n' "$needle" >&2
        return 1
    fi
}

# Every line of a banner has the same width, the column junction lines up,
# and data rows put │ in that column. Measured in a UTF-8 locale so block
# characters count as one cell.
assert_box_aligned() {
    (
        export LC_ALL=C.UTF-8
        local line width=0 seen=0 w last prefix idx junction=-1
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            w=${#line}
            if (( seen == 0 )); then
                width=$w
                seen=1
            elif (( w != width )); then
                printf 'width %d != %d: %s\n' "$w" "$width" "$line" >&2
                return 1
            fi
            last=${line: -1}
            case "${line:0:1}" in
                ┌|├|└|│) ;;
                *)
                    printf 'bad left border: %s\n' "$line" >&2
                    return 1
                    ;;
            esac
            case "$last" in
                ┐|┤|┘|│) ;;
                *)
                    printf 'bad right border: %s\n' "$line" >&2
                    return 1
                    ;;
            esac
            if [[ "$line" == *"─"* ]]; then
                prefix=${line%%[┼┬┴]*}
                if [[ "$prefix" != "$line" ]]; then
                    idx=${#prefix}
                    if (( junction < 0 )); then
                        junction=$idx
                    elif (( idx != junction )); then
                        printf 'junction %d != %d on %s\n' "$idx" "$junction" "$line" >&2
                        return 1
                    fi
                fi
            fi
        done <<<"$1"
        if (( seen == 0 )); then
            printf 'empty banner\n' >&2
            return 1
        fi
        if (( junction < 0 )); then
            printf 'no column junction\n' >&2
            return 1
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" == │*" │ "* ]] || continue
            if [[ "${line:junction:1}" != "│" ]]; then
                printf 'data junction mismatch on %s\n' "$line" >&2
                return 1
            fi
        done <<<"$1"
    )
}

use_fixtures() {
    local dir="$REPO/tests/fixtures"
    export MACHINE_REPORT_OS_RELEASE="$dir/os-release"
    export MACHINE_REPORT_MEMINFO="$dir/meminfo"
    export MACHINE_REPORT_LOADAVG="$dir/loadavg"
    export MACHINE_REPORT_RESOLV="$dir/resolv.conf"
    export MACHINE_REPORT_CPUINFO="$dir/cpuinfo"
    export MACHINE_REPORT_UPTIME_FILE="$dir/uptime"
    export MACHINE_REPORT_LSCPU_FILE="$dir/lscpu-xeon.txt"
    export MACHINE_REPORT_DF_FILE="$dir/df.txt"
    export MACHINE_REPORT_LASTLOG_FILE="$dir/lastlog.txt"
    export MACHINE_REPORT_NPROC=32
    export MACHINE_REPORT_UNAME_KERNEL=Linux
    export MACHINE_REPORT_UNAME_RELEASE=9.9.9-test
    export MACHINE_REPORT_UNAME_NODE=testhost
    export MACHINE_REPORT_USER=frosty
    export MACHINE_REPORT_IP=10.1.2.3
    export MACHINE_REPORT_GPU_CSV=
    unset SSH_CONNECTION SSH_CLIENT
}

lastlog_header() {
    printf '%-17s%-9s%-43s%s' "Username" "Port" "From" "Latest"
}
