#!/bin/bash
# LED 控制后端：默认使用打包 CLI；检测到可用 led-ugreen sysfs 时可切换。

UGREEN_CLI="${UGREEN_CLI:-}"
LED_SYSFS_ROOT="${LED_SYSFS_ROOT:-/sys/class/leds}"
LED_API_CACHE_DIR="${LED_API_CACHE_DIR:-/tmp/ugreen-led-api}"
LED_BACKEND_ACTIVE="${LED_BACKEND_ACTIVE:-}"
LED_POWER26_BUS="${LED_POWER26_BUS:-}"
LED_POWER26_DEFAULT_BUS="${LED_POWER26_DEFAULT_BUS:-${UGREEN_POWER26_BUS:-0}}"

mkdir -p "$LED_API_CACHE_DIR" 2>/dev/null

_led_log() {
    [[ "${LED_DEBUG:-false}" == "true" ]] && echo "[led_api] $*" >&2
}

ensure_i2c() {
    if ! lsmod 2>/dev/null | grep -q '^i2c_dev[[:space:]]'; then
        modprobe i2c-dev 2>/dev/null || true
    fi
    if declare -F hardware_write_protocol >/dev/null && [[ "$(hardware_write_protocol)" == "smbus-block" ]]; then
        modprobe i2c-designware-core 2>/dev/null || true
        modprobe i2c-designware-platform 2>/dev/null || true
    fi
}

led_power26_profile() {
    declare -F hardware_power26_controller >/dev/null && hardware_power26_controller
}

led_power26_ensure_bus() {
    [[ "$LED_POWER26_BUS" =~ ^[0-9]+$ ]] && return 0
    # DXP480T / Plus 已验证为固定 i2c-0、地址 0x26；无需额外扫描或读取签名。
    [[ "$LED_POWER26_DEFAULT_BUS" =~ ^[0-9]+$ ]] || return 1
    LED_POWER26_BUS="$LED_POWER26_DEFAULT_BUS"
}

led_power26_available() {
    ensure_i2c
    command -v i2cset >/dev/null 2>&1 && led_power26_ensure_bus
}

led_power26_write() {
    local reg="$1" value="$2"
    led_power26_ensure_bus || return 1
    timeout 3 i2cset -y "$LED_POWER26_BUS" 0x26 "$reg" "$value" b >/dev/null 2>&1 || return 1
    sleep 0.03
}

led_power26_color_mode() {
    local r="$1" g="$2" b="$3"
    if ((r > g + 20 && r > b + 20)); then echo 1; else echo 2; fi
}

led_power26_set_color() {
    local r="$1" g="$2" b="$3" effect="${4:-steady}" mode
    mode=$(led_power26_color_mode "$r" "$g" "$b")
    led_power26_write 0xa0 1 || return 1
    led_power26_write 0xa0 2 || return 1
    led_power26_write 0x51 0 || return 1
    led_power26_write 0x50 0 || return 1
    led_power26_write 0xb1 "$mode" || return 1
    case "$effect" in
        fast) led_power26_write 0x50 1 ;;
        slow) led_power26_write 0x51 1 ;;
        breath) led_power26_write 0x50 2 ;;
        *) led_power26_write 0x50 0 ;;
    esac
}

led_power26_set_off() {
    led_power26_write 0x50 0 || return 1
    led_power26_write 0x51 0 || return 1
    led_power26_write 0xa0 1 || return 1
    led_power26_write 0xa0 2
}

led_set_power26_effect() {
    local color="${1:-white}" effect="${2:-steady}" backend key r g b
    case "$color" in
        red) r=255; g=0; b=0 ;;
        white) r=255; g=255; b=255 ;;
        *) return 2 ;;
    esac
    case "$effect" in
        steady|fast|slow|breath|off) ;;
        *) return 2 ;;
    esac

    led_backend_select >/dev/null || return 1
    backend="$LED_BACKEND_ACTIVE"
    [[ "$backend" == "power-0x26" ]] || return 3
    key="power26,${color},${effect}"
    [[ "$(led_read_cached_state power)" == "$key" ]] && return 0

    if [[ "$effect" == "off" ]]; then
        led_power26_set_off || return 1
    else
        led_power26_set_color "$r" "$g" "$b" "$effect" || return 1
    fi
    led_write_cached_state power "$key"
}

