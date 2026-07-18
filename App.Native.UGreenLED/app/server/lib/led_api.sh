#!/bin/bash
# LED adapter.  Hardware access is intentionally delegated to the bundled
# ugreen_leds_cli; this file must not write sysfs, I2C, Super-I/O, or MCU nodes.

UGREEN_CLI="${UGREEN_CLI:-}"
LED_API_CACHE_DIR="${LED_API_CACHE_DIR:-/tmp/ugreen-led-api}"
LED_BACKEND_ACTIVE="${LED_BACKEND_ACTIVE:-}"
LED_LAST_ERROR="${LED_LAST_ERROR:-}"

mkdir -p "$LED_API_CACHE_DIR" 2>/dev/null || true

_led_log() {
    if declare -F ugreen_log_debug >/dev/null; then
        ugreen_log_debug "led.detail" "$*"
    elif [[ "${LED_DEBUG:-false}" == "true" ]]; then
        printf '[led_api] %s\n' "$*" >&2
    fi
}

_led_log_failure() {
    local event="$1" message="$2"
    shift 2
    if declare -F ugreen_log_rate_limited >/dev/null; then
        ugreen_log_rate_limited "${event}:${1:-general}" 30 ERROR "$event" "$message" "$@"
    elif declare -F ugreen_log_error >/dev/null; then
        ugreen_log_error "$event" "$message" "$@"
    fi
}

led_set_error() {
    LED_LAST_ERROR="$*"
    _led_log "$LED_LAST_ERROR"
}

led_cli_available() {
    [[ -n "$UGREEN_CLI" && -x "$UGREEN_CLI" ]]
}

ensure_cli() {
    if ! led_cli_available; then
        led_set_error "ugreen_leds_cli is missing or not executable: ${UGREEN_CLI:-<empty>}"
        _led_log_failure "led.cli_unavailable" "bundled LED CLI is unavailable" "cli=${UGREEN_CLI:-missing}"
        return 1
    fi
}

led_cli_name() {
    if declare -F hardware_cli_led_name >/dev/null; then
        hardware_cli_led_name "$1"
    else
        printf '%s\n' "$1"
    fi
}

led_cli_run() {
    local logical="$1" raw protocol output rc action
    shift
    ensure_cli || return 1
    raw=$(led_cli_name "$logical")
    protocol="legacy"
    declare -F hardware_write_protocol >/dev/null && protocol=$(hardware_write_protocol)
    action="$*"
    if command -v timeout >/dev/null 2>&1; then
        if output=$(UGREEN_LEDS_WRITE_PROTOCOL="$protocol" timeout 5 "$UGREEN_CLI" "$raw" "$@" 2>&1); then rc=0; else rc=$?; fi
    else
        if output=$(UGREEN_LEDS_WRITE_PROTOCOL="$protocol" "$UGREEN_CLI" "$raw" "$@" 2>&1); then rc=0; else rc=$?; fi
    fi
    if [[ "$rc" -ne 0 ]]; then
        output="${output//$'\n'/ }"
        led_set_error "LED CLI command failed: $logical $action (rc=$rc${output:+, $output})"
        _led_log_failure "led.cli_command_failed" "LED CLI command failed" \
            "logical_led=$logical" "raw_led=$raw" "protocol=$protocol" "action=$action" \
            "exit_code=$rc" "output=$output"
        return "$rc"
    fi
    LED_LAST_ERROR=""
    printf '%s' "$output"
}

led_cli_power26_probe() {
    local output rc
    ensure_cli || return 1
    if command -v timeout >/dev/null 2>&1; then
        if output=$(timeout 5 "$UGREEN_CLI" --dxp480t-power-probe 2>&1); then rc=0; else rc=$?; fi
    else
        if output=$("$UGREEN_CLI" --dxp480t-power-probe 2>&1); then rc=0; else rc=$?; fi
    fi
    if [[ "$rc" -ne 0 ]]; then
        output="${output//$'\n'/ }"
        led_set_error "DXP480T power controller probe failed (rc=$rc${output:+, $output})"
        _led_log_failure "led.power26_probe_failed" "DXP480T power controller is unavailable" \
            "exit_code=$rc" "output=$output"
        return "$rc"
    fi
    LED_LAST_ERROR=""
    printf '%s' "$output"
}

led_cli_power26_apply() {
    local color="$1" effect="$2" output rc
    ensure_cli || return 1
    if command -v timeout >/dev/null 2>&1; then
        if output=$(timeout 5 "$UGREEN_CLI" --dxp480t-power "$color" "$effect" 2>&1); then rc=0; else rc=$?; fi
    else
        if output=$("$UGREEN_CLI" --dxp480t-power "$color" "$effect" 2>&1); then rc=0; else rc=$?; fi
    fi
    if [[ "$rc" -ne 0 ]]; then
        output="${output//$'\n'/ }"
        led_set_error "DXP480T power LED command failed: $color $effect (rc=$rc${output:+, $output})"
        _led_log_failure "led.power26_command_failed" "DXP480T power LED CLI command failed" \
            "color=$color" "effect=$effect" "exit_code=$rc" "output=$output"
        return "$rc"
    fi
    LED_LAST_ERROR=""
    printf '%s' "$output"
}

