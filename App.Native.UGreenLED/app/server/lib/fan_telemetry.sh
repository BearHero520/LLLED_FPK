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

fan_telemetry_latest_json() {
    local expected_model file
    expected_model=$(fan_telemetry_model "${1:-unknown}")
    file=$(fan_telemetry_history_path)
    [[ -f "$file" && ! -L "$file" ]] || return 0
    tail -n 256 "$file" 2>/dev/null | awk -F'|' -v expected_model="$expected_model" '
        function number(value, fallback) {
            return value ~ /^-?[0-9]+$/ ? value + 0 : fallback
        }
        NF == 8 && $1 ~ /^[0-9]+$/ && $2 == expected_model {
            at = $1 + 0
            cpu = number($3, -1)
            hdd = number($4, -1)
            ssd = number($5, -1)
            cpu_rpm = number($6, 0)
            sys_rpm = number($7, 0)
            sys2_rpm = number($8, 0)
            latest = sprintf("{\"at\":%.0f,\"cpu\":%d,\"cpuPeak\":%d,\"hdd\":%d,\"ssd\":%d,\"cpuRpm\":%d,\"sysRpm\":%d,\"sys2Rpm\":%d}", at, cpu, cpu, hdd, ssd, cpu_rpm, sys_rpm, sys2_rpm)
        }
        END {
            if (latest != "") printf "%s", latest
        }
    '
}

fan_telemetry_history_json() {
    local seconds="$(fan_telemetry_number "${1:-}" 60)" expected_model cutoff now file
    local bucket_seconds="$(fan_telemetry_number "${3:-}" 1)"
    expected_model=$(fan_telemetry_model "${2:-unknown}")
    [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=60
    (( seconds > 86400 )) && seconds=86400
    [[ "$bucket_seconds" =~ ^[0-9]+$ ]] || bucket_seconds=1
    (( bucket_seconds < 1 )) && bucket_seconds=1
    (( bucket_seconds > seconds )) && bucket_seconds=seconds
    now=$(date +%s 2>/dev/null || echo 0)
    cutoff=$(( now - seconds ))
    file=$(fan_telemetry_history_path)
    printf '['
    [[ -f "$file" && ! -L "$file" ]] || { printf ']'; return 0; }
    awk -F'|' -v expected_model="$expected_model" -v cutoff="$cutoff" -v future="$((now + 60))" -v bucket_seconds="$bucket_seconds" '
        function number(value, fallback) {
            return value ~ /^-?[0-9]+$/ ? value + 0 : fallback
        }
        function emit_pending() {
            if (pending == "") return
            if (!first) printf ","
            printf "%s", pending
            first = 0
        }
        BEGIN {
            first = 1
            pending = ""
            pending_slot = -1
        }
        NF == 8 && $1 ~ /^[0-9]+$/ && $2 == expected_model {
            at = $1 + 0
            if (at < cutoff || at > future) next
            slot = int(at / bucket_seconds)
            if (pending != "" && slot != pending_slot) emit_pending()
            pending_slot = slot
            pending = sprintf("{\"at\":%.0f,\"cpu\":%d,\"hdd\":%d,\"ssd\":%d,\"cpuRpm\":%d,\"sysRpm\":%d,\"sys2Rpm\":%d}", at, number($3, -1), number($4, -1), number($5, -1), number($6, 0), number($7, 0), number($8, 0))
        }
        END {
            emit_pending()
        }
    ' "$file"
    printf ']'
}
