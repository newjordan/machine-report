#!/bin/bash
# WSL2 Machine Report
# Fork of the Linux workstation banner for Windows Subsystem for Linux 2.
# The GPU panel appears only when nvidia-smi works inside WSL.
# Edit the identity block and the render section at the bottom.

# ----- Layout -----
# Label column is exactly MAX_NAME_LEN characters.
# Data column is at least MIN_DATA_LEN and at most MAX_DATA_LEN.
# BORDERS_AND_PADDING is the punctuation around those columns:
#   "│ " + " │ " + " │"  == 7 cells. Leave it alone unless the printf changes.
MAX_NAME_LEN=13
MIN_DATA_LEN=24
MAX_DATA_LEN=48
BORDERS_AND_PADDING=7

# ----- Identity (edit per host) -----
report_title="NEWJORDAN"
report_subtitle="WSL2 MACHINE REPORT"
cpu_platform="WSL2 on Windows"

# Test hooks. Unset on a normal login; they are not a configuration system.
#   MACHINE_REPORT_OS_RELEASE MACHINE_REPORT_MEMINFO MACHINE_REPORT_LOADAVG
#   MACHINE_REPORT_RESOLV MACHINE_REPORT_CPUINFO MACHINE_REPORT_UPTIME_FILE
#   MACHINE_REPORT_LSCPU_FILE MACHINE_REPORT_DF_FILE MACHINE_REPORT_LASTLOG_FILE
#   MACHINE_REPORT_NPROC MACHINE_REPORT_UNAME_KERNEL MACHINE_REPORT_UNAME_RELEASE
#   MACHINE_REPORT_UNAME_NODE MACHINE_REPORT_USER MACHINE_REPORT_IP
#   MACHINE_REPORT_GPU_CSV  (set, even to empty, to skip nvidia-smi)

# ============================================================================
#  Utilities
# ============================================================================

ensure_utf8_locale() {
    # ${#string} counts bytes in the C locale and splits the box. Force a UTF-8
    # locale for this process only; parsers that must be English pass LC_ALL=C.
    if locale -a 2>/dev/null | grep -qiE '^C\.(utf8|UTF-8)$'; then
        export LANG=C.UTF-8
        export LC_ALL=C.UTF-8
    fi
}

