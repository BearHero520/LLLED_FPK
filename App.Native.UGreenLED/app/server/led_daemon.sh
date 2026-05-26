#!/bin/bash
# LED 守护进程：全局模式 off / on / smart + 动态盘位映射 + 电源/网络灯

APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-${APP_ROOT:-/var/apps/${APP_NAME}}}"
VAR_DIR="${TRIM_PKGVAR:-${VAR_DIR:-${APP_ROOT}/var}}"
LOG_DIR="${LOG_DIR:-${VAR_DIR}/log}"
PID_FILE="${PID_FILE:-${VAR_DIR}/led_daemon.pid}"

SERVER_DIR="${SERVER_DIR:-}"
if [[ -z "$SERVER_DIR" ]]; then
    for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
        [[ -f "${d}/led_daemon.sh" ]] && SERVER_DIR="$d" && break
    done
fi
SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"
LIB_DIR="${SERVER_DIR}/lib"
SETTINGS_FILE="${VAR_DIR}/settings.conf"
UGREEN_CLI=""
for c in "${SERVER_DIR}/bin/ugreen_leds_cli" "${APP_ROOT}/target/server/bin/ugreen_leds_cli" /usr/bin/ugreen_leds_cli; do
    [[ -x "$c" ]] && UGREEN_CLI="$c" && break
done
export TARGET="${APP_ROOT}"

export UGREEN_CLI LED_API_CACHE_DIR="${VAR_DIR}/led_cache"
export DISK_IO_CACHE_DIR="${VAR_DIR}/disk_io"
SETTINGS_FILE="$SETTINGS_FILE"

source "${LIB_DIR}/led_api.sh"
source "${LIB_DIR}/settings.sh"
source "${LIB_DIR}/disk_map.sh"
source "${LIB_DIR}/disk_state.sh"
source "${LIB_DIR}/net_state.sh"
source "${LIB_DIR}/led_apply.sh"

mkdir -p "$LOG_DIR" "$VAR_DIR/led_cache" "$DISK_IO_CACHE_DIR"
settings_init "$SETTINGS_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_DIR}/daemon.log"
}

declare -A DISK_STATE_CACHE
declare -A NET_STATE_CACHE
LAST_DEVICE_HASH=""
DAEMON_RUN=true
MAPPING_READY=false

ensure_mapping() {
    disk_refresh_mapping "$SETTINGS_FILE"
    MAPPING_READY=true
    log "动态映射: ${#DISK_LED_MAP[@]} 项 -> $(printf '%s ' "${DISK_LED_MAP[@]}")"
}

check_hotplug() {
    local hash
    hash=$(disk_snapshot_devices | sort | md5sum 2>/dev/null | awk '{print $1}')
    [[ -z "$hash" ]] && return
    if [[ -n "$LAST_DEVICE_HASH" && "$hash" != "$LAST_DEVICE_HASH" ]]; then
        log "热插拔: 重新生成映射"
        DISK_STATE_CACHE=()
        led_clear_cache
        ensure_mapping
    fi
    LAST_DEVICE_HASH="$hash"
}

tick_mode_off() {
    led_all_off_full
}

tick_mode_on() {
    led_all_on_full "$SETTINGS_FILE"
}

tick_mode_smart() {
    local dev led state cached idle_sec
    local manage_power manage_netdev

    idle_sec=$(settings_get "$SETTINGS_FILE" daemon io_idle_seconds "8")
    manage_power=$(settings_get "$SETTINGS_FILE" behavior manage_power "true")
    manage_netdev=$(settings_get "$SETTINGS_FILE" behavior manage_netdev "true")

    $MAPPING_READY || ensure_mapping
    check_hotplug

    for dev in "${!DISK_LED_MAP[@]}"; do
        led="${DISK_LED_MAP[$dev]}"
        [[ -n "$led" ]] || continue
        state=$(disk_detect_smart_state "$dev" "$idle_sec")
        cached="${DISK_STATE_CACHE[$dev]:-}"
        if [[ "$state" != "$cached" ]]; then
            DISK_STATE_CACHE["$dev"]="$state"
            log "盘 $dev -> $led : $state"
            apply_disk_state_led "$led" "$state" "$SETTINGS_FILE" || log "WARN $led"
        fi
    done

    for slot in $(disk_unmapped_slots 2>/dev/null); do
        led_set_off "$slot"
    done

    if [[ "$manage_netdev" == "true" ]]; then
        local ns
        ns=$(net_detect_state)
        if [[ "$ns" != "${NET_STATE_CACHE[main]:-}" ]]; then
            NET_STATE_CACHE[main]="$ns"
            log "网络: $ns"
            apply_netdev_state "$ns" "$SETTINGS_FILE"
        fi
    fi

    if [[ "$manage_power" == "true" ]]; then
        apply_power_smart "$SETTINGS_FILE"
    fi
}

daemon_loop() {
    local interval mode
    interval=$(settings_get "$SETTINGS_FILE" daemon check_interval "5")
    log "启动 mode=$(settings_get "$SETTINGS_FILE" mode global smart) cli=$UGREEN_CLI"

    ensure_mapping

    while $DAEMON_RUN; do
        if [[ "$(settings_get "$SETTINGS_FILE" daemon enabled "true")" != "true" ]]; then
            sleep "$interval"
            continue
        fi
        if ! ensure_cli; then
            log "ERROR CLI 不可用"
            sleep "$interval"
            continue
        fi

        mode=$(settings_get "$SETTINGS_FILE" mode global "smart")
        case "$mode" in
            off)  tick_mode_off ;;
            on)   tick_mode_on ;;
            smart|*) tick_mode_smart ;;
        esac
        sleep "$interval"
    done
}

stop_daemon() {
    DAEMON_RUN=false
    [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
}

case "${1:-}" in
    start|_daemon)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            exit 0
        fi
        daemon_loop &
        echo $! > "$PID_FILE"
        ;;
    stop) stop_daemon ;;
    status)
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && exit 0
        exit 3
        ;;
    once)
        ensure_mapping
        mode=$(settings_get "$SETTINGS_FILE" mode global "smart")
        case "$mode" in
            off) tick_mode_off ;;
            on) tick_mode_on ;;
            *) tick_mode_smart ;;
        esac
        ;;
    remap)
        ensure_mapping
        ;;
    *)
        echo "用法: $0 {start|stop|status|once|remap}"
        exit 1
        ;;
esac
