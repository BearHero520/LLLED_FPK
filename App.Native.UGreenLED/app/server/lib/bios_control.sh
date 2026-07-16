#!/bin/bash
# BIOS/Super I/O control is provided by the bundled UGREEN-NAS-Hardware
# ugreenctl CLI.  Keep this file as the app-facing adapter: it preserves the
# HTTP API, while the upstream project owns
# the model plugins, register maps, DMI matching and hardware safeguards.

BIOS_UGREENCTL="${BIOS_UGREENCTL:-}"
BIOS_UGREENCTL_PLUGIN_DIR="${BIOS_UGREENCTL_PLUGIN_DIR:-}"
BIOS_IT8613_ID=34323 # 0x8613; verified by the upstream model plugin.

BIOS_LAST_ERROR=""
BIOS_SUPPORTED=false
BIOS_AVAILABLE=false
BIOS_BACKEND="unavailable"
BIOS_MODEL="unknown"
BIOS_EXPERIMENTAL=false
BIOS_MIN_PWM=40
BIOS_FAN_WRITE_TARGET="sys"
BIOS_PRODUCT_NAME=""
BIOS_CHIP_ID=""
BIOS_REVISION=0
BIOS_CPU_PWM=-1
BIOS_SYS_PWM=-1
BIOS_SYS2_PWM=-1
BIOS_CPU_RPM=0
BIOS_SYS_RPM=0
BIOS_SYS2_RPM=0
BIOS_CPU_MANUAL=false
BIOS_SYS_MANUAL=false
BIOS_SYS2_MANUAL=false
BIOS_STARTUP_POLICY="unknown"

bios_detected_profile() {
    local product
    product=$(hardware_detected_product_name 2>/dev/null || true)
    case "${product^^}" in
        "DXP480T PLUS"|"UGREEN DXP480T PLUS") echo "dxp480t_plus" ;;
        "DXP4800 PLUS"|"UGREEN DXP4800 PLUS") echo "dxp4800_plus" ;;
        "DXP4800 PRO"|"UGREEN DXP4800 PRO") echo "dxp4800_pro" ;;
        *) echo "unknown" ;;
    esac
}

bios_supported_model() {
    case "$(bios_detected_profile)" in
        dxp4800_plus|dxp4800_pro|dxp480t_plus) return 0 ;;
        *) return 1 ;;
    esac
}

bios_ugreenctl_binary() {
    local candidate
    for candidate in \
        "$BIOS_UGREENCTL" \
        "${SERVER_DIR:-}/bin/ugreenctl" \
        "${APP_ROOT:-}/target/server/bin/ugreenctl"; do
        [[ -n "$candidate" && -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

bios_ugreenctl_plugin_dir() {
    local candidate
    for candidate in \
        "$BIOS_UGREENCTL_PLUGIN_DIR" \
        "${SERVER_DIR:-}/lib/ugreenctl/models" \
        "${APP_ROOT:-}/target/server/lib/ugreenctl/models"; do
        [[ -n "$candidate" && -r "$candidate/dxp4800plus.so" && -r "$candidate/dxp480tplus.so" ]] && {
            printf '%s\n' "$candidate"
            return 0
        }
    done
    return 1
}

bios_backend() {
    bios_ugreenctl_binary >/dev/null && bios_ugreenctl_plugin_dir >/dev/null && echo "ugreenctl" || echo "unavailable"
}

bios_cli() {
    local binary plugin_dir
    binary=$(bios_ugreenctl_binary) || {
        BIOS_LAST_ERROR="未找到内置 UGREEN-NAS-Hardware 控制程序"
        return 127
    }
    plugin_dir=$(bios_ugreenctl_plugin_dir) || {
        BIOS_LAST_ERROR="未找到内置 UGREEN-NAS-Hardware 机型插件"
        return 127
    }
    "$binary" --plugin-dir "$plugin_dir" "$@"
}

bios_set_error_from_output() {
    local output="$1" fallback="$2" message
    message=$(printf '%s\n' "$output" | sed -n 's/^error:[[:space:]]*//p' | head -n 1)
    [[ -n "$message" ]] || message=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)
    BIOS_LAST_ERROR="${message:-$fallback}"
}

bios_line_value() {
    local line="$1" key="$2"
    sed -n "s/.*[[:space:]]${key}=\\([^[:space:]]*\\).*/\\1/p" <<< "$line"
}

bios_parse_fan_line() {
    local id="$1" line="$2" pwm mode rpm
    pwm=$(bios_line_value "$line" "pwm")
    mode=$(bios_line_value "$line" "mode")
    rpm=$(bios_line_value "$line" "rpm")
    [[ "$rpm" =~ ^[0-9]+$ ]] || rpm=0
    [[ "$pwm" =~ ^[0-9]+$ ]] || pwm=-1

    case "$id" in
        cpu)
            BIOS_CPU_PWM="$pwm"
            BIOS_CPU_RPM="$rpm"
            [[ "$mode" == "manual" ]] && BIOS_CPU_MANUAL=true || BIOS_CPU_MANUAL=false
            ;;
        sys|sys1)
            BIOS_SYS_PWM="$pwm"
            BIOS_SYS_RPM="$rpm"
            [[ "$mode" == "manual" ]] && BIOS_SYS_MANUAL=true || BIOS_SYS_MANUAL=false
            ;;
        sys2)
            BIOS_SYS2_PWM="$pwm"
            BIOS_SYS2_RPM="$rpm"
            [[ "$mode" == "manual" ]] && BIOS_SYS2_MANUAL=true || BIOS_SYS2_MANUAL=false
            ;;
    esac
}

