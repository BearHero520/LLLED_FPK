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
SETTINGS_FILE="${VAR_DIR}/settings.conf"
UGREEN_CLI=""
for c in "${SERVER_DIR}/bin/ugreen_leds_cli" "${APP_ROOT}/target/server/bin/ugreen_leds_cli" /usr/bin/ugreen_leds_cli; do
    [[ -x "$c" ]] && UGREEN_CLI="$c" && break
done

export UGREEN_CLI LED_API_CACHE_DIR="${VAR_DIR}/led_cache" DISK_IO_CACHE_DIR="${VAR_DIR}/disk_io"

source "${LIB_DIR}/led_api.sh" 2>/dev/null
source "${LIB_DIR}/settings.sh" 2>/dev/null
source "${LIB_DIR}/disk_map.sh" 2>/dev/null
source "${LIB_DIR}/disk_state.sh" 2>/dev/null
source "${LIB_DIR}/net_state.sh" 2>/dev/null
source "${LIB_DIR}/led_apply.sh" 2>/dev/null

QUERY_STRING="${QUERY_STRING:-}"
REQUEST_METHOD="${REQUEST_METHOD:-GET}"
POST_DATA=""
[[ "$REQUEST_METHOD" == "POST" && -n "${CONTENT_LENGTH:-}" ]] && POST_DATA=$(head -c "$CONTENT_LENGTH")

# fnOS/nginx 传参方式不一：PATH_INFO 可能是 /status、status、或整段 .../api.cgi/status
ugreen_api_path() {
    local p="" uri="" c
    for c in "${PATH_INFO:-}" "${REQUEST_URI:-}" "${REDIRECT_URL:-}" "${DOCUMENT_URI:-}"; do
        [[ -z "$c" ]] && continue
        uri="${c%%\?*}"
        case "$uri" in
            */api.cgi/*)
                p="/${uri#*api.cgi/}"
                break
                ;;
            */api.cgi)
                p="/"
                break
                ;;
            *)
                # 如 daemon/start、/daemon/start（无 api.cgi 前缀）
                if [[ "$uri" == /* ]]; then
                    p="$uri"
                else
                    p="/${uri}"
                fi
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
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

echo "Content-Type: application/json; charset=utf-8"
echo ""
settings_init "$SETTINGS_FILE" 2>/dev/null

case "$API_PATH" in
    /status)
        d="stopped"
        [[ -f "${VAR_DIR}/led_daemon.pid" ]] && kill -0 "$(cat "${VAR_DIR}/led_daemon.pid")" 2>/dev/null && d="running"
        mode=$(settings_get "$SETTINGS_FILE" mode global "smart")
        st=$(led_all_status 2>/dev/null || echo "")
        net=$(net_detect_state 2>/dev/null || echo "?")
        nd=0 no=0
        net_can_ping_domestic 2>/dev/null && nd=1
        net_can_ping_overseas 2>/dev/null && no=1
        nlabel=$(net_state_label "$net" 2>/dev/null || echo "$net")
        printf '{"ok":true,"daemon":"%s","mode":"%s","network":"%s","network_label":"%s","net_domestic":%s,"net_overseas":%s,"led_status":"%s"}' \
            "$d" "$mode" "$net" "$(json_str "$nlabel")" "$nd" "$no" "$(json_str "$st")"
        ;;
    /mapping)
        disk_refresh_mapping "$SETTINGS_FILE" 2>/dev/null
        printf '{"ok":true,"mapping":['
        first=1
        for dev in "${!DISK_LED_MAP[@]}"; do
            led="${DISK_LED_MAP[$dev]}"
            state=$(disk_detect_smart_state "$dev" "$(settings_get "$SETTINGS_FILE" daemon io_idle_seconds 8)" 2>/dev/null)
            [[ $first -eq 0 ]] && printf ','
            first=0
            printf '{"device":"%s","led":"%s","state":"%s"}' "$dev" "$led" "$state"
        done
        printf ']}'
        ;;
    /settings)
        if [[ "$REQUEST_METHOD" == "POST" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                if [[ "$line" =~ ^([^.]+)\.([^=]+)=(.*)$ ]]; then
                    settings_set "$SETTINGS_FILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
                fi
            done <<< "$POST_DATA"
            led_clear_cache 2>/dev/null
            echo '{"ok":true}'
        else
            echo -n '{"ok":true,"raw":"'
            json_str "$(cat "$SETTINGS_FILE" 2>/dev/null)"
            echo '"}'
        fi
        ;;
    /mode)
        m=$(echo "$QUERY_STRING" | sed -n 's/.*mode=\([^&]*\).*/\1/p')
        if [[ -n "$m" ]]; then
            settings_set "$SETTINGS_FILE" mode global "$m"
            led_clear_cache 2>/dev/null
            case "$m" in
                off) led_all_off_full 2>/dev/null ;;
                on)  led_all_on_full "$SETTINGS_FILE" 2>/dev/null ;;
            esac
            bash "${SERVER_DIR}/led_daemon.sh" once 2>/dev/null
        fi
        printf '{"ok":true,"mode":"%s"}' "$(settings_get "$SETTINGS_FILE" mode global smart)"
        ;;
    /remap)
        bash "${SERVER_DIR}/led_daemon.sh" remap 2>/dev/null
        disk_refresh_mapping "$SETTINGS_FILE" 2>/dev/null
        n=0
        for _ in "${!DISK_LED_MAP[@]}"; do n=$((n + 1)); done
        printf '{"ok":true,"message":"已重新检测 %s 块硬盘","disk_count":%s}' "$n" "$n"
        ;;
    /daemon/start)
        if [[ -x "${APP_ROOT}/cmd/main" ]]; then
            "${APP_ROOT}/cmd/main" start 2>/dev/null
        else
            bash "${SERVER_DIR}/led_daemon.sh" start 2>/dev/null
        fi
        d="stopped"
        [[ -f "${VAR_DIR}/led_daemon.pid" ]] && kill -0 "$(cat "${VAR_DIR}/led_daemon.pid")" 2>/dev/null && d="running"
        printf '{"ok":true,"daemon":"%s","message":"后台已启动"}' "$d"
        ;;
    /daemon/stop)
        if [[ -x "${APP_ROOT}/cmd/main" ]]; then
            "${APP_ROOT}/cmd/main" stop 2>/dev/null
        else
            bash "${SERVER_DIR}/led_daemon.sh" stop 2>/dev/null
        fi
        printf '{"ok":true,"daemon":"stopped","message":"后台已停止"}'
        ;;
    *)
        printf '{"ok":false,"error":"unknown","path":"%s"}' "$(json_str "$API_PATH")"
        ;;
esac
