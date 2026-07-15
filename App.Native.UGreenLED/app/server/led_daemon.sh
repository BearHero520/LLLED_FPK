#!/bin/bash
# LED 守护进程：全局模式 + 动态盘位映射 + 速度闪动 + 电源/网络灯
APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-${APP_ROOT:-/var/apps/${APP_NAME}}}"
VAR_DIR="${TRIM_PKGVAR:-${VAR_DIR:-${APP_ROOT}/var}}"
LOG_DIR="${LOG_DIR:-${VAR_DIR}/log}"

SERVER_DIR="${SERVER_DIR:-}"
if [[ -z "$SERVER_DIR" ]]; then
    for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
        [[ -f "${d}/led_daemon.sh" ]] && SERVER_DIR="$d" && break
    done
fi
SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"
LIB_DIR="${SERVER_DIR}/lib"
source "${LIB_DIR}/app_paths.sh"
ugreen_resolve_runtime || exit 1

PID_FILE="${PID_FILE:-${RUNTIME_DIR}/led_daemon.pid}"
LEGACY_PID_FILE="${VAR_DIR}/led_daemon.pid"
SETTINGS_FILE="${VAR_DIR}/settings.conf"
DISK_STATUS_FILE="${RUNTIME_DIR}/disk_status.tsv"
NET_STATUS_FILE="${RUNTIME_DIR}/net_status.tsv"
UGREEN_CLI=""
for c in "${SERVER_DIR}/bin/ugreen_leds_cli" "${APP_ROOT}/target/server/bin/ugreen_leds_cli" /usr/bin/ugreen_leds_cli; do
    [[ -x "$c" ]] && UGREEN_CLI="$c" && break
done
export TARGET="${APP_ROOT}"

export UGREEN_CLI LED_API_CACHE_DIR="${RUNTIME_DIR}/led_cache"
export DISK_IO_CACHE_DIR="${RUNTIME_DIR}/disk_io"
export NET_SPEED_CACHE_FILE="${RUNTIME_DIR}/net_speed.cache"
export NET_STATE_CACHE_FILE="${RUNTIME_DIR}/net_state.cache"

source "${LIB_DIR}/settings.sh"
source "${LIB_DIR}/hardware_profile.sh"
source "${LIB_DIR}/driver_manager.sh"
source "${LIB_DIR}/led_api.sh"
source "${LIB_DIR}/disk_map.sh"
source "${LIB_DIR}/disk_state.sh"
source "${LIB_DIR}/net_state.sh"
source "${LIB_DIR}/led_apply.sh"

mkdir -p "$LOG_DIR" "$LED_API_CACHE_DIR" "$DISK_IO_CACHE_DIR"
settings_init "$SETTINGS_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_DIR}/daemon.log"
}

declare -A LOG_THROTTLE
log_limited() {
    local key="$1" interval="$2"
    shift 2
    local now last
    now=$(date +%s)
    last="${LOG_THROTTLE[$key]:-0}"
    if (( now - last >= interval )); then
        LOG_THROTTLE["$key"]="$now"
        log "$*"
    fi
}

positive_int() {
    local value="$1" fallback="$2"
    if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]]; then
        echo "$value"
    else
        echo "$fallback"
    fi
}

bounded_int() {
    local value="$1" min="$2" max="$3" fallback="$4"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
        echo "$value"
    else
        echo "$fallback"
    fi
}

declare -A DISK_STATE_CACHE
declare -A NET_STATE_CACHE
LAST_DEVICE_HASH=""
LAST_HOTPLUG_CHECK=0
DAEMON_RUN=true
MAPPING_READY=false

ensure_mapping() {
    local mapping_mode profile product
    mapping_mode=$(disk_mapping_mode "$SETTINGS_FILE")
    if [[ "$mapping_mode" == "position" || "$mapping_mode" == "disk" ]]; then
        DISK_LED_MAP=()
        disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || true
    else
        disk_refresh_mapping "$SETTINGS_FILE"
    fi
    rm -f "${DISK_IO_CACHE_DIR}/"*.io "${DISK_IO_CACHE_DIR}/"*.power 2>/dev/null
    MAPPING_READY=true
    profile=$(hardware_profile_key)
    product=$(hardware_detected_product_name)
    log "${mapping_mode} 映射 ${#DISK_LED_MAP[@]} 项，机型=${product:-unknown}，档案=$profile -> $(printf '%s ' "${DISK_LED_MAP[@]}")"
}

reload_runtime() {
    led_clear_cache
    MAPPING_READY=false
    ensure_mapping
}