trim() {
    local s="${1-}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

fit_width() {
    local text="${1-}" width="${2:-0}" len
    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        width=0
    fi
    len=${#text}
    if (( len > width )); then
        if (( width <= 3 )); then
            printf '%s' "${text:0:width}"
        else
            printf '%s...' "${text:0:width-3}"
        fi
    elif (( len < width )); then
        printf '%s%*s' "$text" $((width - len)) ""
    else
        printf '%s' "$text"
    fi
}

repeat_char() {
    local char="$1" count="$2" pad
    if [[ ! "$count" =~ ^[0-9]+$ ]] || (( count <= 0 )); then
        printf ''
        return
    fi
    pad=$(printf '%*s' "$count" '')
    printf '%s' "${pad// /$char}"
}

max_length() {
    local max_len=0 len s min max
    for s in "$@"; do
        len=${#s}
        if (( len > max_len )); then
            max_len=$len
        fi
    done
    min=$MIN_DATA_LEN
    max=$MAX_DATA_LEN
    if (( min > max )); then
        min=$max
    fi
    if (( max_len < min )); then
        max_len=$min
    fi
    if (( max_len > max )); then
        max_len=$max
    fi
    printf '%s' "$max_len"
}

table_width() {
    printf '%s' $((CURRENT_LEN + MAX_NAME_LEN + BORDERS_AND_PADDING))
}

print_header() {
    local width inner
    width=$(table_width)
    inner=$(repeat_char "┬" $((width - 2)))
    printf '┌%s┐\n' "$inner"
    inner=$(repeat_char "┴" $((width - 2)))
    printf '├%s┤\n' "$inner"
}

print_centered() {
    local text="$1" inner len pad_left pad_right
    inner=$((CURRENT_LEN + MAX_NAME_LEN + BORDERS_AND_PADDING - 2))
    len=${#text}
    if (( len > inner )); then
        text=$(fit_width "$text" "$inner")
        len=${#text}
    fi
    pad_left=$(( (inner - len) / 2 ))
    pad_right=$(( inner - len - pad_left ))
    printf '│%*s%s%*s│\n' "$pad_left" "" "$text" "$pad_right" ""
}

print_divider() {
    local side="${1:-middle}" left middle right width junction left_dashes right_dashes
    case "$side" in
        top)    left="├"; middle="┬"; right="┤" ;;
        bottom) left="└"; middle="┴"; right="┘" ;;
        *)      left="├"; middle="┼"; right="┤" ;;
    esac
    width=$(table_width)
    # The inner │ sits after "│ " + label + " ".
    junction=$((MAX_NAME_LEN + 3))
    left_dashes=$((junction - 1))
    right_dashes=$((width - junction - 2))
    printf '%s%s%s%s%s\n' \
        "$left" \
        "$(repeat_char "─" "$left_dashes")" \
        "$middle" \
        "$(repeat_char "─" "$right_dashes")" \
        "$right"
}

print_data() {
    local name="$1" data="$2"
    printf '│ %s │ %s │\n' \
        "$(fit_width "$name" "$MAX_NAME_LEN")" \
        "$(fit_width "$data" "$CURRENT_LEN")"
}

bar_graph() {
    # Filled cells are the share of total, clamped to 0..100% so a load
    # average above the CPU count cannot blow out the right border.
    local used="${1:-0}" total="${2:-0}" width="$CURRENT_LEN"
    LC_ALL=C awk -v u="$used" -v t="$total" -v w="$width" 'BEGIN {
        if (w+0 < 1) exit
        n = 0
        if ((t+0) > 0 && (u+0) > 0) {
            p = (u+0) / (t+0) * 100
            if (p < 0) p = 0
            if (p > 100) p = 100
            n = int(p / 100 * w + 0.5)
            if (n > w) n = w
            if (n < 0) n = 0
        }
        full = "█"
        empty = "░"
        for (i = 0; i < n; i++) printf "%s", full
        for (i = n; i < w; i++) printf "%s", empty
    }'
}

plural_word() {
    if [[ "$1" == "1" ]]; then
        printf '%s' "$2"
    else
        printf '%ss' "$2"
    fi
}

first_number() {
    LC_ALL=C awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^-?[0-9]/) { print $i+0; exit }
            }
        }
    ' <<<"${1-}"
}

numeric_or_blank() {
    local raw num
    raw=$(trim "${1-}")
    if [[ -z "$raw" || "$raw" == *N/A* || "$raw" == *n/a* ]]; then
        printf ''
        return
    fi
    num=$(printf '%s' "$raw" | tr -cd '0-9.')
    printf '%s' "$num"
}

format_percent() {
    LC_ALL=C awk -v u="${1:-0}" -v t="${2:-0}" 'BEGIN {
        if (t+0 <= 0) { printf "0.0"; exit }
        printf "%.1f", ((u+0)/(t+0))*100
    }'
}

format_pair_gib() {
    local used="$1" total="$2" divisor="$3" used_s total_s pct
    if ! LC_ALL=C awk -v t="$total" 'BEGIN { exit !((t+0) > 0) }'; then
        printf 'n/a'
        return
    fi
    used_s=$(LC_ALL=C awk -v v="$used" -v d="$divisor" 'BEGIN { printf "%.2f", (v+0)/d }')
    total_s=$(LC_ALL=C awk -v v="$total" -v d="$divisor" 'BEGIN { printf "%.2f", (v+0)/d }')
    pct=$(format_percent "$used" "$total")
    printf '%s/%s GiB [%s%%]' "$used_s" "$total_s" "$pct"
}

format_power() {
    local w="${1-}"
    if [[ -z "$w" ]]; then
        printf 'n/a'
        return
    fi
    LC_ALL=C awk -v w="$w" 'BEGIN { printf "%.2f W", w+0 }'
}

format_temp() {
    local t="${1-}"
    if [[ -z "$t" ]]; then
        printf 'n/a'
        return
    fi
    printf '%s °C' "$t"
}

