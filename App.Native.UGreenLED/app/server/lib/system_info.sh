#!/bin/bash
# 只读系统信息采集，供 Web 状态页面展示。

SYSTEM_INFO_PROC_ROOT="${SYSTEM_INFO_PROC_ROOT:-/proc}"
SYSTEM_INFO_SYS_ROOT="${SYSTEM_INFO_SYS_ROOT:-/sys}"
SYSTEM_INFO_OS_RELEASE="${SYSTEM_INFO_OS_RELEASE:-/etc/os-release}"
SYSTEM_INFO_HOSTNAME_FILE="${SYSTEM_INFO_HOSTNAME_FILE:-${SYSTEM_INFO_PROC_ROOT}/sys/kernel/hostname}"

system_info_hostname() {
    local value=""
    [[ -r "$SYSTEM_INFO_HOSTNAME_FILE" ]] && value=$(<"$SYSTEM_INFO_HOSTNAME_FILE")
    [[ -z "$value" ]] && value=$(hostname 2>/dev/null || true)
    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    printf '%s\n' "${value:-unknown}"
}

system_info_os_name() {
    local value=""
    if [[ -r "$SYSTEM_INFO_OS_RELEASE" ]]; then
        value=$(sed -n 's/^PRETTY_NAME=//p' "$SYSTEM_INFO_OS_RELEASE" | head -n 1)
        value="${value#\"}"
        value="${value%\"}"
    fi
    [[ -z "$value" ]] && value=$(uname -o 2>/dev/null || uname -s 2>/dev/null || true)
    printf '%s\n' "${value:-Linux}"
}

system_info_kernel() {
    uname -r 2>/dev/null || printf '%s\n' "unknown"
}

system_info_uptime_seconds() {
    local value=0
    if [[ -r "${SYSTEM_INFO_PROC_ROOT}/uptime" ]]; then
        value=$(awk '{printf "%d", $1}' "${SYSTEM_INFO_PROC_ROOT}/uptime" 2>/dev/null || echo 0)
    fi
    [[ "$value" =~ ^[0-9]+$ ]] || value=0
    printf '%s\n' "$value"
}

system_info_cpu_model() {
    local value=""
    if [[ -r "${SYSTEM_INFO_PROC_ROOT}/cpuinfo" ]]; then
        value=$(awk -F: '
            /^[[:space:]]*model name[[:space:]]*:/ || /^[[:space:]]*Hardware[[:space:]]*:/ || /^[[:space:]]*Processor[[:space:]]*:/ {
                v=$2
                sub(/^[[:space:]]+/, "", v)
                sub(/[[:space:]]+$/, "", v)
                if (length(v)) { print v; exit }
            }
        ' "${SYSTEM_INFO_PROC_ROOT}/cpuinfo" 2>/dev/null)
    fi
    [[ -z "$value" ]] && value=$(uname -m 2>/dev/null || true)
    printf '%s\n' "${value:-unknown}"
}

system_info_cpu_threads() {
    local value=0
    if [[ -r "${SYSTEM_INFO_PROC_ROOT}/cpuinfo" ]]; then
        value=$(grep -c '^[[:space:]]*processor[[:space:]]*:' "${SYSTEM_INFO_PROC_ROOT}/cpuinfo" 2>/dev/null || true)
    fi
    if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value <= 0 )); then
        value=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)
    fi
    [[ "$value" =~ ^[0-9]+$ ]] || value=0
    printf '%s\n' "$value"
}

system_info_load_averages() {
    if [[ -r "${SYSTEM_INFO_PROC_ROOT}/loadavg" ]]; then
        awk '{print $1 "|" $2 "|" $3}' "${SYSTEM_INFO_PROC_ROOT}/loadavg" 2>/dev/null || printf '0|0|0\n'
    else
        printf '0|0|0\n'
    fi
}

system_info_memory_metrics() {
    if [[ ! -r "${SYSTEM_INFO_PROC_ROOT}/meminfo" ]]; then
        printf '0|0|0\n'
        return
    fi
    awk '
        $1 == "MemTotal:" { total=$2 }
        $1 == "MemAvailable:" { available=$2 }
        $1 == "MemFree:" { free=$2 }
        $1 == "Buffers:" { buffers=$2 }
        $1 == "Cached:" { cached=$2 }
        END {
            if (!available) available=free+buffers+cached
            used=total-available
            if (used < 0) used=0
            percent=total > 0 ? int((used*100 + total/2)/total) : 0
            printf "%d|%d|%d\n", int(total/1024), int(used/1024), percent
        }
    ' "${SYSTEM_INFO_PROC_ROOT}/meminfo" 2>/dev/null || printf '0|0|0\n'
}

system_info_format_temperature() {
    local raw="$1"
    awk -v raw="$raw" 'BEGIN {
        if (raw > 1000) value=raw/1000; else value=raw
        if (value < 0 || value > 130) exit 1
        printf "%.1f\n", value
    }'
}

system_info_cpu_temperature() {
    local input label source_name raw value
    for input in "${SYSTEM_INFO_SYS_ROOT}"/class/hwmon/hwmon*/temp*_input; do
        [[ -r "$input" ]] || continue
        raw=$(<"$input")
        [[ "$raw" =~ ^[0-9]+$ ]] || continue
        value=$(system_info_format_temperature "$raw" 2>/dev/null || true)
        [[ -n "$value" ]] || continue
        label=""
        [[ -r "${input%_input}_label" ]] && label=$(<"${input%_input}_label")
        source_name=""
        [[ -r "$(dirname "$input")/name" ]] && source_name=$(<"$(dirname "$input")/name")
        case "${source_name,,}:${label,,}" in
            *coretemp*|*k10temp*|*zenpower*|*package*|*tctl*|*cpu*|*core\ 0*) printf '%s\n' "$value"; return ;;
        esac
    done
    for input in "${SYSTEM_INFO_SYS_ROOT}"/class/thermal/thermal_zone*/temp; do
        [[ -r "$input" ]] || continue
        raw=$(<"$input")
        [[ "$raw" =~ ^[0-9]+$ ]] || continue
        value=$(system_info_format_temperature "$raw" 2>/dev/null || true)
        [[ -n "$value" ]] || continue
        label=""
        [[ -r "${input%/temp}/type" ]] && label=$(<"${input%/temp}/type")
        case "${label,,}" in
            *x86_pkg_temp*|*package*|*cpu*) printf '%s\n' "$value"; return ;;
        esac
    done
    printf '\n'
}
