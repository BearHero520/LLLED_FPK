#!/bin/bash
# Read-only hardware diagnostics for UGREEN NAS compatibility work.
# This script never loads/unloads modules and never issues state-changing hardware writes.

set -u
set -o pipefail
umask 077
shopt -s nullglob

COLLECTOR_VERSION="1"
APP_NAME="App.Native.UGreenLED"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)

SYS_ROOT="${UGREEN_DIAG_SYS_ROOT:-/sys}"
PROC_ROOT="${UGREEN_DIAG_PROC_ROOT:-/proc}"
DEV_ROOT="${UGREEN_DIAG_DEV_ROOT:-/dev}"
ETC_ROOT="${UGREEN_DIAG_ETC_ROOT:-/etc}"
USR_SRC_ROOT="${UGREEN_DIAG_USR_SRC_ROOT:-/usr/src}"
TMP_ROOT="${TMPDIR:-/tmp}"
I2C_PROBE_MODE="${UGREEN_DIAG_I2C_PROBE:-auto}"
OUTPUT_MODE="file"
OUTPUT_PATH=""
OUTPUT_EXPLICIT=false

PRODUCT_NAME=""
IT87_LOADED=false
IT87_BOUND=false
VENDOR_IT86_ACTIVE=false
I2C_PROBE_ENABLED=false
I2C_ADAPTER_COUNT=0
I2C_TARGET_DEVICE_COUNT=0
IT87_BOUND_PATHS=()

usage() {
    cat <<'EOF'
Usage: nas_hardware_collect.sh [options]

Options:
  --stdout          Write the report to standard output.
  --output PATH     Create the report at PATH; refuses to overwrite existing files.
  --i2c-probe       Run targeted, read-only 0x31/0x26 register reads.
  --no-i2c-probe    Do not access I2C devices.
  -h, --help        Show this help.

Without options, a mode-0600 report is created under /tmp. In auto mode, targeted
I2C reads are attempted only on DXP480T-family systems. The collector never uses
i2cget -f, i2cset, modprobe, rmmod, or state-changing control commands.
EOF
}

sanitize_value() {
    local value="${1:-}"
    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//$'\t'/ }"
    printf '%s' "$value"
}

read_value() {
    local path="$1" value
    if [[ ! -r "$path" ]]; then
        printf '<unavailable>'
        return 0
    fi
    value=$(head -c 512 "$path" 2>&1)
    sanitize_value "$value"
}

resolved_link() {
    local path="$1" value
    value=$(readlink -f "$path" 2>/dev/null || readlink "$path" 2>/dev/null || true)
    sanitize_value "$value"
}

sha256_file() {
    local path="$1"
    if [[ ! -r "$path" ]]; then
        printf '<unavailable>'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" 2>/dev/null | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$path" 2>/dev/null | awk '{print $NF}'
    else
        printf '<sha256-tool-missing>'
    fi
}

section() {
    printf '\n===== %s =====\n' "$1"
}