format_uptime_seconds() {
    local raw="${1%%.*}" d h m parts=()
    if [[ ! "$raw" =~ ^[0-9]+$ ]]; then
        printf 'n/a'
        return
    fi
    d=$((raw / 86400))
    h=$(((raw % 86400) / 3600))
    m=$(((raw % 3600) / 60))
    if (( d > 0 )); then
        parts+=("${d}d")
    fi
    if (( h > 0 )); then
        parts+=("${h}h")
    fi
    if (( m > 0 || ${#parts[@]} == 0 )); then
        parts+=("${m}m")
    fi
    local IFS=' '
    printf '%s' "${parts[*]}"
}

mhz_to_ghz() {
    local mhz="${1-}"
    if [[ -z "$mhz" ]]; then
        printf 'n/a'
        return
    fi
    LC_ALL=C awk -v m="$mhz" 'BEGIN {
        if (m+0 <= 0) { printf "n/a"; exit }
        printf "%.2f GHz", (m+0)/1000
    }'
}

clean_cpu_model() {
    local s
    s=$(trim "${1-}")
    s=${s//"(R)"/}
    s=${s//"(TM)"/}
    s=${s//"(tm)"/}
    s=${s//"CPU @"/}
    s=${s//@/}
    s=$(printf '%s' "$s" | tr -s '[:space:]' ' ')
    s=$(trim "$s")
    s=$(printf '%s' "$s" | sed -E 's/ [0-9]+([.][0-9]+)?[[:space:]]*[Gg][Hh][Zz]$//')
    trim "$s"
}

format_cpu_summary() {
    local threads="$1" cps="${2:-0}" sockets="${3:-0}" physical
    if [[ ! "$threads" =~ ^[0-9]+$ ]]; then
        threads=1
    fi
    if [[ ! "$cps" =~ ^[0-9]+$ ]]; then
        cps=0
    fi
    if [[ ! "$sockets" =~ ^[0-9]+$ ]]; then
        sockets=0
    fi
    if (( cps < 1 || sockets < 1 )); then
        printf '%s %s' "$threads" "$(plural_word "$threads" thread)"
        return
    fi
    physical=$((cps * sockets))
    if (( threads > physical )); then
        printf '%s %s / %s %s / %s %s' \
            "$threads" "$(plural_word "$threads" thread)" \
            "$physical" "$(plural_word "$physical" core)" \
            "$sockets" "$(plural_word "$sockets" socket)"
    else
        printf '%s %s / %s %s' \
            "$physical" "$(plural_word "$physical" core)" \
            "$sockets" "$(plural_word "$sockets" socket)"
    fi
}

# ============================================================================
#  Parsing
# ============================================================================

lscpu_value() {
    local key="$1" text="$2"
    printf '%s\n' "$text" | LC_ALL=C awk -F: -v k="$key" '
        {
            key = $1
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key == k) {
                val = substr($0, index($0, ":") + 1)
                gsub(/^[ \t]+|[ \t]+$/, "", val)
                print val
                exit
            }
        }
    '
}

read_lscpu_text() {
    if [[ -n "${MACHINE_REPORT_LSCPU_FILE:-}" ]]; then
        cat "$MACHINE_REPORT_LSCPU_FILE"
        return
    fi
    LC_ALL=C lscpu 2>/dev/null || true
}

cpu_freq_mhz_from_lscpu() {
    local text="$1" mhz cpuinfo
    mhz=$(lscpu_value "CPU max MHz" "$text")
    mhz=$(first_number "$mhz")
    if [[ -z "$mhz" || "$mhz" == "0" ]]; then
        mhz=$(lscpu_value "CPU MHz" "$text")
        mhz=$(first_number "$mhz")
    fi
    if [[ -z "$mhz" || "$mhz" == "0" ]]; then
        cpuinfo="${MACHINE_REPORT_CPUINFO:-/proc/cpuinfo}"
        if [[ -r "$cpuinfo" ]]; then
            mhz=$(LC_ALL=C awk -F: '$1 ~ /^[ \t]*cpu MHz/ {
                gsub(/^[ \t]+/, "", $2); print $2; exit
            }' "$cpuinfo")
            mhz=$(first_number "$mhz")
        fi
    fi
    printf '%s' "$mhz"
}

read_nproc() {
    local n="${MACHINE_REPORT_NPROC:-}"
    if [[ -z "$n" ]]; then
        n=$(nproc 2>/dev/null || true)
    fi
    if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n < 1 )); then
        n=1
    fi
    printf '%s' "$n"
}

collect_cpu() {
    local text threads cps sockets model
    text=$(read_lscpu_text)
    model=$(lscpu_value "Model name" "$text")
    model=$(clean_cpu_model "$model")
    if [[ -z "$model" ]]; then
        model="Unknown CPU"
    fi
    threads=$(read_nproc)
    cps=$(first_number "$(lscpu_value "Core(s) per socket" "$text")")
    sockets=$(first_number "$(lscpu_value "Socket(s)" "$text")")
    cpu_model=$model
    cpu_summary=$(format_cpu_summary "$threads" "${cps:-0}" "${sockets:-0}")
    cpu_threads=$threads
    cpu_freq_str=$(mhz_to_ghz "$(cpu_freq_mhz_from_lscpu "$text")")
}

read_os_name() {
    local f="${MACHINE_REPORT_OS_RELEASE:-/etc/os-release}"
    if [[ ! -r "$f" ]]; then
        printf 'Unknown'
        return
    fi
    (
        # shellcheck disable=SC1090
        . "$f"
        local code="${VERSION_CODENAME:-}"
        if [[ -n "$code" ]]; then
            code="${code^}"
        fi
        printf '%s' "${NAME:-Unknown}${VERSION_ID:+ ${VERSION_ID}}${code:+ ${code}}"
    )
}

read_kernel() {
    local s="${MACHINE_REPORT_UNAME_KERNEL:-}" r="${MACHINE_REPORT_UNAME_RELEASE:-}"
    if [[ -z "$s" ]]; then
        s=$(uname -s)
    fi
    if [[ -z "$r" ]]; then
        r=$(uname -r)
    fi
    printf '%s %s' "$s" "$r"
}

read_hostname() {
    if [[ -n "${MACHINE_REPORT_UNAME_NODE:-}" ]]; then
        printf '%s' "$MACHINE_REPORT_UNAME_NODE"
    else
        uname -n
    fi
}

read_user() {
    if [[ -n "${MACHINE_REPORT_USER:-}" ]]; then
        printf '%s' "$MACHINE_REPORT_USER"
    else
        id -un
    fi
}

read_client_ip() {
    local raw=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        raw="${SSH_CONNECTION%% *}"
    elif [[ -n "${SSH_CLIENT:-}" ]]; then
        raw="${SSH_CLIENT%% *}"
    else
        raw=$(who am i 2>/dev/null | awk '{ print $5 }' | tr -d '()' || true)
    fi
    raw=$(trim "$raw")
    if [[ -z "$raw" || "$raw" == ":0" ]]; then
        printf 'local'
    else
        printf '%s' "$raw"
    fi
}

iface_is_virtual() {
    case "$1" in
        lo|docker*|br-*|veth*|virbr*|vnet*|tun*|tap*|wg*|tailscale*|zt*|cni*|flannel*|cali*|lxc*|podman*|vboxnet*|vmnet*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ip_global_addrs() {
    local family="$1"
    command -v ip >/dev/null 2>&1 || return 0
    ip -o "-$family" addr show scope global 2>/dev/null | LC_ALL=C awk '{
        split($4, a, "/")
        addr = a[1]
        sub(/%.*$/, "", addr)
        print $2, addr
    }' || true
}

ifconfig_ipv4s() {
    command -v ifconfig >/dev/null 2>&1 || return 0
    ifconfig 2>/dev/null | LC_ALL=C awk '
        /^[^[:space:]]/ { iface = $1; sub(/:$/, "", iface) }
        $1 == "inet" {
            addr = $2
            sub(/^addr:/, "", addr)
            print iface, addr
        }
    ' || true
}

get_ip_addr() {
    local iface addr ip ips_line
    local -a ips=()
    while read -r iface addr; do
        if iface_is_virtual "$iface"; then
            continue
        fi
        case "$addr" in
            ""|127.*|169.254.*) continue ;;
        esac
        printf '%s' "$addr"
        return 0
    done < <(ip_global_addrs 4)
    while read -r iface addr; do
        if iface_is_virtual "$iface"; then
            continue
        fi
        case "$addr" in
            ""|fe80:*|::1) continue ;;
        esac
        printf '%s' "$addr"
        return 0
    done < <(ip_global_addrs 6)
    while read -r iface addr; do
        if iface_is_virtual "$iface"; then
            continue
        fi
        case "$addr" in
            ""|127.*|169.254.*) continue ;;
        esac
        printf '%s' "$addr"
        return 0
    done < <(ifconfig_ipv4s)
    if ips_line=$(hostname -I 2>/dev/null); then
        read -r -a ips <<<"$ips_line"
        for ip in "${ips[@]}"; do
            case "$ip" in
                127.*|169.254.*|fe80:*) continue ;;
            esac
            printf '%s' "$ip"
            return 0
        done
    fi
    printf '%s' "No IP found"
}

