#!/bin/bash
APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-/var/apps/${APP_NAME}}"
VAR_DIR="${TRIM_PKGVAR:-${APP_ROOT}/var}"

SERVER_DIR=""
for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
    [[ -f "${d}/lib/logging.sh" ]] && SERVER_DIR="$d" && break
done
LOG_DIR="${VAR_DIR}/log"
UGREEN_LOG_COMPONENT="static"
UGREEN_LOG_FILE="${LOG_DIR}/app.log"
export LOG_DIR UGREEN_LOG_COMPONENT UGREEN_LOG_FILE
if [[ -n "$SERVER_DIR" && -f "${SERVER_DIR}/lib/logging.sh" ]] && \
    source "${SERVER_DIR}/lib/logging.sh" 2>/dev/null && \
    declare -F ugreen_log_make_request_id >/dev/null && \
    declare -F ugreen_log_warn >/dev/null && \
    declare -F ugreen_log_error >/dev/null; then
    :
else
    _ugreen_static_fallback_sanitize() {
        local value="${1:-}"
        value="${value//$'\r'/ }"
        value="${value//$'\n'/ }"
        value="${value//$'\t'/ }"
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        printf '%s' "${value:0:1024}"
    }
    _ugreen_static_fallback_emit() {
        local level="${1:-ERROR}" event="${2:-static.error}" message="${3:-}" item context=""
        shift 3 || true
        event="${event//[^a-zA-Z0-9_.:-]/_}"
        for item in "$@"; do context+=" $(_ugreen_static_fallback_sanitize "$item")"; done
        mkdir -p "$LOG_DIR" 2>/dev/null || return 0
        chmod 0750 "$LOG_DIR" 2>/dev/null || true
        printf '[%s] [%s] [static] [pid=%s] [request=%s] [event=%s] [source=index.cgi:fallback:0] msg="%s"%s\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo unknown-time)" "$level" "${BASHPID:-$$}" \
            "$(_ugreen_static_fallback_sanitize "${UGREEN_REQUEST_ID:-unassigned}")" "$event" \
            "$(_ugreen_static_fallback_sanitize "$message")" "$context" >> "$UGREEN_LOG_FILE" 2>/dev/null || true
        chmod 0640 "$UGREEN_LOG_FILE" 2>/dev/null || true
        return 0
    }
    ugreen_log_make_request_id() { printf 'static-%s-%s\n' "$(date +%s 2>/dev/null || echo 0)" "${BASHPID:-$$}"; }
    ugreen_log_warn() { _ugreen_static_fallback_emit WARN "$@"; }
    ugreen_log_error() { _ugreen_static_fallback_emit ERROR "$@"; }
fi
if [[ "${HTTP_X_REQUEST_ID:-}" =~ ^[A-Za-z0-9._:-]{8,64}$ ]]; then
    UGREEN_REQUEST_ID="$HTTP_X_REQUEST_ID"
else
    UGREEN_REQUEST_ID=$(ugreen_log_make_request_id)
fi
export UGREEN_REQUEST_ID

BASE_PATH=""
for d in "${APP_ROOT}/www" "${APP_ROOT}/target/www"; do
    if [[ -f "${d}/index.html" ]]; then
        BASE_PATH="$d"
        break
    fi
done
BASE_PATH="${BASE_PATH:-${APP_ROOT}/www}"

URI_NO_QUERY="${REQUEST_URI%%\?*}"
REL_PATH="/"
case "$URI_NO_QUERY" in
    *index.cgi*) REL_PATH="${URI_NO_QUERY#*index.cgi}" ;;
esac
[[ -z "$REL_PATH" || "$REL_PATH" == "/" ]] && REL_PATH="/index.html"
TARGET_FILE="${BASE_PATH}${REL_PATH}"
if echo "$TARGET_FILE" | grep -q '\.\.'; then
    ugreen_log_warn "static.invalid_path" "拒绝包含上级目录的静态资源请求" "path=$REL_PATH"
    echo "Status: 400 Bad Request"
    echo "Content-Type: text/plain; charset=utf-8"
    echo "X-Request-ID: $UGREEN_REQUEST_ID"
    echo ""
    echo "Bad Request"
    exit 0
fi
if [[ ! -f "$TARGET_FILE" ]]; then
    ugreen_log_warn "static.not_found" "静态资源不存在" "path=$REL_PATH"
    echo "Status: 404 Not Found"
    echo "Content-Type: text/plain; charset=utf-8"
    echo "X-Request-ID: $UGREEN_REQUEST_ID"
    echo ""
    echo "404 Not Found: ${REL_PATH}"
    exit 0
fi
if [[ ! -r "$TARGET_FILE" ]]; then
    ugreen_log_error "static.not_readable" "静态资源不可读" "path=$REL_PATH"
    echo "Status: 500 Internal Server Error"
    echo "Content-Type: text/plain; charset=utf-8"
    echo "X-Request-ID: $UGREEN_REQUEST_ID"
    echo ""
    echo "Resource is not readable"
    exit 0
fi
ext="${TARGET_FILE##*.}"
case "$ext" in
    html|htm) mime="text/html; charset=utf-8" ;;
    css) mime="text/css; charset=utf-8" ;;
    js) mime="application/javascript; charset=utf-8" ;;
    png) mime="image/png" ;;
    woff) mime="font/woff" ;;
    woff2) mime="font/woff2" ;;
    json) mime="application/json; charset=utf-8" ;;
    *) mime="application/octet-stream" ;;
esac
echo "Content-Type: $mime"
echo "X-Request-ID: $UGREEN_REQUEST_ID"
echo ""
if ! cat "$TARGET_FILE"; then
    ugreen_log_error "static.read_failed" "读取静态资源时发生错误" "path=$REL_PATH"
fi