led_cli_available() {
    [[ -n "$UGREEN_CLI" && -x "$UGREEN_CLI" ]]
}

ensure_cli() {
    if ! led_cli_available; then
        echo "ugreen_leds_cli 未找到或未可执行: ${UGREEN_CLI:-<empty>}" >&2
        return 1
    fi
    ensure_i2c
}

led_sysfs_available() {
    if declare -F driver_sysfs_ready >/dev/null; then
        driver_sysfs_ready
    else
        [[ -d "$LED_SYSFS_ROOT/power" && -w "$LED_SYSFS_ROOT/power/brightness" && -w "$LED_SYSFS_ROOT/power/color" ]]
    fi
}

led_driver_loaded() {
    if declare -F driver_module_loaded >/dev/null && driver_module_loaded; then
        return 0
    fi
    if declare -F driver_vendor_conflict >/dev/null && driver_vendor_conflict; then
        return 0
    fi
    lsmod 2>/dev/null | grep -Eq '^(led_ugreen|leds_mcu[^[:space:]]*|ugreen_leds|leds_ugreen)[[:space:]]'
}

led_backend_configured() {
    local configured="auto"
    if declare -F settings_get >/dev/null && [[ -n "${SETTINGS_FILE:-}" ]]; then
        configured=$(settings_get "$SETTINGS_FILE" hardware backend "auto")
    fi
    case "$configured" in auto|cli|sysfs) echo "$configured" ;; *) echo "auto" ;; esac
}

led_backend_reset() {
    LED_BACKEND_ACTIVE=""
    LED_POWER26_BUS=""
}

led_backend_select() {
    local configured
    [[ -n "$LED_BACKEND_ACTIVE" ]] && { echo "$LED_BACKEND_ACTIVE"; return; }
    configured=$(led_backend_configured)
    if led_power26_profile; then
        [[ "$configured" != "sysfs" ]] || return 1
        led_driver_loaded && return 2
        led_power26_available || return 1
        LED_BACKEND_ACTIVE="power-0x26"
        echo "$LED_BACKEND_ACTIVE"
        return 0
    fi
    case "$configured" in
        sysfs)
            led_sysfs_available || return 1
            LED_BACKEND_ACTIVE="sysfs"
            ;;
        cli)
            # 已绑定内核驱动时禁止 CLI 抢占同一个 MCU。
            led_driver_loaded && return 2
            ensure_cli || return 1
            LED_BACKEND_ACTIVE="cli"
            ;;
        *)
            if led_sysfs_available; then
                LED_BACKEND_ACTIVE="sysfs"
            elif led_driver_loaded; then
                return 2
            else
                ensure_cli || return 1
                LED_BACKEND_ACTIVE="cli"
            fi
            ;;
    esac
    echo "$LED_BACKEND_ACTIVE"
}

ensure_led_backend() {
    led_backend_select >/dev/null
}

led_backend_name() {
    if led_backend_select >/dev/null 2>&1; then
        echo "$LED_BACKEND_ACTIVE"
    else
        echo "unavailable"
    fi
}

led_cli_name() {
    if declare -F hardware_cli_led_name >/dev/null; then
        hardware_cli_led_name "$1"
    else
        echo "$1"
    fi
}

led_sysfs_path() {
    printf '%s/%s\n' "$LED_SYSFS_ROOT" "$1"
}

led_cli_run() {
    local logical="$1" raw protocol
    shift
    ensure_cli || return 1
    raw=$(led_cli_name "$logical")
    protocol="legacy"
    declare -F hardware_write_protocol >/dev/null && protocol=$(hardware_write_protocol)
    UGREEN_LEDS_WRITE_PROTOCOL="$protocol" timeout 5 "$UGREEN_CLI" "$raw" "$@"
}

