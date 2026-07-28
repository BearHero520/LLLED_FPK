#!/bin/bash
# Independent read-only fan telemetry sampler. It never controls LEDs or writes PWM.

APP_NAME="App.Native.UGreenLED"
APP_ROOT="${TRIM_APPDEST:-${APP_ROOT:-/var/apps/${APP_NAME}}}"
VAR_DIR="${TRIM_PKGVAR:-${VAR_DIR:-${APP_ROOT}/var}}"
SERVER_DIR="${SERVER_DIR:-}"
if [[ -z "$SERVER_DIR" ]]; then
    for d in "${APP_ROOT}/server" "${APP_ROOT}/target/server"; do
        [[ -f "${d}/fan_telemetry_daemon.sh" ]] && SERVER_DIR="$d" && break
    done
fi
SERVER_DIR="${SERVER_DIR:-${APP_ROOT}/server}"
LIB_DIR="${SERVER_DIR}/lib"
LOG_DIR="${VAR_DIR}/log"
UGREEN_LOG_COMPONENT="fan-telemetry"
export APP_NAME APP_ROOT VAR_DIR SERVER_DIR LIB_DIR LOG_DIR UGREEN_LOG_COMPONENT TARGET="${APP_ROOT}"

source "${LIB_DIR}/app_paths.sh" 2>/dev/null && ugreen_resolve_runtime || exit 1
SETTINGS_FILE="${VAR_DIR}/settings.conf"
for library in logging settings hardware_profile bios_control fan_telemetry; do
    source "${LIB_DIR}/${library}.sh" 2>/dev/null || exit 1
done
settings_init "$SETTINGS_FILE" >/dev/null 2>&1 || true
ugreen_log_configure_from_settings "$SETTINGS_FILE" 2>/dev/null || true

PID_FILE="${RUNTIME_DIR}/fan-telemetry.pid"
INTERVAL_SECONDS="${FAN_TELEMETRY_INTERVAL_SECONDS:-10}"
[[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || INTERVAL_SECONDS=10
(( INTERVAL_SECONDS < 10 )) && INTERVAL_SECONDS=10

run_sampler() {
    trap 'rm -f "$PID_FILE"; exit 0' INT TERM EXIT
    while true; do
        fan_telemetry_capture >/dev/null 2>&1 || true
        sleep "$INTERVAL_SECONDS"
    done
}

start_sampler() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        return 0
    fi
    rm -f "$PID_FILE"
    nohup /bin/bash "$0" run >"${LOG_DIR}/fan-telemetry.log" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 0.05
    kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

stop_sampler() {
    local pid=""
    [[ -f "$PID_FILE" ]] && pid=$(cat "$PID_FILE" 2>/dev/null || true)
    [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
}

case "${1:-}" in
    start) start_sampler ;;
    stop) stop_sampler ;;
    status) [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null ;;
    run) run_sampler ;;
    *) echo "Usage: $0 {start|stop|status|run}" >&2; exit 1 ;;
esac