run_command() {
    local label="$1" output rc arg
    shift
    printf '\n[%s]\ncommand=' "$label"
    for arg in "$@"; do printf '%q ' "$arg"; done
    printf '\n'
    if [[ $# -eq 0 ]] || ! command -v "$1" >/dev/null 2>&1; then
        printf 'result=<command unavailable>\nexit_code=127\n'
        return 0
    fi
    output=$("$@" 2>&1)
    rc=$?
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output"
    else
        printf '<no output>\n'
    fi
    printf 'exit_code=%d\n' "$rc"
    return 0
}

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 "$@"
    else
        "$@"
    fi
}

detect_state() {
    local h module_link module_target entry adapters target_devices

    PRODUCT_NAME=$(read_value "$SYS_ROOT/class/dmi/id/product_name")
    [[ "$PRODUCT_NAME" == "<unavailable>" ]] && PRODUCT_NAME="unknown"

    if [[ -d "$SYS_ROOT/module/it87" ]] || \
       { [[ -r "$PROC_ROOT/modules" ]] && grep -q '^it87[[:space:]]' "$PROC_ROOT/modules" 2>/dev/null; }; then
        IT87_LOADED=true
    fi

    for h in "$SYS_ROOT"/class/hwmon/hwmon*; do
        module_link="$h/device/driver/module"
        module_target=$(resolved_link "$module_link")
        if [[ "${module_target##*/}" == "it87" ]]; then
            IT87_BOUND=true
            IT87_BOUND_PATHS+=("$h")
        fi
    done
    for entry in "$SYS_ROOT"/bus/platform/drivers/it87/it87.*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        IT87_BOUND=true
        IT87_BOUND_PATHS+=("$entry")
    done

    if [[ -d "$PROC_ROOT/it86" || -d "$SYS_ROOT/module/ug_it86x_sio" || \
          -d "$SYS_ROOT/module/ug_it86x_cpufan" ]]; then
        VENDOR_IT86_ACTIVE=true
    fi

    adapters=("$SYS_ROOT"/class/i2c-adapter/i2c-*)
    I2C_ADAPTER_COUNT=${#adapters[@]}
    target_devices=("$SYS_ROOT"/bus/i2c/devices/*-0031 "$SYS_ROOT"/bus/i2c/devices/*-0026)
    I2C_TARGET_DEVICE_COUNT=${#target_devices[@]}

    case "${I2C_PROBE_MODE,,}" in
        on|yes|true|1) I2C_PROBE_ENABLED=true ;;
        off|no|false|0) I2C_PROBE_ENABLED=false ;;
        *)
            [[ "$PRODUCT_NAME" == *DXP480T* ]] && I2C_PROBE_ENABLED=true || I2C_PROBE_ENABLED=false
            ;;
    esac
}

collect_summary() {
    local bound_paths="none"
    if (( ${#IT87_BOUND_PATHS[@]} > 0 )); then
        bound_paths=$(IFS=,; printf '%s' "${IT87_BOUND_PATHS[*]}")
    fi
    section "summary"
    printf 'collector_version=%s\n' "$COLLECTOR_VERSION"
    printf 'read_only=true\n'
    printf 'product_name=%s\n' "$PRODUCT_NAME"
    printf 'kernel=%s\n' "$(uname -r 2>/dev/null || printf unknown)"
    printf 'uid=%s\n' "$(id -u 2>/dev/null || printf unknown)"
    printf 'it87_loaded=%s\n' "$IT87_LOADED"
    printf 'it87_bound=%s\n' "$IT87_BOUND"
    printf 'it87_bound_paths=%s\n' "$bound_paths"
    printf 'vendor_it86_active=%s\n' "$VENDOR_IT86_ACTIVE"
    printf 'i2c_adapter_count=%s\n' "$I2C_ADAPTER_COUNT"
    printf 'i2c_target_device_count=%s\n' "$I2C_TARGET_DEVICE_COUNT"
    printf 'targeted_i2c_probe=%s\n' "$I2C_PROBE_ENABLED"
}

collect_system() {
    local key
    section "system"
    printf 'collected_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf unknown)"
    run_command "uname" uname -a
    if [[ -r "$ETC_ROOT/os-release" ]]; then
        printf '\n[os-release]\n'
        head -c 8192 "$ETC_ROOT/os-release" 2>&1
        printf '\n'
    else
        printf '\n[os-release]\n<unavailable>\n'
    fi
    printf '\n[dmi-safe-fields]\n'
    for key in sys_vendor product_name product_version board_vendor board_name board_version \
               bios_vendor bios_version bios_date; do
        printf '%s=%s\n' "$key" "$(read_value "$SYS_ROOT/class/dmi/id/$key")"
    done
    printf 'omitted_fields=product_serial,product_uuid,board_serial,chassis_serial\n'
}

collect_module_details() {
    local module_path="" parameter holder source_dir source_file output rc
    section "it87-module-and-binding"

    if command -v lsmod >/dev/null 2>&1; then
        printf '[related-lsmod]\n'
        output=$(lsmod 2>&1)
        rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "$output" | grep -Ei '^(it87|ug_it86|hwmon_vid|wmi|i2c_|leds_mcu)' || printf '<no related modules>\n'
        else
            printf '%s\nexit_code=%d\n' "$output" "$rc"
        fi
    fi
    if [[ -r "$PROC_ROOT/modules" ]]; then
        printf '\n[related-proc-modules]\n'
        grep -Ei '^(it87|ug_it86|hwmon_vid|wmi|i2c_|leds_mcu)' "$PROC_ROOT/modules" 2>/dev/null || \
            printf '<no related modules>\n'
    fi

    run_command "modinfo-it87" modinfo it87
    if command -v modinfo >/dev/null 2>&1; then
        module_path=$(modinfo -n it87 2>/dev/null || true)
    fi
    printf '\n[it87-binary]\npath=%s\nsha256=%s\n' \
        "${module_path:-<unavailable>}" "$(sha256_file "$module_path")"

    printf '\n[it87-parameters]\n'
    if [[ -d "$SYS_ROOT/module/it87/parameters" ]]; then
        for parameter in "$SYS_ROOT/module/it87/parameters/"*; do
            printf '%s=%s\n' "${parameter##*/}" "$(read_value "$parameter")"
        done
    else
        printf '<unavailable>\n'
    fi

    printf '\n[it87-holders]\n'
    if [[ -d "$SYS_ROOT/module/it87/holders" ]]; then
        for holder in "$SYS_ROOT/module/it87/holders/"*; do
            printf '%s -> %s\n' "${holder##*/}" "$(resolved_link "$holder")"
        done
    else
        printf '<unavailable>\n'
    fi

    printf '\n[it87-platform-driver]\n'
    if [[ -d "$SYS_ROOT/bus/platform/drivers/it87" ]]; then
        for holder in "$SYS_ROOT/bus/platform/drivers/it87/"*; do
            printf '%s type=%s target=%s\n' "${holder##*/}" \
                "$([[ -L "$holder" ]] && printf symlink || printf node)" "$(resolved_link "$holder")"
        done
    else
        printf '<unavailable>\n'
    fi

    printf '\n[ioports-relevant]\n'
    if [[ -r "$PROC_ROOT/ioports" ]]; then
        grep -iE 'it87|it86|0a3[0-9]|0a35|0a36|super.?io|hwmon' "$PROC_ROOT/ioports" 2>/dev/null || \
            printf '<no matching I/O resources>\n'
    else
        printf '<unavailable>\n'
    fi

    printf '\n[vendor-proc-it86]\n'
    if [[ -d "$PROC_ROOT/it86" ]]; then
        ls -la "$PROC_ROOT/it86" 2>&1
    else
        printf '<not present>\n'
    fi

    run_command "dkms-status-it87" dkms status -m it87
    printf '\n[it87-dkms-source]\n'
    source_dir=""
    for source_dir in "$USR_SRC_ROOT"/it87*; do
        [[ -d "$source_dir" ]] || continue
        printf 'directory=%s\n' "$source_dir"
        if [[ -r "$source_dir/dkms.conf" ]]; then
            grep -E '^(PACKAGE_NAME|PACKAGE_VERSION|BUILT_MODULE_NAME|DEST_MODULE_LOCATION)' \
                "$source_dir/dkms.conf" 2>/dev/null || true
        fi
        for source_file in "$source_dir/it87.c" "$source_dir/src/it87.c"; do
            [[ -r "$source_file" ]] || continue
            printf 'source=%s sha256=%s\n' "$source_file" "$(sha256_file "$source_file")"
        done
    done
    [[ -n "$source_dir" ]] || printf '<not found>\n'
}

collect_hwmon() {
    local h name module device node base mode value
    section "hwmon-values"
    for h in "$SYS_ROOT"/class/hwmon/hwmon*; do
        name=$(read_value "$h/name")
        module=$(resolved_link "$h/device/driver/module")
        device=$(resolved_link "$h/device")
        printf '\npath=%s name=%s module=%s device=%s\n' "$h" "$name" "${module:-<none>}" "${device:-<none>}"
        for node in "$h"/fan[0-9]* "$h"/pwm[0-9]*; do
            [[ -f "$node" ]] || continue
            base=${node##*/}
            case "$base" in
                fan[0-9]*_input|fan[0-9]*_label|pwm[0-9]|pwm[0-9][0-9]|pwm[0-9]_enable|pwm[0-9][0-9]_enable|pwm[0-9]_freq|pwm[0-9][0-9]_freq|pwm[0-9]_auto_*|pwm[0-9][0-9]_auto_*) ;;
                *) continue ;;
            esac
            mode=$(stat -Lc '%a' "$node" 2>/dev/null || printf unknown)
            value=$(read_value "$node")
            printf 'node=%s mode=%s value=%s\n' "$base" "$mode" "$value"
        done
    done
}

collect_i2c() {
    local output rc adapter dev_path name driver module modalias dev bus address reg
    section "i2c-and-led"

    if command -v lsmod >/dev/null 2>&1; then
        printf '[i2c-led-modules]\n'
        output=$(lsmod 2>&1)
        rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "$output" | grep -Ei '^(i2c_|leds_mcu|led_ugreen|ugreen_leds)' || printf '<no related modules>\n'
        else
            printf '%s\nexit_code=%d\n' "$output" "$rc"
        fi
    fi

    run_command "modinfo-i2c-i801" modinfo i2c_i801
    run_command "modinfo-i2c-dev" modinfo i2c_dev
    run_command "i2cdetect-list" i2cdetect -l

    printf '\n[i2c-device-nodes]\n'
    if (( I2C_ADAPTER_COUNT == 0 )); then
        printf '<no sysfs I2C adapters>\n'
    fi
    for dev in "$DEV_ROOT"/i2c-*; do
        ls -l "$dev" 2>&1
    done

    printf '\n[i2c-adapters]\n'
    for adapter in "$SYS_ROOT"/class/i2c-adapter/i2c-*; do
        printf 'adapter=%s name=%s device=%s driver=%s module=%s\n' \
            "${adapter##*/}" "$(read_value "$adapter/name")" "$(resolved_link "$adapter/device")" \
            "$(resolved_link "$adapter/device/driver")" "$(resolved_link "$adapter/device/driver/module")"
    done

    printf '\n[target-i2c-devices]\n'
    if (( I2C_TARGET_DEVICE_COUNT == 0 )); then
        printf '<no 0x31/0x26 sysfs devices>\n'
    fi
    for dev_path in "$SYS_ROOT"/bus/i2c/devices/*-0031 "$SYS_ROOT"/bus/i2c/devices/*-0026; do
        [[ -e "$dev_path" || -L "$dev_path" ]] || continue
        name=$(read_value "$dev_path/name")
        driver=$(resolved_link "$dev_path/driver")
        module=$(resolved_link "$dev_path/driver/module")
        modalias=$(read_value "$dev_path/modalias")
        printf 'device=%s name=%s modalias=%s driver=%s module=%s\n' \
            "$dev_path" "$name" "$modalias" "${driver:-<none>}" "${module:-<none>}"
    done

    printf '\n[pci-smbus]\n'
    if command -v lspci >/dev/null 2>&1; then
        output=$(lspci -nnk 2>&1)
        rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "$output" | grep -iA5 -B1 'SMBus' || printf '<no SMBus PCI function reported>\n'
        else
            printf '%s\nexit_code=%d\n' "$output" "$rc"
        fi
    else
        printf '<lspci unavailable>\n'
    fi

    printf '\n[kernel-messages-relevant]\n'
    if command -v dmesg >/dev/null 2>&1; then
        output=$(dmesg 2>&1)
        rc=$?
        if (( rc == 0 )); then
            printf '%s\n' "$output" | grep -iE 'i2c|smbus|i801|it87|it8613|n76e003' | tail -n 200 || \
                printf '<no relevant kernel messages>\n'
        else
            printf '%s\nexit_code=%d\n' "$output" "$rc"
        fi
    else
        printf '<dmesg unavailable>\n'
    fi

    printf '\n[targeted-i2c-read-probes]\n'
    if ! $I2C_PROBE_ENABLED; then
        printf '<disabled>\n'
    elif ! command -v i2cget >/dev/null 2>&1; then
        printf '<i2cget unavailable>\n'
    else
        dev_path=""
        for dev in "$DEV_ROOT"/i2c-*; do
            [[ -e "$dev" ]] || continue
            dev_path="$dev"
            bus=${dev##*-}
            [[ "$bus" =~ ^[0-9]+$ ]] || continue
            for address in 0x31 0x26; do
                for reg in 0x5a 0x5b 0x5d; do
                    output=$(run_with_timeout i2cget -y "$bus" "$address" "$reg" b 2>&1)
                    rc=$?
                    output=$(sanitize_value "$output")
                    [[ -n "$output" ]] || output="<empty>"
                    printf 'bus=i2c-%s address=%s register=%s exit_code=%d output=%s\n' \
                        "$bus" "$address" "$reg" "$rc" "$output"
                done
            done
        done
        [[ -n "$dev_path" ]] || printf '<no /dev/i2c-* nodes to probe>\n'
    fi

    printf '\n[led-class]\n'
    if [[ -d "$SYS_ROOT/class/leds" ]]; then
        for dev_path in "$SYS_ROOT"/class/leds/*; do
            printf 'led=%s device=%s driver=%s module=%s\n' "${dev_path##*/}" \
                "$(resolved_link "$dev_path/device")" "$(resolved_link "$dev_path/device/driver")" \
                "$(resolved_link "$dev_path/device/driver/module")"
        done
    else
        printf '<unavailable>\n'
    fi
}