read_machine_ip() {
    if [[ -n "${MACHINE_REPORT_IP:-}" ]]; then
        printf '%s' "$MACHINE_REPORT_IP"
    else
        get_ip_addr
    fi
}

read_dns() {
    local f="${MACHINE_REPORT_RESOLV:-/etc/resolv.conf}"
    [[ -r "$f" ]] || return 0
    LC_ALL=C awk '$1 == "nameserver" && $2 != "" { print $2 }' "$f"
}

read_loadavg() {
    local f="${MACHINE_REPORT_LOADAVG:-/proc/loadavg}" a b c
    if [[ -r "$f" ]]; then
        read -r a b c _ < "$f" || true
    fi
    [[ -n "${a:-}" ]] || a=0
    [[ -n "${b:-}" ]] || b=0
    [[ -n "${c:-}" ]] || c=0
    printf '%s %s %s' "$a" "$b" "$c"
}

read_mem_kb() {
    local f="${MACHINE_REPORT_MEMINFO:-/proc/meminfo}"
    if [[ ! -r "$f" ]]; then
        printf '0 0'
        return
    fi
    LC_ALL=C awk '
        $1 == "MemTotal:" { t = $2 }
        $1 == "MemAvailable:" { a = $2 }
        $1 == "MemFree:" { free = $2 }
        $1 == "Buffers:" { b = $2 }
        $1 == "Cached:" { c = $2 }
        END {
            if (t == "") t = 0
            if (a == "") a = (free+0) + (b+0) + (c+0)
            u = (t+0) - (a+0)
            if (u < 0) u = 0
            printf "%d %d", u, t+0
        }
    ' "$f"
}