check_hotplug() {
    local interval="${1:-30}" hash remap now
    now=$(date +%s)
    if (( LAST_HOTPLUG_CHECK > 0 && now - LAST_HOTPLUG_CHECK < interval )); then
        return
    fi
    LAST_HOTPLUG_CHECK="$now"
    remap=$(settings_get "$SETTINGS_FILE" behavior remap_on_hotplug "true")
    [[ "$remap" == "true" ]] || return
    hash=$(disk_snapshot_devices | sort | md5sum 2>/dev/null | awk '{print $1}')
    [[ -z "$hash" ]] && return
    if [[ -n "$LAST_DEVICE_HASH" && "$hash" != "$LAST_DEVICE_HASH" ]]; then
        log "检测到硬盘拓扑或身份变化，重新生成映射"
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

sorted_disk_mapping() {
    local dev
    for dev in "${!DISK_LED_MAP[@]}"; do
        printf '%s|%s\n' "$dev" "${DISK_LED_MAP[$dev]}"
    done | sort -t'|' -k2,2V
}

write_net_runtime_status() {
    local state="$1" domestic="$2" overseas="$3" rx="$4" tx="$5" total="$6"
    local label tmp now
    label=$(net_state_label "$state")
    now=$(date +%s)
    tmp="${NET_STATUS_FILE}.tmp.$$"
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$state" "$label" "$domestic" "$overseas" "$rx" "$tx" "$total" "$now" > "$tmp"
    mv "$tmp" "$NET_STATUS_FILE"
}

tick_mode_smart() {
    local dev led state cached idle_sec sample read_kbps write_kbps total_kbps
    local manage_power manage_netdev disk_blink net_blink disk_threshold net_threshold
    local disk_tmp now net_sample rx_kbps tx_kbps net_total probe_sample ns domestic overseas probe_ttl
    local disk_power_probe_interval hotplug_check_interval net_led

    idle_sec=$(positive_int "$(settings_get "$SETTINGS_FILE" daemon io_idle_seconds "8")" 8)
    manage_power=$(settings_get "$SETTINGS_FILE" behavior manage_power "true")
    manage_netdev=$(settings_get "$SETTINGS_FILE" behavior manage_netdev "true")
    disk_blink=$(settings_get "$SETTINGS_FILE" activity disk_blink "false")
    net_blink=$(settings_get "$SETTINGS_FILE" activity network_blink "false")
    disk_threshold=$(positive_int "$(settings_get "$SETTINGS_FILE" activity disk_threshold_kbps "128")" 128)
    net_threshold=$(positive_int "$(settings_get "$SETTINGS_FILE" activity network_threshold_kbps "32")" 32)
    probe_ttl=$(positive_int "$(settings_get "$SETTINGS_FILE" daemon network_probe_interval "30")" 30)
    disk_power_probe_interval=$(bounded_int "$(settings_get "$SETTINGS_FILE" daemon disk_power_probe_interval "60")" 10 3600 60)
    hotplug_check_interval=$(bounded_int "$(settings_get "$SETTINGS_FILE" daemon hotplug_check_interval "30")" 5 3600 30)

    $MAPPING_READY || ensure_mapping
    check_hotplug "$hotplug_check_interval"

    disk_tmp="${DISK_STATUS_FILE}.tmp.$$"
    : > "$disk_tmp"
    now=$(date +%s)
    while IFS='|' read -r dev led; do
        [[ -n "$dev" && -n "$led" ]] || continue
        sample=$(disk_detect_smart_sample "$dev" "$idle_sec" "$disk_power_probe_interval")
        IFS='|' read -r state read_kbps write_kbps total_kbps <<< "$sample"
        state="${state:-offline}"
        read_kbps="${read_kbps:-0}"
        write_kbps="${write_kbps:-0}"
        total_kbps="${total_kbps:-0}"

        cached="${DISK_STATE_CACHE[$dev]:-}"
        if [[ "$state" != "$cached" ]]; then
            DISK_STATE_CACHE["$dev"]="$state"
            log "磁盘 $dev -> $led : $state (读 ${read_kbps}KB/s, 写 ${write_kbps}KB/s)"
        fi

        if [[ "$disk_blink" == "true" && "$state" == "active" && "$total_kbps" -ge "$disk_threshold" ]]; then
            apply_disk_activity_led "$led" "$state" "$SETTINGS_FILE" "$total_kbps" "$disk_threshold" || \
                log_limited "disk:${led}" 60 "WARN $led 闪动失败"
        else
            apply_disk_state_led "$led" "$state" "$SETTINGS_FILE" || \
                log_limited "disk:${led}" 60 "WARN $led 状态应用失败"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "$dev" "$led" "$state" "$read_kbps" "$write_kbps" "$total_kbps" "$now" >> "$disk_tmp"
    done < <(sorted_disk_mapping)
    mv "$disk_tmp" "$DISK_STATUS_FILE"

    for led in $(disk_unmapped_slots 2>/dev/null); do
        led_set_off "$led"
    done

    if [[ "$manage_netdev" == "true" ]]; then
        net_sample=$(net_sample_speed)
        IFS='|' read -r rx_kbps tx_kbps net_total <<< "$net_sample"
        probe_sample=$(net_detect_state_cached "$probe_ttl")
        IFS='|' read -r ns domestic overseas <<< "$probe_sample"
        ns="${ns:-disconnected}"
        rx_kbps="${rx_kbps:-0}"
        tx_kbps="${tx_kbps:-0}"
        net_total="${net_total:-0}"

        if [[ "$ns" != "${NET_STATE_CACHE[main]:-}" ]]; then
            NET_STATE_CACHE[main]="$ns"
            log "网络: $ns"
        fi
        while IFS= read -r net_led; do
            [[ -n "$net_led" ]] || continue
            if [[ "$net_blink" == "true" && "$ns" != "disconnected" && "$net_total" -ge "$net_threshold" ]]; then
                apply_netdev_activity "$ns" "$SETTINGS_FILE" "$net_total" "$net_threshold" "$net_led"
            else
                apply_netdev_state "$ns" "$SETTINGS_FILE" "$net_led"
            fi
        done < <(led_list_network_slots)
        write_net_runtime_status "$ns" "${domestic:-0}" "${overseas:-0}" "$rx_kbps" "$tx_kbps" "$net_total"
    fi

    if [[ "$manage_power" == "true" ]]; then
        apply_power_smart "$SETTINGS_FILE"
    fi
}

daemon_loop() {
    local interval mode enabled
    trap 'DAEMON_RUN=false' TERM INT
    trap 'reload_runtime' HUP
    log "启动 mode=$(settings_get "$SETTINGS_FILE" mode global smart) backend=$(led_backend_name) cli=$UGREEN_CLI runtime=$RUNTIME_DIR"
    ensure_mapping

    while $DAEMON_RUN; do
        interval=$(settings_get "$SETTINGS_FILE" daemon check_interval "5")
        [[ "$interval" =~ ^[0-9]+$ ]] || interval=5
        (( interval < 1 )) && interval=1
        enabled=$(settings_get "$SETTINGS_FILE" daemon enabled "true")
        if [[ "$enabled" != "true" ]]; then
            sleep "$interval"
            continue
        fi
        if ! ensure_led_backend; then
            log_limited "backend" 60 "ERROR LED 控制后端不可用或发生冲突"
            sleep "$interval"
            continue
        fi

        # 实验室检测期间由 CGI 临时接管硬盘灯，避免守护循环覆盖识别灯效。
        if lab_mapping_session_active; then
            sleep "$interval"
            continue
        fi

        mode=$(settings_get "$SETTINGS_FILE" mode global "smart")
        case "$mode" in
            off) tick_mode_off ;;
            on) tick_mode_on ;;
            smart|*) tick_mode_smart ;;
        esac
        sleep "$interval"
    done
    [[ -f "$PID_FILE" && "$(cat "$PID_FILE" 2>/dev/null)" == "${BASHPID:-$$}" ]] && rm -f "$PID_FILE"
}

