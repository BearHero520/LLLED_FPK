#!/bin/bash
set -euo pipefail

APP_NAME="${APP_NAME:-App.Native.UGreenLED}"
APP_ROOT="${TRIM_APPDEST:-${APP_ROOT:-/var/apps/${APP_NAME}}}"
VAR_DIR="${TRIM_PKGVAR:-${VAR_DIR:-${APP_ROOT}/var}}"
SERVER_DIR="${SERVER_DIR:-$(cd "$(dirname "$0")" && pwd)}"
LIB_DIR="${SERVER_DIR}/lib"
SETTINGS_FILE="${SETTINGS_FILE:-${VAR_DIR}/settings.conf}"

source "${LIB_DIR}/app_paths.sh"
ugreen_resolve_paths
source "${LIB_DIR}/settings.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/hardware_profile.sh"
source "${LIB_DIR}/bios_control.sh"

case "${1:-}" in
    shutdown)
        enabled=$(settings_get "$SETTINGS_FILE" power_schedule enabled false)
        days=$(settings_get "$SETTINGS_FILE" power_schedule days "")
        wake_time=$(settings_get "$SETTINGS_FILE" power_schedule wake_time "")
        [[ "$enabled" == "true" ]] || exit 0
        bios_schedule_rearm "$days" "$wake_time" || {
            _bios_log_error "bios.power_schedule_rearm_failed" "定时关机前重设 RTC 开机失败，已取消关机" \
                "error=$BIOS_LAST_ERROR"
            exit 1
        }
        ugreen_log_audit "bios.power_schedule_shutdown" "已按用户计划执行安全关机" \
            "days=$days" "wake_time=$wake_time"
        exec /usr/bin/systemctl poweroff
        ;;
    *)
        echo "usage: $0 shutdown" >&2
        exit 64
        ;;
esac