read_disk_mib() {
    local text f="${MACHINE_REPORT_DF_FILE:-}"
    if [[ -n "$f" ]]; then
        text=$(cat "$f")
    else
        text=$(LC_ALL=C df -Pm / 2>/dev/null) || true
    fi
    printf '%s\n' "$text" | LC_ALL=C awk '
        NR > 1 && NF >= 6 && $(NF-3) ~ /^[0-9]+$/ && $(NF-4) ~ /^[0-9]+$/ {
            u = $(NF-3)
            t = $(NF-4)
        }
        END {
            if (u == "") u = 0
            if (t == "") t = 0
            printf "%d %d", u, t
        }
    '
}

read_uptime() {
    local f="${MACHINE_REPORT_UPTIME_FILE:-/proc/uptime}" secs=""
    if [[ ! -r "$f" ]]; then
        printf 'n/a'
        return
    fi
    read -r secs _ < "$f" || true
    format_uptime_seconds "${secs:-0}"
}

parse_lastlog_record() {
    local header="$1" row="$2" from_prefix latest_prefix from_at latest_at from latest pretty
    if [[ -z "$row" ]]; then
        printf 'unavailable\t'
        return
    fi
    if [[ "$row" == *"Never logged in"* ]]; then
        printf 'Never logged in\t'
        return
    fi
    if [[ "$header" != *"From"* || "$header" != *"Latest"* ]]; then
        printf '%s\t' "$(trim "$row")"
        return
    fi
    from_prefix="${header%%From*}"
    latest_prefix="${header%%Latest*}"
    from_at=${#from_prefix}
    latest_at=${#latest_prefix}
    from=$(trim "${row:from_at:latest_at-from_at}")
    latest=$(trim "${row:latest_at}")
    pretty=$(printf '%s\n' "$latest" | LC_ALL=C awk '{
        if (NF >= 6) print $1, $2, $3, $4, $6
        else print $0
    }')
    printf '%s\t%s' "$pretty" "$from"
}

read_last_login() {
    local out header row user
    if [[ -n "${MACHINE_REPORT_LASTLOG_FILE:-}" ]]; then
        if [[ ! -s "$MACHINE_REPORT_LASTLOG_FILE" ]]; then
            printf 'unavailable\t'
            return
        fi
        out=$(cat "$MACHINE_REPORT_LASTLOG_FILE")
    else
        user="${USER:-}"
        if [[ -z "$user" ]]; then
            user=$(id -un)
        fi
        if ! out=$(LC_ALL=C lastlog -u "$user" 2>/dev/null); then
            printf 'unavailable\t'
            return
        fi
    fi
    header=$(printf '%s\n' "$out" | sed -n '1p')
    row=$(printf '%s\n' "$out" | sed -n '2p')
    parse_lastlog_record "$header" "$row"
}

csv_to_tsv() {
    LC_ALL=C awk '
        function trim(s) {
            gsub(/^[ \t"]+|[ \t"]+$/, "", s)
            return s
        }
        {
            n = 0
            field = ""
            inq = 0
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "\"") { inq = !inq; continue }
                if (c == "," && !inq) {
                    n++
                    fields[n] = trim(field)
                    field = ""
                    continue
                }
                field = field c
            }
            n++
            fields[n] = trim(field)
            for (i = 1; i <= n; i++) {
                printf "%s%s", fields[i], (i < n ? "\t" : "\n")
            }
        }
    ' <<<"${1-}"
}