led_backend_status_raw() {
    local led="$1" backend path
    led_backend_select >/dev/null || return 1
    backend="$LED_BACKEND_ACTIVE"
    if [[ "$backend" == "sysfs" ]]; then
        path=$(led_sysfs_path "$led")
        [[ -r "$path/status" ]] || return 1
        cat "$path/status"
    elif [[ "$backend" == "power-0x26" ]]; then
        local state
        [[ "$led" == "power" ]] || return 1
        state=$(led_read_cached_state "$led")
        case "$state" in
            off|power26,*,off) echo "off 0 0 0 0 0 0" ;;
            blink,*|power26,*,fast|power26,*,slow) echo "blink 0 0 0 0 0 0" ;;
            power26,*,breath) echo "breath 0 0 0 0 0 0" ;;
            *) echo "on 0 0 0 0 0 0" ;;
        esac
    else
        led_cli_run "$led" -status 2>/dev/null
    fi
}

led_op_mode() {
    local raw lower
    raw=$(led_backend_status_raw "$1") || return 1
    lower="${raw,,}"
    if [[ "$lower" =~ op_mode:([a-z]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$lower" =~ op_mode:([0-3]) ]]; then
        case "${BASH_REMATCH[1]}" in 0) echo off ;; 1) echo on ;; 2) echo blink ;; 3) echo breath ;; esac
    elif [[ "$lower" =~ status[[:space:]]*=[[:space:]]*(off|on|blink|breath) ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$lower" =~ ^(off|on|blink|breath)[[:space:]] ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "unknown"
    fi
}

led_is_off() {
    [[ "$(led_op_mode "$1")" == "off" ]]
}

_cache_file() {
    echo "$LED_API_CACHE_DIR/$(echo "$1" | tr '/' '_').state"
}

led_read_cached_state() {
    local f
    f=$(_cache_file "$1")
    [[ -f "$f" ]] && cat "$f"
}

led_write_cached_state() {
    echo "$2" > "$(_cache_file "$1")"
}

led_ensure_on() {
    local led="$1" backend path
    led_is_off "$led" || return 0
    led_backend_select >/dev/null || return 1
    backend="$LED_BACKEND_ACTIVE"
    if [[ "$backend" == "sysfs" ]]; then
        path=$(led_sysfs_path "$led")
        printf '1\n' > "$path/brightness"
    else
        led_cli_run "$led" -on >/dev/null 2>&1
    fi
    sleep 0.08
}

led_set_color() {
    local led="$1" r="$2" g="$3" b="$4" brightness="${5:-64}" backend path key
    ensure_led_backend || return 1
    key="${r},${g},${b},${brightness}"
    [[ "$(led_read_cached_state "$led")" == "$key" ]] && return 0
    backend="$LED_BACKEND_ACTIVE"

    if [[ "$backend" == "sysfs" ]]; then
        path=$(led_sysfs_path "$led")
        [[ -w "$path/color" && -w "$path/brightness" ]] || return 1
        printf '%s %s %s\n' "$r" "$g" "$b" > "$path/color" || return 1
        printf '%s\n' "$brightness" > "$path/brightness" || return 1
    elif [[ "$backend" == "power-0x26" ]]; then
        [[ "$led" == "power" ]] || return 1
        led_power26_set_color "$r" "$g" "$b" steady || return 1
    else
        led_ensure_on "$led" || return 1
        led_cli_run "$led" -color "$r" "$g" "$b" -brightness "$brightness" -on >/dev/null 2>&1 || {
            led_cli_run "$led" -on >/dev/null 2>&1 || true
            sleep 0.1
            led_cli_run "$led" -color "$r" "$g" "$b" -brightness "$brightness" -on >/dev/null 2>&1 || return 1
        }
    fi
    led_write_cached_state "$led" "$key"
}

led_set_off() {
    local led="$1" backend path
    ensure_led_backend || return 1
    [[ "$(led_read_cached_state "$led")" == "off" ]] && return 0
    backend="$LED_BACKEND_ACTIVE"
    if [[ "$backend" == "sysfs" ]]; then
        path=$(led_sysfs_path "$led")
        [[ -w "$path/brightness" ]] || return 1
        printf '0\n' > "$path/brightness" || return 1
    elif [[ "$backend" == "power-0x26" ]]; then
        [[ "$led" == "power" ]] || return 1
        led_power26_set_off || return 1
    else
        led_cli_run "$led" -off >/dev/null 2>&1 || return 1
    fi
    led_write_cached_state "$led" "off"
}

led_set_blink() {
    local led="$1" r="$2" g="$3" b="$4" period_ms="$5" on_ms="$6" brightness="${7:-64}"
    local off_ms backend path key
    ensure_led_backend || return 1
    ((period_ms < 2)) && period_ms=2
    ((on_ms < 1)) && on_ms=1
    ((on_ms >= period_ms)) && on_ms=$((period_ms / 2))
    off_ms=$((period_ms - on_ms))
    ((off_ms < 1)) && off_ms=1
    key="blink,${r},${g},${b},${on_ms},${off_ms},${brightness}"
    [[ "$(led_read_cached_state "$led")" == "$key" ]] && return 0
    backend="$LED_BACKEND_ACTIVE"

    if [[ "$backend" == "sysfs" ]]; then
        path=$(led_sysfs_path "$led")
        [[ -w "$path/color" && -w "$path/brightness" && -w "$path/blink_type" ]] || return 1
        printf '%s %s %s\n' "$r" "$g" "$b" > "$path/color" || return 1
        printf '%s\n' "$brightness" > "$path/brightness" || return 1
        printf 'blink %s %s\n' "$on_ms" "$off_ms" > "$path/blink_type" || return 1
    elif [[ "$backend" == "power-0x26" ]]; then
        [[ "$led" == "power" ]] || return 1
        if ((period_ms >= 1200)); then
            led_power26_set_color "$r" "$g" "$b" slow || return 1
        else
            led_power26_set_color "$r" "$g" "$b" fast || return 1
        fi
    else
        led_ensure_on "$led" || return 1
        led_cli_run "$led" -color "$r" "$g" "$b" -blink "$on_ms" "$off_ms" -brightness "$brightness" >/dev/null 2>&1 || return 1
    fi
    led_write_cached_state "$led" "$key"
}

led_list_network_slots() {
    if declare -F hardware_network_leds >/dev/null; then
        hardware_network_leds
    else
        echo netdev
    fi
}

led_list_disk_slots() {
    local count i backend line raw protocol="legacy"
    declare -F hardware_disk_count >/dev/null && count=$(hardware_disk_count)
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        for ((i = 1; i <= count; i++)); do echo "disk${i}"; done
        return
    fi
    led_backend_select >/dev/null || return 1
    backend="$LED_BACKEND_ACTIVE"
    if [[ "$backend" == "sysfs" ]]; then
        for raw in "$LED_SYSFS_ROOT"/disk*; do
            [[ -d "$raw" && "${raw##*/}" =~ ^disk[1-9][0-9]*$ ]] && echo "${raw##*/}"
        done | sort -V -u
    else
        declare -F hardware_write_protocol >/dev/null && protocol=$(hardware_write_protocol)
        raw=$(UGREEN_LEDS_WRITE_PROTOCOL="$protocol" "$UGREEN_CLI" all -status 2>/dev/null) || return 1
        while IFS= read -r line; do
            [[ "$line" =~ ^(disk[0-9]+): ]] && echo "${BASH_REMATCH[1]}"
        done <<< "$raw" | sort -V -u
    fi
}

led_all_status() {
    local led raw backend
    led_backend_select >/dev/null || return 1
    backend="$LED_BACKEND_ACTIVE"
    echo "backend: $backend"
    for led in power $(led_list_network_slots) $(led_list_disk_slots); do
        raw=$(led_backend_status_raw "$led" 2>/dev/null || true)
        [[ -n "$raw" ]] && printf '%s: %s\n' "$led" "$(echo "$raw" | head -n 1)"
    done
}

led_clear_cache() {
    rm -f "$LED_API_CACHE_DIR"/* 2>/dev/null
    led_backend_reset
}
