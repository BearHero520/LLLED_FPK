#!/bin/bash
# 简易 HTTP JSON API（默认端口 5088）

APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-${APP_ROOT:-/var/apps/${APP_NAME}}}"
VAR_DIR="${TRIM_PKGVAR:-${VAR_DIR:-${APP_ROOT}/var}}"
PORT="${PORT:-5088}"
LOG_FILE="${VAR_DIR}/log/api.log"

SERVER_DIR=""
for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
    [[ -f "${d}/led_daemon.sh" ]] && SERVER_DIR="$d" && break
done
SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"
LIB_DIR="${SERVER_DIR}/lib"
source "${LIB_DIR}/app_paths.sh"
ugreen_resolve_runtime || exit 1
PID_FILE="${RUNTIME_DIR}/http_api.pid"
LEGACY_PID_FILE="${VAR_DIR}/http_api.pid"
DAEMON_PID_FILE="${RUNTIME_DIR}/led_daemon.pid"
DISK_STATUS_FILE="${RUNTIME_DIR}/disk_status.tsv"
SETTINGS_FILE="${VAR_DIR}/settings.conf"
UGREEN_CLI=""
for c in "${SERVER_DIR}/bin/ugreen_leds_cli" "${APP_ROOT}/target/server/bin/ugreen_leds_cli" /usr/bin/ugreen_leds_cli; do
    [[ -x "$c" ]] && UGREEN_CLI="$c" && break
done
export TARGET="${APP_ROOT}"
export UGREEN_CLI LED_API_CACHE_DIR="${RUNTIME_DIR}/led_cache"

source "${LIB_DIR}/led_api.sh"
source "${LIB_DIR}/settings.sh"
source "${LIB_DIR}/disk_map.sh"

mkdir -p "${VAR_DIR}/log"

log_api() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    printf '%s' "$s"
}

respond() {
    local code="$1" body="$2"
    printf 'HTTP/1.1 %s\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
        "$code" "${#body}" "$body"
}

settings_to_json() {
    local f="$1" cur="" body="{"
    local first_sec=1
    [[ -f "$f" ]] || { echo "{}"; return; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            [[ $first_sec -eq 0 ]] && body+=","
            first_sec=0
            cur="${BASH_REMATCH[1]}"
            body+="\"$(json_str "$cur")\":{"
            continue
        fi
        if [[ "$line" =~ ^([^=]+)=(.*)$ && -n "$cur" ]]; then
            local k="${BASH_REMATCH[1]}" v="${BASH_REMATCH[2]}"
            k="${k// /}"; v="${v#"${v%%[![:space:]]*}"}"
            body+="\"$(json_str "$k")\":\"$(json_str "$v")\","
        fi
    done < "$f"
    body="${body%,}}"
    body="${body//,,/,}"
    body="${body%\{},}"
    echo "${body}}"
}

handle_request() {
    local method="$1" path="$2" query="$3" post_body="$4"
    settings_init "$SETTINGS_FILE"

    case "$path" in
        /api/status)
            local daemon="stopped" st=""
            if [[ -f "$DAEMON_PID_FILE" ]] && kill -0 "$(cat "$DAEMON_PID_FILE")" 2>/dev/null; then
                daemon="running"
            fi
            st=$(led_all_status 2>/dev/null || true)
            respond "200 OK" "{\"ok\":true,\"daemon\":\"$daemon\",\"led_status\":\"$(json_str "$st")\"}"
            ;;
        /api/mapping)
            disk_load_mapping_from_settings "$SETTINGS_FILE" 2>/dev/null || {
                disk_save_auto_mapping "$SETTINGS_FILE"
                disk_load_mapping_from_settings "$SETTINGS_FILE"
            }
            local items="" first=1
            for dev in "${!DISK_LED_MAP[@]}"; do
                local led="${DISK_LED_MAP[$dev]}"
                local state
                state="unknown"
                if [[ -f "$DISK_STATUS_FILE" ]]; then
                    while IFS='|' read -r status_dev status_led status_state _; do
                        if [[ "$status_dev" == "$dev" ]]; then
                            state="${status_state:-unknown}"
                            break
                        fi
                    done < "$DISK_STATUS_FILE"
                fi
                [[ $first -eq 0 ]] && items+=","
                first=0
                items+="{\"device\":\"$dev\",\"led\":\"$led\",\"state\":\"$state\"}"
            done
            respond "200 OK" "{\"ok\":true,\"mapping\":[$items]}"
            ;;
        /api/settings)
            if [[ "$method" == "GET" ]]; then
                respond "200 OK" "$(settings_to_json "$SETTINGS_FILE")"
            elif [[ "$method" == "POST" ]]; then
                # POST body: section|key|value 每行，或 JSON 简化：color.active=0 255 0
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    if [[ "$line" =~ ^([^|]+)\|([^|]+)\|(.+)$ ]]; then
                        settings_set "$SETTINGS_FILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
                    elif [[ "$line" =~ ^([^.]+)\.([^=]+)=(.+)$ ]]; then
                        settings_set "$SETTINGS_FILE" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
                    fi
                done <<< "$post_body"
                led_clear_cache
                respond "200 OK" '{"ok":true}'
            else
                respond "405 Method Not Allowed" '{"ok":false}'
            fi
            ;;
        /api/remap)
            DISK_LED_MAP=()
            disk_save_auto_mapping "$SETTINGS_FILE"
            respond "200 OK" '{"ok":true}'
            ;;
        /api/led/set)
            # ?led=disk1&r=255&g=0&b=0&brightness=64
            local led r g b br
            led=$(echo "$query" | sed -n 's/.*led=\([^&]*\).*/\1/p'); led="${led:-disk1}"
            r=$(echo "$query" | sed -n 's/.*r=\([^&]*\).*/\1/p'); r="${r:-255}"
            g=$(echo "$query" | sed -n 's/.*g=\([^&]*\).*/\1/p'); g="${g:-255}"
            b=$(echo "$query" | sed -n 's/.*b=\([^&]*\).*/\1/p'); b="${b:-255}"
            br=$(echo "$query" | sed -n 's/.*brightness=\([^&]*\).*/\1/p'); br="${br:-64}"
            led_set_color "$led" "$r" "$g" "$b" "$br"
            respond "200 OK" "{\"ok\":true,\"led\":\"$led\"}"
            ;;
        /api/led/off)
            local led
            led=$(echo "$query" | sed -n 's/.*led=\([^&]*\).*/\1/p')
            if [[ -z "$led" || "$led" == "all" ]]; then
                for s in $(led_list_disk_slots 2>/dev/null) power netdev; do
                    led_set_off "$s" 2>/dev/null
                done
            else
                led_set_off "$led"
            fi
            led_clear_cache
            respond "200 OK" '{"ok":true}'
            ;;
        /api/daemon/start)
            "${TARGET}/server/led_daemon.sh" start
            respond "200 OK" '{"ok":true}'
            ;;
        /api/daemon/stop)
            "${TARGET}/server/led_daemon.sh" stop
            respond "200 OK" '{"ok":true}'
            ;;
        *)
            respond "404 Not Found" '{"ok":false,"error":"not found"}'
            ;;
    esac
}

