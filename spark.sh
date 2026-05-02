#!/bin/bash
# Spark Machine Report
# Forked from TR-100 (U.S. Graphics, BSD-3-Clause).
# Edit this file directly — no config, no abstractions. That's the point.

# ----- Layout (rarely change) -----
MIN_NAME_LEN=5
MAX_NAME_LEN=13
MIN_DATA_LEN=20
MAX_DATA_LEN=32
BORDERS_AND_PADDING=7

# ----- Identity (edit me) -----
report_title="NEWJORDAN"
report_subtitle="DGX SPARK MACHINE REPORT"
cpu_platform="NVIDIA DGX Spark"
last_login_ip_present=0
gpu_present=0

# ============================================================================
#  Utilities
# ============================================================================

max_length() {
    local max_len=0 len
    for str in "$@"; do
        len=${#str}
        (( len > max_len )) && max_len=$len
    done
    if [ $max_len -lt $MAX_DATA_LEN ]; then
        printf '%s' "$max_len"
    else
        printf '%s' "$MAX_DATA_LEN"
    fi
}

set_current_len() {
    CURRENT_LEN=$(max_length                                     \
        "$report_title"                                          \
        "$report_subtitle"                                       \
        "$os_name"                                               \
        "$os_kernel"                                             \
        "$net_hostname"                                          \
        "$net_machine_ip"                                        \
        "$net_client_ip"                                         \
        "$net_current_user"                                      \
        "$cpu_model"                                             \
        "$cpu_cores_summary"                                     \
        "$cpu_platform"                                          \
        "$cpu_freq GHz"                                          \
        "$cpu_1min_bar_graph"                                    \
        "$cpu_5min_bar_graph"                                    \
        "$cpu_15min_bar_graph"                                   \
        "$gpu_name"                                              \
        "$gpu_util_bar"                                          \
        "$gpu_temp_str"                                          \
        "$gpu_power_str"                                         \
        "$gpu_clock_str"                                         \
        "$root_used_gb/$root_total_gb GB [$disk_percent%]"       \
        "$disk_bar_graph"                                        \
        "${mem_used_gb}/${mem_total_gb} GiB [${mem_percent}%]"   \
        "${mem_bar_graph}"                                       \
        "$last_login_time"                                       \
        "$last_login_ip"                                         \
        "$sys_uptime"                                            \
    )
}

PRINT_HEADER() {
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local top="┌" bottom="├"
    for (( i = 0; i < length - 2; i++ )); do
        top+="┬"; bottom+="┴"
    done
    top+="┐"; bottom+="┤"
    printf '%s\n' "$top"
    printf '%s\n' "$bottom"
}

PRINT_CENTERED_DATA() {
    local max_len=$((CURRENT_LEN+MAX_NAME_LEN-BORDERS_AND_PADDING))
    local text="$1"
    local total_width=$((max_len + 12))
    local text_len=${#text}
    local padding_left=$(( (total_width - text_len) / 2 ))
    local padding_right=$(( total_width - text_len - padding_left ))
    printf "│%${padding_left}s%s%${padding_right}s│\n" "" "$text" ""
}

PRINT_DIVIDER() {
    local side="$1"
    case "$side" in
        "top")    local left_symbol="├" middle_symbol="┬" right_symbol="┤" ;;
        "bottom") local left_symbol="└" middle_symbol="┴" right_symbol="┘" ;;
        *)        local left_symbol="├" middle_symbol="┼" right_symbol="┤" ;;
    esac
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local divider="$left_symbol"
    for (( i = 0; i < length - 3; i++ )); do
        divider+="─"
        [ "$i" -eq 14 ] && divider+="$middle_symbol"
    done
    divider+="$right_symbol"
    printf '%s\n' "$divider"
}