stop_daemon() {
    DAEMON_RUN=false
    [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null
    if [[ "$LEGACY_PID_FILE" != "$PID_FILE" && -f "$LEGACY_PID_FILE" ]]; then
        kill "$(cat "$LEGACY_PID_FILE")" 2>/dev/null
    fi
    rm -f "$PID_FILE"
    rm -f "$LEGACY_PID_FILE"
}

migrate_legacy_runtime() {
    local old_pid="" i
    if [[ "$LEGACY_PID_FILE" != "$PID_FILE" && -f "$LEGACY_PID_FILE" ]]; then
        old_pid=$(cat "$LEGACY_PID_FILE" 2>/dev/null || true)
        if [[ -n "$old_pid" && "$old_pid" != "${BASHPID:-$$}" ]] && kill -0 "$old_pid" 2>/dev/null; then
            kill "$old_pid" 2>/dev/null || true
            for ((i=0; i<60; i++)); do
                kill -0 "$old_pid" 2>/dev/null || break
                sleep 0.1
            done
            if kill -0 "$old_pid" 2>/dev/null; then
                echo "旧版 LED 守护进程未能停止: $old_pid" >&2
                return 1
            fi
        fi
    fi

    rm -f "$LEGACY_PID_FILE" \
        "${VAR_DIR}/disk_status.tsv" "${VAR_DIR}/net_status.tsv" \
        "${VAR_DIR}/net_speed.cache" "${VAR_DIR}/net_state.cache" 2>/dev/null
    rm -rf "${VAR_DIR}/led_cache" "${VAR_DIR}/disk_io" 2>/dev/null
}

case "${1:-}" in
    start|_daemon)
        migrate_legacy_runtime || exit 1
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