parse_and_handle() {
    local req method path query post_len post_body=""
    read -r req || return
    method="${req%% *}"
    path="${req#* }"; path="${path%% *}"
    query=""
    [[ "$path" == *"?"* ]] && { query="${path#*\?}"; path="${path%%\?*}"; }

    while read -r h; do
        h="${h//$'\r'/}"
        [[ -z "$h" ]] && break
        if [[ "$h" =~ ^[Cc]ontent-[Ll]ength:[[:space:]]*([0-9]+) ]]; then
            post_len="${BASH_REMATCH[1]}"
        fi
    done

    if [[ -n "$post_len" && "$post_len" -gt 0 ]]; then
        post_body=$(head -c "$post_len")
    fi

    handle_request "$method" "$path" "$query" "$post_body"
}

listen_loop() {
    log_api "API 监听 :$PORT"
    while true; do
        parse_and_handle < <(
            if command -v ncat >/dev/null 2>&1; then
                ncat -l "$PORT" --send-only 2>/dev/null
            elif command -v nc >/dev/null 2>&1; then
                nc -l -p "$PORT" -q 1 2>/dev/null
            elif command -v socat >/dev/null 2>&1; then
                socat -T 10 TCP-LISTEN:"$PORT",reuseaddr,fork STDIO 2>/dev/null
            else
                log_api "ERROR: 需要 nc/ncat/socat"
                sleep 5
                continue
            fi
        ) || true
    done
}

case "${1:-}" in
    start)
        if [[ -f "$LEGACY_PID_FILE" ]]; then
            kill "$(cat "$LEGACY_PID_FILE")" 2>/dev/null || true
            rm -f "$LEGACY_PID_FILE"
        fi
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            exit 0
        fi
        listen_loop &
        echo $! > "$PID_FILE"
        ;;
    stop)
        [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null
        [[ -f "$LEGACY_PID_FILE" ]] && kill "$(cat "$LEGACY_PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
        rm -f "$LEGACY_PID_FILE"
        ;;
    *)
        echo "用法: $0 {start|stop}"
        ;;
esac
