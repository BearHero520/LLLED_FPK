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

        net="disconnected" nlabel="断网" nd=0 no=0 rx=0 tx=0 total=0 updated=0
        if [[ -f "$NET_STATUS_FILE" ]]; then
            IFS='|' read -r net nlabel nd no rx tx total updated < "$NET_STATUS_FILE"
        fi
        printf '{"ok":true,"daemon":"%s","mode":"%s","network":"%s","network_label":"%s","net_domestic":%s,"net_overseas":%s,"net_rx_kbps":%s,"net_tx_kbps":%s,"net_total_kbps":%s,"updated_at":%s,"led_status":"%s"}' \
            "$d" "$mode" "$net" "$(json_str "$nlabel")" "${nd:-0}" "${no:-0}" "${rx:-0}" "${tx:-0}" "${total:-0}" "${updated:-0}" "$(json_str "$st")"
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