collect_controller() {
    local controller="" candidate output rc
    section "bundled-controller-read"
    if [[ -n "${UGREEN_DIAG_UGREENCTL:-}" ]]; then
        controller="$UGREEN_DIAG_UGREENCTL"
    else
        for candidate in \
            "$SCRIPT_DIR/bin/ugreenctl" \
            "${TRIM_APPDEST:-/var/apps/$APP_NAME}/server/bin/ugreenctl" \
            "${TRIM_APPDEST:-/var/apps/$APP_NAME}/target/server/bin/ugreenctl" \
            /usr/bin/ugreenctl; do
            if [[ -x "$candidate" ]]; then
                controller="$candidate"
                break
            fi
        done
    fi
    if [[ -z "$controller" || ! -x "$controller" ]]; then
        printf 'path=<unavailable>\n'
        return 0
    fi
    printf 'path=%s\nsha256=%s\n' "$controller" "$(sha256_file "$controller")"
    output=$(run_with_timeout "$controller" info 2>&1)
    rc=$?
    printf 'command=info\nexit_code=%d\n%s\n' "$rc" "${output:-<no output>}"
}

collect_report() {
    detect_state
    collect_summary
    collect_system
    collect_module_details
    collect_hwmon
    collect_i2c
    collect_controller
    section "privacy-and-safety"
    printf 'no_module_state_changes=true\n'
    printf 'no_pwm_or_policy_writes=true\n'
    printf 'no_i2c_data_writes=true\n'
    printf 'no_force_i2c_access=true\n'
    printf 'network_addresses_collected=false\n'
    printf 'hardware_serials_collected=false\n'
    return 0
}

