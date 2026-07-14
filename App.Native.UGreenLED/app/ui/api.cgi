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

source "${LIB_DIR}/led_api.sh" 2>/dev/null
source "${LIB_DIR}/settings.sh" 2>/dev/null
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
    local message="${1:-}" active=false mode slot first dev hctl serial model size transport led supported
    lab_mapping_session_active && active=true
    mode=$(disk_mapping_mode "$SETTINGS_FILE")
    disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || DISK_LED_MAP=()

    printf '{"ok":true,"active":%s,"mode":"%s","session_ttl":%s,"slots":[' "$active" "$(json_str "$mode")" "$LAB_MAPPING_SESSION_TTL"
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
        [[ $first -eq 0 ]] && printf ','
        first=0
        led="${DISK_LED_MAP[$dev]:-}"
        supported=false
        [[ "$hctl" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]] && supported=true
        printf '{"device":"%s","hctl":"%s","serial":"%s","model":"%s","size":"%s","transport":"%s","led":"%s","supported":%s}' \
            "$(json_str "$dev")" "$(json_str "$hctl")" "$(json_str "$serial")" "$(json_str "$model")" \
            "$(json_str "$size")" "$(json_str "$transport")" "$(json_str "$led")" "$supported"
    done < <(disk_inventory_rows)
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
        elif ! ensure_cli; then
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
        elif disk_save_manual_mapping "$SETTINGS_FILE" <<< "$POST_DATA"; then
            lab_mapping_resume_control
            lab_mapping_status_json "自定义硬盘位置已保存"
        else
            result=$?
            case "$result" in
                3) error="包含不存在的 LED 盘位" ;;
                4) error="硬盘设备或 HCTL 已变化，请重新开始检测" ;;
                5) error="同一硬盘或盘位不能重复绑定" ;;
                6) error="请至少绑定一个硬盘盘位" ;;
                *) error="映射数据无效，未保存任何更改" ;;
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
    /led/set)
        led=$(query_value led); r=$(query_value r); g=$(query_value g); b=$(query_value b); br=$(query_value brightness)
        br="${br:-64}"
        if [[ "$led" =~ ^(power|netdev|disk[1-9][0-9]*)$ && "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ && "$br" =~ ^[0-9]+$ ]] && \
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
        if [[ "$led" =~ ^(power|netdev|disk[1-9][0-9]*)$ ]]; then
            led_set_off "$led" && printf '{"ok":true,"led":"%s"}' "$led" || echo '{"ok":false,"error":"led command failed"}'
        else
            echo '{"ok":false,"error":"invalid led"}'
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
