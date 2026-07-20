#!/bin/bash
# Telemetry storage is application-side only. Hardware reads stay in bios_control.sh,
# which delegates fan and thermal access to the bundled upstream ugreenctl tool.

FAN_TELEMETRY_MAX_SAMPLES="${FAN_TELEMETRY_MAX_SAMPLES:-9000}"

fan_telemetry_history_path() {
    printf '%s\n' "${VAR_DIR:-/var/apps/App.Native.UGreenLED/var}/fan-telemetry.tsv"
}

fan_telemetry_number() {
    local value="${1:-}" fallback="${2:--1}"
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

fan_telemetry_model() {
    local model="${1:-unknown}"
    [[ "$model" =~ ^[A-Za-z0-9_-]{1,48}$ ]] || model="unknown"
    printf '%s' "$model"
}

_fan_telemetry_append_unlocked() {
    local file="$1" line="$2" temporary
    printf '%s\n' "$line" >> "$file" || return 1
    if (( $(wc -l < "$file" 2>/dev/null || echo 0) > FAN_TELEMETRY_MAX_SAMPLES )); then
        temporary="${file}.tmp.${BASHPID:-$$}"
        tail -n "$FAN_TELEMETRY_MAX_SAMPLES" "$file" > "$temporary" && mv "$temporary" "$file"
        rm -f "$temporary" 2>/dev/null || true
    fi
}

fan_telemetry_append() {
    local at="$(fan_telemetry_number "${1:-}" 0)" model cpu hdd ssd cpu_rpm sys_rpm sys2_rpm file line
    model=$(fan_telemetry_model "${2:-}")
    cpu=$(fan_telemetry_number "${3:-}"); hdd=$(fan_telemetry_number "${4:-}"); ssd=$(fan_telemetry_number "${5:-}")
    cpu_rpm=$(fan_telemetry_number "${6:-}" 0); sys_rpm=$(fan_telemetry_number "${7:-}" 0); sys2_rpm=$(fan_telemetry_number "${8:-}" 0)
    [[ "$at" =~ ^[0-9]+$ && "$at" -gt 0 ]] || return 1
    file=$(fan_telemetry_history_path)
    [[ ! -L "$file" ]] || return 1
    mkdir -p "$(dirname "$file")" 2>/dev/null || return 1
    line="${at}|${model}|${cpu}|${hdd}|${ssd}|${cpu_rpm}|${sys_rpm}|${sys2_rpm}"
    if command -v flock >/dev/null 2>&1; then
        ( flock -x 9; _fan_telemetry_append_unlocked "$file" "$line" ) 9>>"${file}.lock"
    else
        _fan_telemetry_append_unlocked "$file" "$line"
    fi
}

fan_telemetry_append_bios_status() {
    local now="$(fan_telemetry_number "${1:-}" 0)" cpu_rpm sys2_rpm
    [[ "${BIOS_SUPPORTED:-false}" == "true" && "$now" =~ ^[0-9]+$ && "$now" -gt 0 ]] || return 0
    cpu_rpm="${BIOS_CPU_RPM:-0}"
    sys2_rpm="${BIOS_SYS2_RPM:-0}"
    [[ "${BIOS_CPU_FAN_PRESENT:-true}" == "true" ]] || cpu_rpm=-1
    case "${BIOS_MODEL:-}" in dxp480t_plus|dxp6800pro) ;; *) sys2_rpm=-1 ;; esac
    fan_telemetry_append "$now" "$BIOS_MODEL" "$BIOS_CPU_CELSIUS" "$BIOS_HDD_CELSIUS" "$BIOS_SSD_CELSIUS" \
        "$cpu_rpm" "$BIOS_SYS_RPM" "$sys2_rpm"
}

fan_telemetry_capture() {
    local now
    bios_read_status >/dev/null 2>&1 || true
    [[ "${BIOS_SUPPORTED:-false}" == "true" ]] || return 0
    now=$(date +%s 2>/dev/null || echo 0)
    fan_telemetry_append_bios_status "$now"
}

fan_telemetry_current_json() {
    local at="$(fan_telemetry_number "${1:-}" 0)" cpu_rpm="${BIOS_CPU_RPM:-0}" sys2_rpm="${BIOS_SYS2_RPM:-0}"
    [[ "${BIOS_CPU_FAN_PRESENT:-true}" == "true" ]] || cpu_rpm=-1
    case "${BIOS_MODEL:-}" in dxp480t_plus|dxp6800pro) ;; *) sys2_rpm=-1 ;; esac
    printf '{"at":%s,"cpu":%s,"cpuPeak":%s,"hdd":%s,"ssd":%s,"cpuRpm":%s,"sysRpm":%s,"sys2Rpm":%s}' \
        "$at" "$(fan_telemetry_number "${BIOS_CPU_CELSIUS:-}")" "$(fan_telemetry_number "${BIOS_CPU_PEAK_CELSIUS:-}")" "$(fan_telemetry_number "${BIOS_HDD_CELSIUS:-}")" \
        "$(fan_telemetry_number "${BIOS_SSD_CELSIUS:-}")" "$(fan_telemetry_number "$cpu_rpm")" \
        "$(fan_telemetry_number "${BIOS_SYS_RPM:-}" 0)" "$(fan_telemetry_number "$sys2_rpm")"
}

fan_telemetry_history_json() {
    local seconds="$(fan_telemetry_number "${1:-}" 60)" expected_model cutoff now file first=true
    local at model cpu hdd ssd cpu_rpm sys_rpm sys2_rpm
    expected_model=$(fan_telemetry_model "${2:-unknown}")
    [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=60
    (( seconds > 86400 )) && seconds=86400
    now=$(date +%s 2>/dev/null || echo 0)
    cutoff=$(( now - seconds ))
    file=$(fan_telemetry_history_path)
    printf '['
    [[ -f "$file" && ! -L "$file" ]] || { printf ']'; return 0; }
    while IFS='|' read -r at model cpu hdd ssd cpu_rpm sys_rpm sys2_rpm extra; do
        [[ -z "$extra" && "$at" =~ ^[0-9]+$ && "$model" == "$expected_model" ]] || continue
        (( at >= cutoff && at <= now + 60 )) || continue
        cpu=$(fan_telemetry_number "$cpu"); hdd=$(fan_telemetry_number "$hdd"); ssd=$(fan_telemetry_number "$ssd")
        cpu_rpm=$(fan_telemetry_number "$cpu_rpm" 0); sys_rpm=$(fan_telemetry_number "$sys_rpm" 0); sys2_rpm=$(fan_telemetry_number "$sys2_rpm" 0)
        $first || printf ','
        printf '{"at":%s,"cpu":%s,"hdd":%s,"ssd":%s,"cpuRpm":%s,"sysRpm":%s,"sys2Rpm":%s}' \
            "$at" "$cpu" "$hdd" "$ssd" "$cpu_rpm" "$sys_rpm" "$sys2_rpm"
        first=false
    done < "$file"
    printf ']'
}