create_explicit_output() {
    local parent
    [[ -n "$OUTPUT_PATH" ]] || return 1
    parent=${OUTPUT_PATH%/*}
    [[ "$parent" == "$OUTPUT_PATH" ]] && parent="."
    if [[ ! -d "$parent" || -e "$OUTPUT_PATH" || -L "$OUTPUT_PATH" ]]; then
        printf 'Refusing output path (parent missing or file already exists): %s\n' "$OUTPUT_PATH" >&2
        return 1
    fi
    (set -o noclobber; : > "$OUTPUT_PATH") 2>/dev/null || return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stdout)
            OUTPUT_MODE="stdout"
            ;;
        --output)
            [[ $# -ge 2 ]] || { printf '%s\n' '--output requires a path' >&2; exit 2; }
            OUTPUT_MODE="file"
            OUTPUT_PATH="$2"
            OUTPUT_EXPLICIT=true
            shift
            ;;
        --i2c-probe)
            I2C_PROBE_MODE="on"
            ;;
        --no-i2c-probe)
            I2C_PROBE_MODE="off"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "$OUTPUT_MODE" == "stdout" ]]; then
    collect_report
    exit 0
fi

if $OUTPUT_EXPLICIT; then
    create_explicit_output || exit 1
else
    if command -v mktemp >/dev/null 2>&1; then
        OUTPUT_PATH=$(mktemp "$TMP_ROOT/ugreen-led-hardware.XXXXXX") || exit 1
    else
        OUTPUT_PATH="$TMP_ROOT/ugreen-led-hardware.$$.txt"
        create_explicit_output || exit 1
    fi
fi

if ! collect_report > "$OUTPUT_PATH" 2>&1; then
    printf 'Hardware diagnostics failed; partial output: %s\n' "$OUTPUT_PATH" >&2
    exit 1
fi
chmod 0600 "$OUTPUT_PATH" 2>/dev/null || true
printf 'NAS 硬件诊断采集完成：%s\n' "$OUTPUT_PATH"
