#!/bin/bash
APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-/var/apps/${APP_NAME}}"
VAR_DIR="${TRIM_PKGVAR:-${APP_ROOT}/var}"

SERVER_DIR=""
for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
    [[ -f "${d}/led_daemon.sh" ]] && SERVER_DIR="$d" && break
done
SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"

LIB_DIR="${SERVER_DIR}/lib"
source "${LIB_DIR}/app_paths.sh" 2>/dev/null
ugreen_resolve_runtime || exit 1

SETTINGS_FILE="${VAR_DIR}/settings.conf"
PID_FILE="${RUNTIME_DIR}/led_daemon.pid"
DISK_STATUS_FILE="${RUNTIME_DIR}/disk_status.tsv"
NET_STATUS_FILE="${RUNTIME_DIR}/net_status.tsv"
UPDATE_CACHE_FILE="${RUNTIME_DIR}/update_check.cache"
UPDATE_REPOSITORY="BearHero520/LLLED_FPK"
UPDATE_LATEST_URL="https://github.com/${UPDATE_REPOSITORY}/releases/latest"
UPDATE_API_URL="https://api.github.com/repos/${UPDATE_REPOSITORY}/releases/latest"
UPDATE_CACHE_TTL=21600
UGREEN_CLI=""
for c in "${SERVER_DIR}/bin/ugreen_leds_cli" "${APP_ROOT}/target/server/bin/ugreen_leds_cli" /usr/bin/ugreen_leds_cli; do
    [[ -x "$c" ]] && UGREEN_CLI="$c" && break
done

export TARGET="$APP_ROOT" SERVER_DIR
export UGREEN_CLI LED_API_CACHE_DIR="${RUNTIME_DIR}/led_cache" DISK_IO_CACHE_DIR="${RUNTIME_DIR}/disk_io"
export NET_SPEED_CACHE_FILE="${RUNTIME_DIR}/net_speed.cache" NET_STATE_CACHE_FILE="${RUNTIME_DIR}/net_state.cache"

source "${LIB_DIR}/settings.sh" 2>/dev/null
source "${LIB_DIR}/hardware_profile.sh" 2>/dev/null
source "${LIB_DIR}/driver_manager.sh" 2>/dev/null
source "${LIB_DIR}/led_api.sh" 2>/dev/null
source "${LIB_DIR}/disk_map.sh" 2>/dev/null
source "${LIB_DIR}/disk_state.sh" 2>/dev/null
source "${LIB_DIR}/net_state.sh" 2>/dev/null
source "${LIB_DIR}/led_apply.sh" 2>/dev/null

QUERY_STRING="${QUERY_STRING:-}"
REQUEST_METHOD="${REQUEST_METHOD:-GET}"
POST_DATA=""
POST_TOO_LARGE=false
if [[ "$REQUEST_METHOD" == "POST" && "${CONTENT_LENGTH:-0}" =~ ^[0-9]+$ && "${CONTENT_LENGTH:-0}" -gt 65536 ]]; then
    POST_TOO_LARGE=true
elif [[ "$REQUEST_METHOD" == "POST" && "${CONTENT_LENGTH:-0}" =~ ^[0-9]+$ ]]; then
    POST_DATA=$(head -c "${CONTENT_LENGTH:-0}")
fi