led_power26_profile() {
    declare -F hardware_power26_controller >/dev/null && hardware_power26_controller
}

led_backend_configured() {
    local configured="auto"
    if declare -F settings_get >/dev/null && [[ -n "${SETTINGS_FILE:-}" ]]; then
        configured=$(settings_get "$SETTINGS_FILE" hardware backend "auto")
    fi
    case "$configured" in auto|cli) printf '%s\n' "$configured" ;; *) printf 'cli\n' ;; esac
}

led_backend_reset() { LED_BACKEND_ACTIVE=""; }

led_backend_select() {
    [[ -n "$LED_BACKEND_ACTIVE" ]] && { printf '%s\n' "$LED_BACKEND_ACTIVE"; return 0; }
    ensure_cli || return 1
    if led_power26_profile; then
        led_cli_power26_probe >/dev/null || return 1
    fi
    LED_BACKEND_ACTIVE="cli"
    printf '%s\n' "$LED_BACKEND_ACTIVE"
}

ensure_led_backend() { led_backend_select >/dev/null; }

led_backend_name() {
    if led_backend_select >/dev/null 2>&1; then printf '%s\n' "$LED_BACKEND_ACTIVE"; else printf 'unavailable\n'; fi
}

led_backend_status_raw() {
    local state
    led_backend_select >/dev/null || return 1
    if led_power26_profile && [[ "$1" == "power" ]]; then
        state=$(led_read_cached_state power)
        case "$state" in
            off|power26,*,off) echo "status = off" ;;
            power26,*,fast|power26,*,slow) echo "status = blink" ;;
            power26,*,breath) echo "status = breath" ;;
            *) echo "status = on" ;;
        esac
        return 0
    fi
    led_cli_run "$1" -status 2>/dev/null
}