PRINT_DATA() {
    local name="$1"
    local data="$2"
    local max_data_len=$CURRENT_LEN
    local name_len=${#name}
    if (( name_len < MIN_NAME_LEN )); then
        name=$(printf "%-${MIN_NAME_LEN}s" "$name")
    elif (( name_len > MAX_NAME_LEN )); then
        name=$(echo "$name" | cut -c 1-$((MAX_NAME_LEN-3)))...
    else
        name=$(printf "%-${MAX_NAME_LEN}s" "$name")
    fi
    local data_len=${#data}
    if (( data_len >= MAX_DATA_LEN || data_len == MAX_DATA_LEN-1 )); then
        data=$(echo "$data" | cut -c 1-$((MAX_DATA_LEN-3-2)))...
    else
        data=$(printf "%-${max_data_len}s" "$data")
    fi
    printf "│ %-${MAX_NAME_LEN}s │ %s │\n" "$name" "$data"
}

PRINT_FOOTER() {
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local footer="└"
    for (( i = 0; i < length - 3; i++ )); do
        footer+="─"
        [ "$i" -eq 14 ] && footer+="┴"
    done
    footer+="┘"
    printf '%s\n' "$footer"
}

bar_graph() {
    local percent num_blocks
    local width=$CURRENT_LEN
    local graph=""
    local used=$1 total=$2
    if (( $(awk "BEGIN { print ($total <= 0) }") )); then
        percent=0
    else
        percent=$(awk -v u="$used" -v t="$total" 'BEGIN { printf "%.2f", (u/t)*100 }')
    fi
    num_blocks=$(awk -v p="$percent" -v w="$width" 'BEGIN { printf "%d", (p/100)*w }')
    for (( i = 0; i < num_blocks; i++ )); do graph+="█"; done
    for (( i = num_blocks; i < width; i++ )); do graph+="░"; done
    printf "%s" "${graph}"
}

get_ip_addr() {
    local ipv4_address="" ipv6_address=""
    if command -v ip &>/dev/null; then
        ipv4_address=$(ip -o -4 addr show 2>/dev/null | awk '
            $2 != "lo" && $2 !~ /^docker/ && $2 !~ /^br-/ && $2 !~ /^veth/ \
            { split($4, a, "/"); if (!seen++) print a[1] }')
        if [ -z "$ipv4_address" ]; then
            ipv6_address=$(ip -o -6 addr show 2>/dev/null | awk '
                $2 != "lo" && $2 !~ /^docker/ && $2 !~ /^br-/ \
                { split($4, a, "/"); if (!seen++) print a[1] }')
        fi
    elif command -v ifconfig &>/dev/null; then
        ipv4_address=$(ifconfig | awk '
            /^[a-z]/ {iface=$1}
            iface != "lo:" && iface !~ /^docker/ && /inet / && !found_ipv4 {found_ipv4=1; print $2}')
    fi
    if [ -z "$ipv4_address" ] && [ -z "$ipv6_address" ]; then
        printf '%s' "No IP found"
    else
        printf '%s' "${ipv4_address:-$ipv6_address}"
    fi
}

# ============================================================================
#  Data collection
# ============================================================================

# OS / kernel
source /etc/os-release
os_name="${NAME} ${VERSION_ID} ${VERSION_CODENAME^}"
os_kernel="$(uname -s) $(uname -r)"

# Network / user
net_current_user=$(whoami)
if command -v hostname &>/dev/null; then
    net_hostname=$(hostname -f 2>/dev/null || hostname)
else
    net_hostname=$(uname -n)
fi
[ -z "$net_hostname" ] && net_hostname="Not Defined"
net_machine_ip=$(get_ip_addr)
net_client_ip=$(who am i 2>/dev/null | awk '{print $5}' | tr -d '()')
[ -z "$net_client_ip" ] && net_client_ip="Not connected"
mapfile -t net_dns_ip < <(grep '^nameserver [0-9.]' /etc/resolv.conf 2>/dev/null | awk '{print $2}')

# CPU — Spark has hybrid cores, lscpu prints two "Model name" lines
mapfile -t cpu_model_names < <(lscpu | awk -F: '
    /Model name/ { sub(/^ +/, "", $2); sub(/ +$/, "", $2); print $2 }')
if [ "${#cpu_model_names[@]}" -ge 2 ]; then
    cpu_model="NVIDIA GB10 Grace Blackwell"
    cpu_cluster_label="${cpu_model_names[0]} + ${cpu_model_names[1]}"
else
    cpu_model="${cpu_model_names[0]:-Unknown CPU}"
    cpu_cluster_label=""
fi

# Cores per cluster (lscpu prints "Core(s) per socket" once per cluster on hybrid)
mapfile -t cluster_cores < <(lscpu | awk -F: '
    /Core\(s\) per socket/ { gsub(/ /, "", $2); print $2 }')
cpu_cores=$(nproc --all)
if [ "${#cluster_cores[@]}" -ge 2 ]; then
    cpu_cores_summary="${cpu_cores} (${cluster_cores[0]}P + ${cluster_cores[1]}E)"
else
    cpu_cores_summary="${cpu_cores} cores"
fi

# Frequency — aarch64 has no "cpu MHz" in /proc/cpuinfo; use lscpu max
cpu_freq_mhz=$(lscpu | awk -F: '/CPU max MHz/ { gsub(/ /, "", $2); print $2; exit }')
if [ -z "$cpu_freq_mhz" ]; then
    cpu_freq_mhz=$(lscpu | awk -F: '/CPU\(s\) scaling MHz/ { gsub(/[ %]/, "", $2); print $2; exit }')
fi
[ -z "$cpu_freq_mhz" ] && cpu_freq_mhz=0
cpu_freq=$(awk -v m="$cpu_freq_mhz" 'BEGIN { printf "%.2f", m/1000 }')

# Load
load_avg_1min=$(uptime  | awk -F'load average: ' '{print $2}' | cut -d ',' -f1 | tr -d ' ')
load_avg_5min=$(uptime  | awk -F'load average: ' '{print $2}' | cut -d ',' -f2 | tr -d ' ')
load_avg_15min=$(uptime | awk -F'load average: ' '{print $2}' | cut -d ',' -f3 | tr -d ' ')

# Memory (unified on Spark — same pool as GPU)
mem_total=$(grep 'MemTotal'     /proc/meminfo | awk '{print $2}')
mem_available=$(grep 'MemAvailable' /proc/meminfo | awk '{print $2}')
mem_used=$((mem_total - mem_available))
mem_percent=$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN { printf "%.2f", (u/t)*100 }')
mem_total_gb=$(awk -v k="$mem_total"     'BEGIN { printf "%.2f", k/(1024*1024) }')
mem_used_gb=$(awk  -v k="$mem_used"      'BEGIN { printf "%.2f", k/(1024*1024) }')

# Disk (root /)
root_used=$(df -m /  | awk 'NR==2 {print $3}')
root_total=$(df -m / | awk 'NR==2 {print $2}')
root_total_gb=$(awk -v t="$root_total" 'BEGIN { printf "%.2f", t/1024 }')
root_used_gb=$(awk  -v u="$root_used"  'BEGIN { printf "%.2f", u/1024 }')
disk_percent=$(awk  -v u="$root_used" -v t="$root_total" 'BEGIN { printf "%.2f", (u/t)*100 }')

# GPU — GB10 reports [N/A] for memory.total/power.limit (unified memory),
# but utilization, temperature, power.draw, gfx clock all work.
if command -v nvidia-smi &>/dev/null; then
    gpu_present=1
    gpu_csv=$(nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,power.draw,clocks.current.graphics \
        --format=csv,noheader,nounits 2>/dev/null | head -1)
    IFS=',' read -r gpu_name_raw gpu_util_raw gpu_temp_raw gpu_power_raw gpu_clock_raw <<<"$gpu_csv"
    gpu_name=$(echo "$gpu_name_raw"  | sed 's/^ *//;s/ *$//')
    gpu_util=$(echo "$gpu_util_raw"  | tr -dc '0-9.')
    gpu_temp=$(echo "$gpu_temp_raw"  | tr -dc '0-9.')
    gpu_power=$(echo "$gpu_power_raw" | tr -dc '0-9.')
    gpu_clock=$(echo "$gpu_clock_raw" | tr -dc '0-9.')
    [ -z "$gpu_util" ]  && gpu_util=0
    [ -z "$gpu_temp" ]  && gpu_temp=0
    [ -z "$gpu_power" ] && gpu_power=0
    [ -z "$gpu_clock" ] && gpu_clock=0
    gpu_temp_str="${gpu_temp} °C"
    gpu_power_str=$(awk -v w="$gpu_power" 'BEGIN { printf "%.2f W", w }')
    gpu_clock_str=$(awk -v c="$gpu_clock" 'BEGIN { printf "%.0f MHz", c }')
fi

# Last login + uptime
# Ubuntu 24.04 lastlog row formats:
#   With IP:  USER PORT IP   DAY MON D HH:MM:SS TZ    YEAR
#   No IP:    USER PORT      DAY MON D HH:MM:SS TZ    YEAR
last_login_row=$(lastlog -u "$USER" 2>/dev/null | awk 'NR==2')
last_login_ip=$(echo "$last_login_row" | awk '{print $3}')
if [[ "$last_login_row" == *"Never logged in"* ]]; then
    last_login_time="Never logged in"
    last_login_ip=""
elif [[ "$last_login_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    last_login_ip_present=1
    last_login_time=$(echo "$last_login_row" | awk '{print $4, $5, $6, $7, $9}')
else
    last_login_ip=""
    last_login_time=$(echo "$last_login_row" | awk '{print $3, $4, $5, $6, $8}')
fi
sys_uptime=$(uptime -p | sed 's/up\s*//; s/\s*day\(s*\)/d/; s/\s*hour\(s*\)/h/; s/\s*minute\(s*\)/m/')

# Compute column width before drawing bars
set_current_len

# Bars (need CURRENT_LEN)
cpu_1min_bar_graph=$(bar_graph  "$load_avg_1min"  "$cpu_cores")
cpu_5min_bar_graph=$(bar_graph  "$load_avg_5min"  "$cpu_cores")
cpu_15min_bar_graph=$(bar_graph "$load_avg_15min" "$cpu_cores")
mem_bar_graph=$(bar_graph "$mem_used"  "$mem_total")
disk_bar_graph=$(bar_graph "$root_used" "$root_total")
if [ $gpu_present -eq 1 ]; then
    gpu_util_bar=$(bar_graph "$gpu_util" 100)
fi

# ============================================================================
#  Render
# ============================================================================

PRINT_HEADER
PRINT_CENTERED_DATA "$report_title"
PRINT_CENTERED_DATA "$report_subtitle"
PRINT_DIVIDER "top"
PRINT_DATA "OS"         "$os_name"
PRINT_DATA "KERNEL"     "$os_kernel"
PRINT_DIVIDER
PRINT_DATA "HOSTNAME"   "$net_hostname"
PRINT_DATA "MACHINE IP" "$net_machine_ip"
PRINT_DATA "CLIENT  IP" "$net_client_ip"
for dns_num in "${!net_dns_ip[@]}"; do
    PRINT_DATA "DNS  IP $((dns_num + 1))" "${net_dns_ip[dns_num]}"
done
PRINT_DATA "USER"       "$net_current_user"
PRINT_DIVIDER
PRINT_DATA "PROCESSOR"  "$cpu_model"
[ -n "$cpu_cluster_label" ] && PRINT_DATA "ARCH"       "$cpu_cluster_label"
PRINT_DATA "CORES"      "$cpu_cores_summary"
PRINT_DATA "PLATFORM"   "$cpu_platform"
PRINT_DATA "CPU FREQ"   "$cpu_freq GHz"
PRINT_DATA "LOAD  1m"   "$cpu_1min_bar_graph"
PRINT_DATA "LOAD  5m"   "$cpu_5min_bar_graph"
PRINT_DATA "LOAD 15m"   "$cpu_15min_bar_graph"
if [ $gpu_present -eq 1 ]; then
    PRINT_DIVIDER
    PRINT_DATA "GPU"        "$gpu_name"
    PRINT_DATA "GPU UTIL"   "$gpu_util_bar"
    PRINT_DATA "GPU TEMP"   "$gpu_temp_str"
    PRINT_DATA "GPU POWER"  "$gpu_power_str"
    PRINT_DATA "GPU CLOCK"  "$gpu_clock_str"
fi
PRINT_DIVIDER
PRINT_DATA "VOLUME"     "$root_used_gb/$root_total_gb GB [$disk_percent%]"
PRINT_DATA "DISK USAGE" "$disk_bar_graph"
PRINT_DIVIDER
PRINT_DATA "MEMORY"     "${mem_used_gb}/${mem_total_gb} GiB [${mem_percent}%]"
PRINT_DATA "USAGE"      "${mem_bar_graph}"
PRINT_DIVIDER
PRINT_DATA "LAST LOGIN" "$last_login_time"
[ $last_login_ip_present -eq 1 ] && PRINT_DATA "" "$last_login_ip"
PRINT_DATA "UPTIME"     "$sys_uptime"
PRINT_DIVIDER "bottom"