# fnOS/nginx 传参方式不一：PATH_INFO 可能是 /status、status、或整段 .../api.cgi/status
ugreen_api_path() {
    local p="" uri="" c
    for c in "${PATH_INFO:-}" "${REQUEST_URI:-}" "${REDIRECT_URL:-}" "${DOCUMENT_URI:-}"; do
        [[ -z "$c" ]] && continue
        uri="${c%%\?*}"
        case "$uri" in
            */api.cgi/*) p="/${uri#*api.cgi/}"; break ;;
            */api.cgi) p="/"; break ;;
            *)
                [[ "$uri" == /* ]] && p="$uri" || p="/${uri}"
                break
                ;;
        esac
    done
    [[ -z "$p" ]] && p="/"
    [[ "$p" != /* ]] && p="/$p"
    echo "$p"
}
API_PATH="$(ugreen_api_path)"

json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

query_value() {
    local key="$1"
    echo "$QUERY_STRING" | sed -n "s/.*${key}=\([^&]*\).*/\1/p"
}

current_app_version() {
    local manifest_file version
    for manifest_file in \
        "${APP_ROOT}/manifest" \
        "${APP_ROOT}/target/manifest" \
        "${APP_ROOT}/../manifest" \
        "/var/apps/@appcenter/${APP_NAME}/manifest"; do
        [[ -f "$manifest_file" ]] || continue
        version=$(sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$manifest_file" | head -n 1)
        version="${version//[[:space:]]/}"
        [[ -n "$version" ]] && { printf '%s' "$version"; return; }
    done
    printf '%s' "unknown"
}

fetch_latest_release_tag() {
    local response="" tag="" effective_url="" location=""
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -fsSL --retry 2 --connect-timeout 5 --max-time 20 \
            -H 'Accept: application/vnd.github+json' -H 'User-Agent: UGreenLED-fnOS' \
            "$UPDATE_API_URL" 2>/dev/null || true)
        tag=$(printf '%s\n' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        if [[ -z "$tag" ]]; then
            effective_url=$(curl -fsSL --retry 1 --connect-timeout 5 --max-time 20 -o /dev/null \
                -w '%{url_effective}' "$UPDATE_LATEST_URL" 2>/dev/null || true)
            tag="${effective_url##*/}"
        fi
    elif command -v wget >/dev/null 2>&1; then
        response=$(wget -qO- --timeout=20 --header='Accept: application/vnd.github+json' \
            --header='User-Agent: UGreenLED-fnOS' "$UPDATE_API_URL" 2>/dev/null || true)
        tag=$(printf '%s\n' "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        if [[ -z "$tag" ]]; then
            location=$(wget --spider --server-response --max-redirect=10 --timeout=20 "$UPDATE_LATEST_URL" 2>&1 | \
                sed -n 's/^[[:space:]]*[Ll]ocation:[[:space:]]*\([^[:space:]]*\).*/\1/p' | tail -n 1)
            effective_url="${location//$'\r'/}"
            tag="${effective_url##*/}"
        fi
    else
        return 1
    fi

    [[ "$tag" =~ ^v?[0-9]+([.][0-9]+){1,3}([._-][0-9A-Za-z.-]+)?$ ]] || return 1
    printf '%s' "$tag"
}

update_check_json() {
    local force="$1" current latest_tag="" latest_version="" now cached_tag="" cached_at=0
    local release_url download_url cache_age
    current=$(current_app_version)
    now=$(date +%s)

    if [[ "$force" != "1" && -f "$UPDATE_CACHE_FILE" ]]; then
        IFS='|' read -r cached_tag cached_at < "$UPDATE_CACHE_FILE"
        cached_at="${cached_at:-0}"
        if [[ "$cached_at" =~ ^[0-9]+$ ]]; then
            cache_age=$((now - cached_at))
            if (( cache_age >= 0 && cache_age <= UPDATE_CACHE_TTL )); then
                latest_tag="$cached_tag"
            fi
        fi
    fi

    if [[ -z "$latest_tag" ]]; then
        latest_tag=$(fetch_latest_release_tag 2>/dev/null || true)
        if [[ -n "$latest_tag" ]]; then
            printf '%s|%s\n' "$latest_tag" "$now" > "${UPDATE_CACHE_FILE}.tmp" 2>/dev/null && \
                mv "${UPDATE_CACHE_FILE}.tmp" "$UPDATE_CACHE_FILE" 2>/dev/null || true
        fi
    fi

    if [[ -z "$latest_tag" ]]; then
        printf '{"ok":true,"reachable":false,"current_version":"%s","checked_at":%s,"error":"无法连接 GitHub Release"}' \
            "$(json_str "$current")" "$now"
        return
    fi

    latest_version="${latest_tag#v}"
    release_url="https://github.com/${UPDATE_REPOSITORY}/releases/tag/${latest_tag}"
    download_url="https://github.com/${UPDATE_REPOSITORY}/releases/download/${latest_tag}/App.Native.UGreenLED.fpk"
    printf '{"ok":true,"reachable":true,"current_version":"%s","latest_version":"%s","latest_tag":"%s","release_url":"%s","download_url":"%s","checked_at":%s}' \
        "$(json_str "$current")" "$(json_str "$latest_version")" "$(json_str "$latest_tag")" \
        "$(json_str "$release_url")" "$(json_str "$download_url")" "$now"
}

lab_mapping_resume_control() {
    lab_mapping_session_end
    led_clear_cache 2>/dev/null
    rm -f "$DISK_STATUS_FILE"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
    else
        bash "${SERVER_DIR}/led_daemon.sh" once >/dev/null 2>&1 || true
    fi
}

lab_mapping_status_json() {
    local message="${1:-}" active=false mode slot first dev hctl serial model size transport led
    local position=0 position_supported identity_supported position_led identity_led product profile auto_led physical_position
    declare -A position_led_map=() identity_led_map=()
    lab_mapping_session_active && active=true
    mode=$(disk_mapping_mode "$SETTINGS_FILE")
    product=$(hardware_detected_product_name)
    profile=$(hardware_profile_key)

    DISK_LED_MAP=()
    disk_load_position_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || true
    for dev in "${!DISK_LED_MAP[@]}"; do position_led_map["$dev"]="${DISK_LED_MAP[$dev]}"; done
    DISK_LED_MAP=()
    disk_load_identity_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || true
    for dev in "${!DISK_LED_MAP[@]}"; do identity_led_map["$dev"]="${DISK_LED_MAP[$dev]}"; done
    disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || DISK_LED_MAP=()

    printf '{"ok":true,"active":%s,"mode":"%s","product_name":"%s","profile":"%s","session_ttl":%s,"slots":[' \
        "$active" "$(json_str "$mode")" "$(json_str "$product")" "$(json_str "$profile")" "$LAB_MAPPING_SESSION_TTL"
    first=1
    while IFS= read -r slot; do
        [[ -n "$slot" ]] || continue
        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '{"led":"%s","position":%s}' "$(json_str "$slot")" "${slot#disk}"
    done < <(disk_available_slots)
    printf '],"disks":['
    first=1
    while IFS='|' read -r dev hctl serial model size transport; do
        [[ -n "$dev" ]] || continue
        position=$((position + 1))
        auto_led=$(disk_guess_led_by_hctl "$hctl")
        physical_position="$position"
        [[ "$auto_led" =~ ^disk([1-9][0-9]*)$ ]] && physical_position="${BASH_REMATCH[1]}"
        [[ $first -eq 0 ]] && printf ','
        first=0
        led="${DISK_LED_MAP[$dev]:-}"
        position_led="${position_led_map[$dev]:-}"
        identity_led="${identity_led_map[$dev]:-}"
        position_supported=false
        identity_supported=false
        [[ "$hctl" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] && position_supported=true
        [[ -n "$serial" ]] && identity_supported=true
        printf '{"position":%s,"device":"%s","hctl":"%s","serial":"%s","model":"%s","size":"%s","transport":"%s","led":"%s","position_led":"%s","identity_led":"%s","supported":%s,"position_supported":%s,"identity_supported":%s}' \
            "$physical_position" \
            "$(json_str "$dev")" "$(json_str "$hctl")" "$(json_str "$serial")" "$(json_str "$model")" \
            "$(json_str "$size")" "$(json_str "$transport")" "$(json_str "$led")" \
            "$(json_str "$position_led")" "$(json_str "$identity_led")" \
            "$position_supported" "$position_supported" "$identity_supported"
    done < <(disk_inventory_rows | sort -t'|' -k2,2V)
    printf ']'
    [[ -n "$message" ]] && printf ',"message":"%s"' "$(json_str "$message")"
    printf '}'
}

runtime_file_fresh() {
    local f="$1" max_age="${2:-30}" modified now
    [[ -f "$f" ]] || return 1
    modified=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    now=$(date +%s)
    (( now - modified <= max_age ))
}

hardware_status_json() {
    local product profile profile_name support protocol protocol_configured disk_count netdev_count configured active
    local cli_ready=false driver_loaded=false sysfs_ready=false dkms_ready=false headers_ready=false conflict=false dkms_installed=false dkms_registered=false driver_managed=false driver_supported=true
    product=$(hardware_detected_product_name)
    profile=$(hardware_profile_key)
    profile_name=$(hardware_profile_display_name "$profile")
    support=$(hardware_support_level "$profile")
    protocol=$(hardware_write_protocol "$profile")
    protocol_configured=$(settings_get "$SETTINGS_FILE" hardware write_protocol "auto")
    disk_count=$(hardware_disk_count "$profile")
    netdev_count=$(hardware_netdev_count "$profile")
    configured=$(led_backend_configured)
    active=$(led_backend_name)
    led_cli_available && cli_ready=true
    driver_module_loaded && driver_loaded=true
    driver_sysfs_ready && sysfs_ready=true
    driver_dkms_ready && dkms_ready=true
    driver_headers_ready && headers_ready=true
    driver_vendor_conflict && conflict=true
    driver_dkms_installed 2>/dev/null && dkms_installed=true
    driver_dkms_registered 2>/dev/null && dkms_registered=true
    driver_managed_by_app && driver_managed=true
    declare -F hardware_driver_supported >/dev/null && ! hardware_driver_supported "$profile" && driver_supported=false
    [[ "$disk_count" =~ ^[0-9]+$ ]] || disk_count=0
    printf '{"ok":true,"product_name":"%s","profile":"%s","profile_name":"%s","support":"%s","cli_version":"%s","write_protocol":"%s","write_protocol_configured":"%s","disk_count":%s,"netdev_count":%s,"backend_configured":"%s","backend_active":"%s","cli_ready":%s,"driver_loaded":%s,"sysfs_ready":%s,"dkms_ready":%s,"headers_ready":%s,"driver_conflict":%s,"dkms_installed":%s,"dkms_registered":%s,"driver_managed":%s,"driver_supported":%s,"kernel":"%s"}' \
        "$(json_str "$product")" "$(json_str "$profile")" "$(json_str "$profile_name")" "$(json_str "$support")" \
        "$(json_str "$UGREEN_CLI_RELEASE")" "$(json_str "$protocol")" "$(json_str "$protocol_configured")" "$disk_count" "$netdev_count" "$(json_str "$configured")" "$(json_str "$active")" \
        "$cli_ready" "$driver_loaded" "$sysfs_ready" "$dkms_ready" "$headers_ready" "$conflict" "$dkms_installed" "$dkms_registered" "$driver_managed" "$driver_supported" "$(json_str "$(driver_kernel_release)")"
}

echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-store"
echo "X-Content-Type-Options: nosniff"
echo ""
settings_init "$SETTINGS_FILE" 2>/dev/null

case "$API_PATH" in
    /status)
        d="stopped"
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && d="running"
        mode=$(settings_get "$SETTINGS_FILE" mode global "smart")
        st=$(led_all_status 2>/dev/null || echo "")
        lab_active=false
        lab_mapping_session_active && lab_active=true

        net="disconnected" nlabel="断网" nd=0 no=0 rx=0 tx=0 total=0 updated=0
        if [[ -f "$NET_STATUS_FILE" ]]; then
            IFS='|' read -r net nlabel nd no rx tx total updated < "$NET_STATUS_FILE"
        fi
        printf '{"ok":true,"daemon":"%s","mode":"%s","network":"%s","network_label":"%s","net_domestic":%s,"net_overseas":%s,"net_rx_kbps":%s,"net_tx_kbps":%s,"net_total_kbps":%s,"updated_at":%s,"lab_mapping_active":%s,"led_status":"%s"}' \
            "$d" "$mode" "$net" "$(json_str "$nlabel")" "${nd:-0}" "${no:-0}" "${rx:-0}" "${tx:-0}" "${total:-0}" "${updated:-0}" "$lab_active" "$(json_str "$st")"
        ;;
    /hardware/status)
        hardware_status_json
        ;;
    /mapping)
        disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || DISK_LED_MAP=()
        printf '{"ok":true,"mapping":['
        first=1
        if runtime_file_fresh "$DISK_STATUS_FILE" 90; then
            while IFS='|' read -r dev led state read_kbps write_kbps total_kbps updated; do
                [[ -n "$dev" ]] || continue
                [[ $first -eq 0 ]] && printf ','
                first=0
                printf '{"device":"%s","led":"%s","state":"%s","read_kbps":%s,"write_kbps":%s,"total_kbps":%s,"updated_at":%s}' \
                    "$(json_str "$dev")" "$(json_str "$led")" "$state" "${read_kbps:-0}" "${write_kbps:-0}" "${total_kbps:-0}" "${updated:-0}"
            done < "$DISK_STATUS_FILE"
        else
            for dev in "${!DISK_LED_MAP[@]}"; do
                led="${DISK_LED_MAP[$dev]}"
                [[ $first -eq 0 ]] && printf ','
                first=0
                printf '{"device":"%s","led":"%s","state":"%s","read_kbps":%s,"write_kbps":%s,"total_kbps":%s}' \
                    "$(json_str "$dev")" "$(json_str "$led")" "unknown" 0 0 0
            done
        fi
        printf ']}'
        ;;
    /settings)
        if [[ "$REQUEST_METHOD" == "POST" ]]; then
            if $POST_TOO_LARGE; then
                echo '{"ok":false,"error":"settings payload too large"}'
            elif settings_apply_updates "$SETTINGS_FILE" <<< "$POST_DATA"; then
                led_clear_cache 2>/dev/null
                if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
                fi
                echo '{"ok":true}'
            else
                echo '{"ok":false,"error":"invalid settings payload"}'
            fi
        else
            echo -n '{"ok":true,"raw":"'
            json_str "$(cat "$SETTINGS_FILE" 2>/dev/null)"
            echo '"}'
        fi
        ;;
    /update/check)
        force=$(query_value force)
        update_check_json "$force"
        ;;
    /lab/mapping/status)
        lab_mapping_status_json
        ;;
    /lab/mapping/start)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! ensure_led_backend; then
            echo '{"ok":false,"error":"LED 控制程序不可用，无法进入检测模式"}'
        elif lab_mapping_show_all; then
            lab_mapping_status_json "检测模式已启动，全部硬盘灯已点亮"
        else
            lab_mapping_resume_control
            echo '{"ok":false,"error":"部分硬盘灯点亮失败，已退出检测模式"}'
        fi
        ;;
    /lab/mapping/highlight)
        led=$(query_value led)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! lab_mapping_session_active; then
            echo '{"ok":false,"error":"检测会话已结束，请重新开始"}'
        elif lab_mapping_highlight_slot "$led"; then
            lab_mapping_status_json "${led} 正在闪烁"
        else
            echo '{"ok":false,"error":"无法点亮指定盘位"}'
        fi
        ;;
    /lab/mapping/save)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! lab_mapping_session_active; then
            echo '{"ok":false,"error":"检测会话已结束，请重新开始"}'
        elif disk_save_identity_mapping "$SETTINGS_FILE" <<< "$POST_DATA"; then
            lab_mapping_resume_control
            lab_mapping_status_json "按硬盘绑定已保存"
        else
            result=$?
            case "$result" in
                3) error="包含不存在的 LED 盘位" ;;
                4) error="硬盘设备或序列号已变化，请重新开始检测" ;;
                5) error="同一硬盘或 LED 不能重复绑定" ;;
                6) error="请至少绑定一块硬盘" ;;
                *) error="映射数据无效，未保存任何更改" ;;
            esac
            printf '{"ok":false,"error":"%s"}' "$(json_str "$error")"
        fi
        ;;
    /lab/position/save)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! lab_mapping_session_active; then
            echo '{"ok":false,"error":"检测会话已结束，请重新开始"}'
        elif disk_save_position_mapping "$SETTINGS_FILE" <<< "$POST_DATA"; then
            lab_mapping_resume_control
            lab_mapping_status_json "灯光与硬盘位置绑定已保存"
        else
            result=$?
            case "$result" in
                3) error="包含不存在的 LED 盘位" ;;
                4) error="硬盘位置或 HCTL 已变化，请重新开始检测" ;;
                5) error="同一位置或 LED 不能重复绑定" ;;
                6) error="请至少绑定一个硬盘位置" ;;
                *) error="位置映射数据无效，未保存任何更改" ;;
            esac
            printf '{"ok":false,"error":"%s"}' "$(json_str "$error")"
        fi
        ;;
    /lab/mapping/cancel)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        else
            lab_mapping_resume_control
            lab_mapping_status_json "已退出检测模式，原映射保持不变"
        fi
        ;;
    /lab/mapping/reset)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif disk_reset_auto_mapping "$SETTINGS_FILE"; then
            lab_mapping_resume_control
            lab_mapping_status_json "已恢复自动 HCTL 映射"
        else
            echo '{"ok":false,"error":"恢复自动映射失败"}'
        fi
        ;;
    /mode)
        m=$(query_value mode)
        case "$m" in
            off|on|smart)
                settings_set "$SETTINGS_FILE" mode global "$m"
                led_clear_cache 2>/dev/null
                if [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    bash "${SERVER_DIR}/led_daemon.sh" once 2>/dev/null
                fi
                printf '{"ok":true,"mode":"%s"}' "$m"
                ;;
            *) echo '{"ok":false,"error":"invalid mode"}' ;;
        esac
        ;;
    /remap)
        settings_set "$SETTINGS_FILE" behavior disk_map_mode auto
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            kill -HUP "$(cat "$PID_FILE")" 2>/dev/null
            sleep 0.2
        else
            bash "${SERVER_DIR}/led_daemon.sh" remap 2>/dev/null
        fi
        rm -f "$DISK_STATUS_FILE"
        disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null
        n=${#DISK_LED_MAP[@]}
        printf '{"ok":true,"message":"已重新检测 %s 块硬盘","disk_count":%s}' "$n" "$n"
        ;;
    /power26/apply)
        color=$(query_value color)
        effect=$(query_value effect)
        threshold=$(query_value threshold); threshold="${threshold:-32}"
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif ! hardware_power26_controller; then
            echo '{"ok":false,"error":"current model does not use the power-0x26 backend"}'
        elif [[ ! "$color" =~ ^(red|white)$ || ! "$effect" =~ ^(steady|fast|slow|breath|network|off)$ || ! "$threshold" =~ ^[0-9]+$ ]] || \
            (( threshold < 1 || threshold > 1048576 )); then
            echo '{"ok":false,"error":"invalid power light parameters"}'
        elif ! ensure_led_backend || [[ "$LED_BACKEND_ACTIVE" != "power-0x26" ]]; then
            echo '{"ok":false,"error":"power-0x26 backend unavailable"}'
        else
            led_clear_cache 2>/dev/null
            command_effect="$effect"
            [[ "$command_effect" == "network" ]] && command_effect=steady
            if led_set_power26_effect "$color" "$command_effect"; then
                settings_set "$SETTINGS_FILE" power26 color "$color"
                if [[ "$effect" == "off" ]]; then
                    settings_set "$SETTINGS_FILE" mode global off
                    mode=off
                elif [[ "$effect" == "network" ]]; then
                    settings_set "$SETTINGS_FILE" power26 effect network
                    settings_set "$SETTINGS_FILE" power26 network_threshold_kbps "$threshold"
                    settings_set "$SETTINGS_FILE" mode global smart
                    mode=smart
                else
                    settings_set "$SETTINGS_FILE" power26 effect "$effect"
                    settings_set "$SETTINGS_FILE" power26 network_threshold_kbps "$threshold"
                    settings_set "$SETTINGS_FILE" mode global on
                    mode=on
                fi
                if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                    kill -HUP "$(cat "$PID_FILE")" 2>/dev/null || true
                fi
                if [[ "$effect" == "off" ]]; then
                    printf '{"ok":true,"mode":"off","color":"%s","effect":"off","message":"电源灯已关闭"}' "$color"
                else
                    printf '{"ok":true,"mode":"%s","color":"%s","effect":"%s","message":"480T 电源灯设置已应用"}' "$mode" "$color" "$effect"
                fi
            else
                echo '{"ok":false,"error":"power light command failed"}'
            fi
        fi
        ;;
    /led/set)
        led=$(query_value led); r=$(query_value r); g=$(query_value g); b=$(query_value b); br=$(query_value brightness)
        br="${br:-64}"
        if [[ "$led" =~ ^(power|netdev[1-9]*|disk[1-9][0-9]*)$ && "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$br" =~ ^[0-9]+$ ]] && \
            (( r <= 255 && g <= 255 && b <= 255 && br <= 255 )); then
            if led_set_color "$led" "$r" "$g" "$b" "$br"; then
                printf '{"ok":true,"led":"%s"}' "$led"
            else
                echo '{"ok":false,"error":"led command failed"}'
            fi
        else
            echo '{"ok":false,"error":"invalid led parameters"}'
        fi
        ;;
    /led/off)
        led=$(query_value led)
        if [[ "$led" =~ ^(power|netdev[1-9]*|disk[1-9][0-9]*)$ ]]; then
            led_set_off "$led" && printf '{"ok":true,"led":"%s"}' "$led" || echo '{"ok":false,"error":"led command failed"}'
        else
            echo '{"ok":false,"error":"invalid led"}'
        fi
        ;;
    /driver/install)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$(query_value confirm)" != "install-driver" ]]; then
            echo '{"ok":false,"error":"driver confirmation required"}'
        else
            daemon_was_running=false
            if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                daemon_was_running=true
                bash "${SERVER_DIR}/led_daemon.sh" stop >/dev/null 2>&1 || true
            fi
            driver_install >> "${VAR_DIR}/log/driver.log" 2>&1
            rc=$?
            if [[ $rc -eq 0 ]]; then
                settings_set "$SETTINGS_FILE" hardware backend sysfs
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                echo '{"ok":true,"message":"内核驱动已安装并切换到 sysfs 后端"}'
            else
                if driver_module_loaded; then
                    settings_set "$SETTINGS_FILE" hardware backend auto
                else
                    settings_set "$SETTINGS_FILE" hardware backend cli
                fi
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                printf '{"ok":false,"error":"%s"}' "$(json_str "$(driver_error_message "$rc")")"
            fi
        fi
        ;;
    /driver/unload)
        if [[ "$REQUEST_METHOD" != "POST" ]]; then
            echo '{"ok":false,"error":"method not allowed"}'
        elif [[ "$(query_value confirm)" != "unload-driver" ]]; then
            echo '{"ok":false,"error":"driver confirmation required"}'
        else
            daemon_was_running=false
            if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                daemon_was_running=true
                bash "${SERVER_DIR}/led_daemon.sh" stop >/dev/null 2>&1 || true
            fi
            if driver_unload >> "${VAR_DIR}/log/driver.log" 2>&1; then
                settings_set "$SETTINGS_FILE" hardware backend cli
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                echo '{"ok":true,"message":"内核驱动已卸载，已切换到 CLI 后端"}'
            else
                rc=$?
                settings_set "$SETTINGS_FILE" hardware backend auto
                $daemon_was_running && bash "${SERVER_DIR}/led_daemon.sh" start >/dev/null 2>&1 || true
                printf '{"ok":false,"error":"%s"}' "$(json_str "$(driver_error_message "$rc")")"
            fi
        fi
        ;;
    /daemon/start)
        if [[ -x "${APP_ROOT}/cmd/main" ]]; then
            "${APP_ROOT}/cmd/main" start 2>/dev/null
        else
            bash "${SERVER_DIR}/led_daemon.sh" start 2>/dev/null
        fi
        d="stopped"
        [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && d="running"
        printf '{"ok":true,"daemon":"%s","message":"后台已启动"}' "$d"
        ;;
    /daemon/stop)
        if [[ -x "${APP_ROOT}/cmd/main" ]]; then
            "${APP_ROOT}/cmd/main" stop 2>/dev/null
        else
            bash "${SERVER_DIR}/led_daemon.sh" stop 2>/dev/null
        fi
        echo '{"ok":true,"daemon":"stopped","message":"后台已停止"}'
        ;;
    *)
        printf '{"ok":false,"error":"unknown","path":"%s"}' "$(json_str "$API_PATH")"
        ;;
esac
