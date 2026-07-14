#!/bin/bash
# fnOS 安装后 server 可能在 $APP_ROOT/server 或 $APP_ROOT/target/server

ugreen_resolve_runtime() {
    APP_NAME="${APP_NAME:-App.Native.UGreenLED}"
    local primary="${UGREEN_RUNTIME_DIR:-${RUNTIME_DIR:-/run/${APP_NAME}}}"
    local fallback="${TMPDIR:-/tmp}/${APP_NAME}"

    if mkdir -p "$primary" 2>/dev/null; then
        RUNTIME_DIR="$primary"
    else
        mkdir -p "$fallback" 2>/dev/null || return 1
        RUNTIME_DIR="$fallback"
    fi
    chmod 0755 "$RUNTIME_DIR" 2>/dev/null || true
    export RUNTIME_DIR
}

ugreen_resolve_paths() {
    APP_NAME="${APP_NAME:-App.Native.UGreenLED}"
    APP_ROOT="${TRIM_APPDEST:-${APP_ROOT:-/var/apps/${APP_NAME}}}"
    VAR_DIR="${TRIM_PKGVAR:-${VAR_DIR:-${APP_ROOT}/var}}"

    SERVER_DIR=""
    for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
        if [[ -f "${d}/led_daemon.sh" ]]; then
            SERVER_DIR="$d"
            break
        fi
    done
    SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"

    WWW_DIR=""
    for d in "${APP_ROOT}/www" "${APP_ROOT}/target/www"; do
        if [[ -f "${d}/index.html" ]]; then
            WWW_DIR="$d"
            break
        fi
    done
    WWW_DIR="${WWW_DIR:-${APP_ROOT}/www}"

    UGREEN_CLI=""
    for c in \
        "${SERVER_DIR}/bin/ugreen_leds_cli" \
        "${APP_ROOT}/target/server/bin/ugreen_leds_cli" \
        /usr/bin/ugreen_leds_cli \
        /opt/ugreen-led-controller/ugreen_leds_cli; do
        if [[ -x "$c" ]]; then
            UGREEN_CLI="$c"
            break
        fi
    done

    LIB_DIR="${SERVER_DIR}/lib"
    ugreen_resolve_runtime || return 1
    export APP_NAME APP_ROOT VAR_DIR RUNTIME_DIR SERVER_DIR WWW_DIR UGREEN_CLI LIB_DIR
    export TARGET="${APP_ROOT}"
}