bios_read_cli_status() {
    local output line startup
    if ! output=$(bios_cli info 2>&1); then
        bios_set_error_from_output "$output" "读取 UGREEN-NAS-Hardware 控制器状态失败"
        return 1
    fi

    BIOS_CHIP_ID=$BIOS_IT8613_ID
    BIOS_REVISION=0
    while IFS= read -r line; do
        case "$line" in
            startup:\ *)
                startup=${line#startup: }
                [[ "$startup" == "restore" ]] && startup=last
                case "$startup" in on|off|last) BIOS_STARTUP_POLICY="$startup" ;; esac
                ;;
            fan\ cpu:\ *) bios_parse_fan_line cpu "${line#fan }" ;;
            fan\ sys:\ *) bios_parse_fan_line sys "${line#fan }" ;;
            fan\ sys1:\ *) bios_parse_fan_line sys1 "${line#fan }" ;;
            fan\ sys2:\ *) bios_parse_fan_line sys2 "${line#fan }" ;;
        esac
    done <<< "$output"
}

bios_read_status() {
    BIOS_LAST_ERROR=""
    BIOS_SUPPORTED=false
    BIOS_AVAILABLE=false
    BIOS_BACKEND="unavailable"
    BIOS_PRODUCT_NAME=$(hardware_detected_product_name 2>/dev/null || true)
    BIOS_MODEL=$(bios_detected_profile)
    BIOS_EXPERIMENTAL=false
    BIOS_MIN_PWM=40
    BIOS_FAN_WRITE_TARGET="sys"
    BIOS_CHIP_ID=""
    BIOS_REVISION=0
    BIOS_CPU_PWM=-1
    BIOS_SYS_PWM=-1
    BIOS_SYS2_PWM=-1
    BIOS_CPU_RPM=0
    BIOS_SYS_RPM=0
    BIOS_SYS2_RPM=0
    BIOS_CPU_MANUAL=false
    BIOS_SYS_MANUAL=false
    BIOS_SYS2_MANUAL=false
    BIOS_STARTUP_POLICY="unknown"

    if ! bios_supported_model; then
        BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro 与 DXP480T Plus"
        return 0
    fi
    BIOS_SUPPORTED=true
    if [[ "$BIOS_MODEL" == "dxp480t_plus" ]]; then
        BIOS_FAN_WRITE_TARGET="all"
    fi
    BIOS_BACKEND=$(bios_backend)
    if [[ "$BIOS_BACKEND" != "ugreenctl" ]]; then
        BIOS_LAST_ERROR="内置 UGREEN-NAS-Hardware 控制程序或机型插件不可用"
        return 1
    fi
    bios_read_cli_status || return 1
    BIOS_AVAILABLE=true
}

bios_set_fan() {
    local channel="$1" pwm="$2" model output
    local -a args=(--apply)
    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro 与 DXP480T Plus"; return 1; }
    [[ "$pwm" =~ ^[0-9]+$ ]] && (( pwm >= 40 && pwm <= 255 )) || {
        BIOS_LAST_ERROR="PWM 必须在 40 到 255 之间"
        return 1
    }
    model=$(bios_detected_profile)
    if [[ "$model" == "dxp480t_plus" ]]; then
        [[ "$channel" == "cpu" || "$channel" == "all" ]] || {
            BIOS_LAST_ERROR="DXP480T Plus 仅支持 CPU 或全部风扇写入"
            return 1
        }
    else
        [[ "$channel" == "cpu" || "$channel" == "sys" ]] || {
            BIOS_LAST_ERROR="未知风扇通道"
            return 1
        }
    fi
    if ! output=$(bios_cli "${args[@]}" fan set "$channel" "$pwm" 2>&1); then
        bios_set_error_from_output "$output" "设置风扇 PWM 失败"
        return 1
    fi
}

bios_set_fan_mode() {
    local channel="$1" mode="$2" model output
    local -a args=(--apply)
    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro 与 DXP480T Plus"; return 1; }
    [[ "$mode" == "auto" || "$mode" == "manual" ]] || {
        BIOS_LAST_ERROR="未知风扇控制模式"
        return 1
    }
    model=$(bios_detected_profile)
    if [[ "$model" == "dxp480t_plus" ]]; then
        [[ "$channel" == "cpu" || "$channel" == "all" ]] || {
            BIOS_LAST_ERROR="DXP480T Plus 仅支持 CPU 或全部风扇模式切换"
            return 1
        }
    else
        [[ "$channel" == "cpu" || "$channel" == "sys" ]] || {
            BIOS_LAST_ERROR="未知风扇通道"
            return 1
        }
    fi
    if ! output=$(bios_cli "${args[@]}" fan mode "$channel" "$mode" 2>&1); then
        bios_set_error_from_output "$output" "设置风扇控制模式失败"
        return 1
    fi
}

bios_set_startup() {
    local policy="$1" upstream_policy output
    local -a args=(--apply)
    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro 与 DXP480T Plus"; return 1; }
    case "$policy" in
        on|off) upstream_policy="$policy" ;;
        last) upstream_policy="restore" ;;
        *) BIOS_LAST_ERROR="未知来电启动策略"; return 1 ;;
    esac
    if ! output=$(bios_cli "${args[@]}" power startup set "$upstream_policy" 2>&1); then
        bios_set_error_from_output "$output" "设置来电启动策略失败"
        return 1
    fi
}