led_op_mode() {
    local raw lower
    raw=$(led_backend_status_raw "$1") || return 1
    lower="${raw,,}"
    if [[ "$lower" =~ op_mode:([a-z]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ "$lower" =~ op_mode:([0-3]) ]]; then
        case "${BASH_REMATCH[1]}" in 0) echo off ;; 1) echo on ;; 2) echo blink ;; 3) echo breath ;; esac
    elif [[ "$lower" =~ status[[:space:]]*=[[:space:]]*(off|on|blink|breath) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ "$lower" =~ ^(off|on|blink|breath)[[:space:]] ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        echo unknown
    fi
}

led_is_off() { [[ "$(led_op_mode "$1")" == "off" ]]; }

_cache_file() { printf '%s/%s.state\n' "$LED_API_CACHE_DIR" "$(printf '%s' "$1" | tr '/' '_')"; }

led_read_cached_state() {
    local file; file=$(_cache_file "$1"); [[ -f "$file" ]] && cat "$file"
}

led_write_cached_state() {
    local file tmp
    file=$(_cache_file "$1"); tmp="${file}.tmp.${BASHPID:-$$}"
    if ! printf '%s\n' "$2" > "$tmp" || ! mv "$tmp" "$file"; then
        rm -f "$tmp" 2>/dev/null || true
        led_set_error "unable to write LED state cache: $file"
        return 1
    fi
}

led_clear_cache() {
    rm -f "$LED_API_CACHE_DIR"/* 2>/dev/null || true
    led_backend_reset
}

led_ensure_on() {
    led_is_off "$1" || return 0
    led_cli_run "$1" -on >/dev/null || return 1
    sleep 0.08
}

led_set_color() {
    local led="$1" r="$2" g="$3" b="$4" brightness="${5:-64}" key
    if led_power26_profile; then
        [[ "$led" == "power" ]] || { led_set_error "DXP480T only exposes the power LED"; return 2; }
        if (( r > g + 20 && r > b + 20 )); then
            led_set_power26_effect red steady
        else
            led_set_power26_effect white steady
        fi
        return
    fi
    ensure_led_backend || return 1
    key="${r},${g},${b},${brightness}"
    [[ "$(led_read_cached_state "$led")" == "$key" ]] && return 0
    led_ensure_on "$led" || true
    led_cli_run "$led" -color "$r" "$g" "$b" -brightness "$brightness" -on >/dev/null || return 1
    led_write_cached_state "$led" "$key"
}

led_set_off() {
    local led="$1"
    if led_power26_profile; then
        [[ "$led" == "power" ]] || { led_set_error "DXP480T only exposes the power LED"; return 2; }
        led_set_power26_effect white off
        return
    fi
    ensure_led_backend || return 1
    [[ "$(led_read_cached_state "$led")" == "off" ]] && return 0
    led_cli_run "$led" -off >/dev/null || return 1
    led_write_cached_state "$led" off
}

led_set_blink() {
    local led="$1" r="$2" g="$3" b="$4" period_ms="$5" on_ms="$6" brightness="${7:-64}"
    local off_ms key
    if led_power26_profile; then
        local color effect
        [[ "$led" == "power" ]] || { led_set_error "DXP480T only exposes the power LED"; return 2; }
        if (( r > g + 20 && r > b + 20 )); then color=red; else color=white; fi
        if (( period_ms >= 1200 )); then effect=slow; else effect=fast; fi
        led_set_power26_effect "$color" "$effect"
        return
    fi
    ensure_led_backend || return 1
    (( period_ms < 2 )) && period_ms=2
    (( on_ms < 1 )) && on_ms=1
    (( on_ms >= period_ms )) && on_ms=$((period_ms / 2))
    off_ms=$((period_ms - on_ms)); (( off_ms < 1 )) && off_ms=1
    key="blink,${r},${g},${b},${on_ms},${off_ms},${brightness}"
    [[ "$(led_read_cached_state "$led")" == "$key" ]] && return 0
    led_cli_run "$led" -color "$r" "$g" "$b" -blink "$on_ms" "$off_ms" -brightness "$brightness" >/dev/null || return 1
    led_write_cached_state "$led" "$key"
}

# The DXP480T page only invokes the dedicated bundled-CLI command.  No shell
# code in the application probes buses or accesses the LED controller directly.
led_set_power26_effect() {
    local color="${1:-white}" effect="${2:-steady}"
    local key
    led_power26_profile || { led_set_error "DXP480T power protocol is not active for this model"; return 2; }
    case "$color" in red|white) ;; *) return 2 ;; esac
    case "$effect" in off|steady|fast|slow|breath) ;; *) return 2 ;; esac
    ensure_led_backend || return 1
    key="power26,${color},${effect}"
    [[ "$(led_read_cached_state power)" == "$key" ]] && return 0
    led_cli_power26_apply "$color" "$effect" >/dev/null || return 1
    led_write_cached_state power "$key"
}

led_power26_available() { led_cli_power26_probe >/dev/null; }
led_power26_bus_candidates() { return 1; }
led_power26_address_candidates() { return 1; }
led_power26_detect() { return 1; }
led_power26_signature_matches() { return 1; }
led_power26_transaction_guard() { ensure_cli; }
led_power26_lock_acquire() { return 0; }
led_power26_lock_release() { return 0; }
led_power26_apply_transaction() { return 1; }
led_power26_set_color() { return 1; }
led_power26_set_off() { return 1; }
led_power26_write() { return 1; }
led_power26_write_u16() { return 1; }

led_sysfs_available() { return 1; }
led_driver_loaded() {
    if declare -F driver_module_loaded >/dev/null && driver_module_loaded; then return 0; fi
    if declare -F driver_vendor_conflict >/dev/null && driver_vendor_conflict; then return 0; fi
    lsmod 2>/dev/null | grep -Eq '^(led_ugreen|leds_mcu[^[:space:]]*|ugreen_leds|leds_ugreen)[[:space:]]'
}

led_list_network_slots() {
    if declare -F hardware_network_leds >/dev/null; then hardware_network_leds; else echo netdev; fi
}

led_list_disk_slots() {
    local count i line raw
    if declare -F hardware_disk_count >/dev/null; then
        count=$(hardware_disk_count)
        if [[ "$count" =~ ^[0-9]+$ ]]; then
            for ((i = 1; i <= count; i++)); do echo "disk${i}"; done
            return 0
        fi
    fi
    raw=$(led_cli_run all -status 2>/dev/null) || return 1
    while IFS= read -r line; do
        [[ "$line" =~ ^(disk[0-9]+): ]] && echo "${BASH_REMATCH[1]}"
    done <<< "$raw" | sort -V -u
}

led_all_status() {
    local led raw state
    led_backend_select >/dev/null || return 1
    echo "backend: cli"
    if led_power26_profile; then
        state=$(led_read_cached_state power)
        case "$state" in
            off|power26,*,off) echo "power: status = off" ;;
            power26,*,fast|power26,*,slow) echo "power: status = blink" ;;
            power26,*,breath) echo "power: status = breath" ;;
            *) echo "power: status = on" ;;
        esac
        return 0
    fi
    for led in power $(led_list_network_slots 2>/dev/null) $(led_list_disk_slots 2>/dev/null); do
        raw=$(led_backend_status_raw "$led" 2>/dev/null || true)
        [[ -n "$raw" ]] && printf '%s: %s\n' "$led" "$(echo "$raw" | head -n 1)"
    done
}