read_gpu() {
    local csv line name util temp power used total
    if [[ -v MACHINE_REPORT_GPU_CSV ]]; then
        csv=$MACHINE_REPORT_GPU_CSV
    else
        command -v nvidia-smi >/dev/null 2>&1 || return 1
        csv=$(LC_ALL=C nvidia-smi \
            --query-gpu=name,utilization.gpu,temperature.gpu,power.draw,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | LC_ALL=C awk 'NR==1 { print; exit }' || true)
    fi
    [[ "$csv" == *,* ]] || return 1
    line=$(csv_to_tsv "$csv")
    IFS=$'\t' read -r name util temp power used total <<<"$line"
    [[ -n "$name" && "$name" != *Failed* ]] || return 1
    util=$(numeric_or_blank "$util")
    temp=$(numeric_or_blank "$temp")
    power=$(numeric_or_blank "$power")
    used=$(numeric_or_blank "$used")
    total=$(numeric_or_blank "$total")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$util" "$temp" "$power" "$used" "$total"
}

# ============================================================================
#  Report
# ============================================================================

main() {
    set -euo pipefail
    ensure_utf8_locale

    local os_name os_kernel net_hostname net_machine_ip net_client_ip net_user
    local mem_used_kb mem_total_kb mem_str disk_used_mib disk_total_mib disk_str
    local load1 load5 load15 login_rec login_time login_from uptime_str
    local gpu_line gpu_present=0 gpu_mem_known=0
    local gpu_name="" gpu_util="0" gpu_temp="" gpu_power="" gpu_mem_used="0" gpu_mem_total="0"
    local gpu_temp_str="" gpu_power_str="" gpu_mem_str=""
    local load1_bar load5_bar load15_bar mem_bar disk_bar gpu_util_bar="" gpu_mem_bar=""
    local dns i
    local -a dns_ips=() width_items=()

    os_name=$(read_os_name)
    os_kernel=$(read_kernel)
    net_hostname=$(read_hostname)
    net_user=$(read_user)
    net_machine_ip=$(read_machine_ip)
    net_client_ip=$(read_client_ip)
    mapfile -t dns_ips < <(read_dns)

    collect_cpu

    read -r load1 load5 load15 <<<"$(read_loadavg)"
    read -r mem_used_kb mem_total_kb <<<"$(read_mem_kb)"
    read -r disk_used_mib disk_total_mib <<<"$(read_disk_mib)"
    mem_str=$(format_pair_gib "$mem_used_kb" "$mem_total_kb" 1048576)
    disk_str=$(format_pair_gib "$disk_used_mib" "$disk_total_mib" 1024)

    login_rec=$(read_last_login)
    IFS=$'\t' read -r login_time login_from <<<"$login_rec"
    uptime_str=$(read_uptime)

    if gpu_line=$(read_gpu); then
        gpu_present=1
        IFS=$'\t' read -r gpu_name gpu_util gpu_temp gpu_power gpu_mem_used gpu_mem_total <<<"$gpu_line"
        gpu_temp_str=$(format_temp "$gpu_temp")
        gpu_power_str=$(format_power "$gpu_power")
        gpu_mem_str=$(format_pair_gib "${gpu_mem_used:-0}" "${gpu_mem_total:-0}" 1024)
        if [[ -n "$gpu_mem_total" && "$gpu_mem_total" != "0" && "$gpu_mem_str" != "n/a" ]]; then
            gpu_mem_known=1
        fi
    fi

    width_items=(
        "$report_title" "$report_subtitle" "$os_name" "$os_kernel"
        "$net_hostname" "$net_machine_ip" "$net_client_ip" "$net_user"
        "$cpu_model" "$cpu_summary" "$cpu_platform" "$cpu_freq_str"
        "$disk_str" "$mem_str" "$login_time" "$login_from" "$uptime_str"
    )
    if ((${#dns_ips[@]})); then
        for dns in "${dns_ips[@]}"; do
            width_items+=("$dns")
        done
    fi
    if (( gpu_present )); then
        width_items+=("$gpu_name" "$gpu_temp_str" "$gpu_power_str")
        if (( gpu_mem_known )); then
            width_items+=("$gpu_mem_str")
        fi
    fi
    CURRENT_LEN=$(max_length "${width_items[@]}")

    load1_bar=$(bar_graph "$load1" "$cpu_threads")
    load5_bar=$(bar_graph "$load5" "$cpu_threads")
    load15_bar=$(bar_graph "$load15" "$cpu_threads")
    mem_bar=$(bar_graph "$mem_used_kb" "$mem_total_kb")
    disk_bar=$(bar_graph "$disk_used_mib" "$disk_total_mib")
    if (( gpu_present )); then
        gpu_util_bar=$(bar_graph "${gpu_util:-0}" 100)
        if (( gpu_mem_known )); then
            gpu_mem_bar=$(bar_graph "${gpu_mem_used:-0}" "${gpu_mem_total:-0}")
        fi
    fi

    # Render. One printf per row on purpose — add a host-specific row here.
    print_header
    print_centered "$report_title"
    print_centered "$report_subtitle"
    print_divider top
    print_data "OS" "$os_name"
    print_data "KERNEL" "$os_kernel"
    print_divider
    print_data "HOSTNAME" "$net_hostname"
    print_data "MACHINE IP" "$net_machine_ip"
    print_data "CLIENT IP" "$net_client_ip"
    if ((${#dns_ips[@]})); then
        i=1
        for dns in "${dns_ips[@]}"; do
            print_data "DNS $i" "$dns"
            i=$((i + 1))
        done
    fi
    print_data "USER" "$net_user"
    print_divider
    print_data "PROCESSOR" "$cpu_model"
    print_data "CORES" "$cpu_summary"
    print_data "PLATFORM" "$cpu_platform"
    print_data "CPU FREQ" "$cpu_freq_str"
    # Two spaces so the "m" in 1m/5m lines up with 15m.
    print_data "LOAD  1m" "$load1_bar"
    print_data "LOAD  5m" "$load5_bar"
    print_data "LOAD 15m" "$load15_bar"
    if (( gpu_present )); then
        print_divider
        print_data "GPU" "$gpu_name"
        print_data "GPU UTIL" "$gpu_util_bar"
        print_data "GPU TEMP" "$gpu_temp_str"
        print_data "GPU POWER" "$gpu_power_str"
        if (( gpu_mem_known )); then
            print_data "GPU MEM" "$gpu_mem_str"
            print_data "GPU USAGE" "$gpu_mem_bar"
        fi
    fi
    print_divider
    print_data "VOLUME" "$disk_str"
    print_data "DISK USAGE" "$disk_bar"
    print_divider
    print_data "MEMORY" "$mem_str"
    print_data "MEM USAGE" "$mem_bar"
    print_divider
    print_data "LAST LOGIN" "$login_time"
    if [[ -n "$login_from" ]]; then
        print_data "LOGIN FROM" "$login_from"
    fi
    print_data "UPTIME" "$uptime_str"
    print_divider bottom
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
