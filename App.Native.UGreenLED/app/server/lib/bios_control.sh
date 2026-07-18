#!/bin/bash
# BIOS/Super I/O control is provided by the bundled UGREEN-NAS-Hardware
# ugreenctl CLI.  Keep this file as the app-facing adapter: it preserves the
# HTTP API, while the upstream project owns
# the model plugins, register maps, DMI matching and hardware safeguards.

BIOS_UGREENCTL="${BIOS_UGREENCTL:-}"
BIOS_UGREENCTL_PLUGIN_DIR="${BIOS_UGREENCTL_PLUGIN_DIR:-}"
BIOS_IT8613_ID=34323 # 0x8613; verified by the upstream model plugin.

BIOS_LAST_ERROR=""
BIOS_FAN_ERROR=""
BIOS_STARTUP_ERROR=""
BIOS_SUPPORTED=false
BIOS_AVAILABLE=false
BIOS_STARTUP_AVAILABLE=false
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
BIOS_CPU_FAN_PRESENT=true
BIOS_FAN_MODE_WRITABLE=false
BIOS_PWM_READABLE=true
BIOS_WRITE_CONFIRMATION_REQUIRED=false
BIOS_DIRECT_FAN_FALLBACK=false

_bios_log_debug() {
    if declare -F ugreen_log_debug >/dev/null; then ugreen_log_debug "$@"; fi
    return 0
}

_bios_log_info() {
    if declare -F ugreen_log_info >/dev/null; then ugreen_log_info "$@"; fi
    return 0
}

_bios_log_error() {
    if declare -F ugreen_log_error >/dev/null; then ugreen_log_error "$@"; fi
    return 0
}

bios_detected_profile() {
    local product
    product=$(hardware_detected_product_name 2>/dev/null || true)
    case "${product^^}" in
        "DXP480T PLUS"|"UGREEN DXP480T PLUS") echo "dxp480t_plus" ;;
        "DXP4800S") echo "dxp4800s" ;;
        "DXP4800 PLUS"|"UGREEN DXP4800 PLUS") echo "dxp4800_plus" ;;
        "DXP4800 PRO"|"UGREEN DXP4800 PRO") echo "dxp4800_pro" ;;
        *) echo "unknown" ;;
    esac
}

bios_supported_model() {
    case "$(bios_detected_profile)" in
        dxp4800_plus|dxp4800_pro|dxp4800s|dxp480t_plus) return 0 ;;
        *) return 1 ;;
    esac
}

bios_direct_fan_fallback_active() {
    local test_path="${BIOS_TEST_IT87_MODULE_PATH:-}"

    if [[ -n "$test_path" ]]; then
        [[ ! -e "$test_path" ]]
        return
    fi
    [[ -d /sys/module && ! -e /sys/module/it87 ]]
}

bios_write_confirmation_required() {
    [[ "$(bios_detected_profile)" == "dxp4800s" ]] || bios_direct_fan_fallback_active
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
        [[ -n "$candidate" && -r "$candidate/dxp4800plus.so" && -r "$candidate/dxp4800s.so" && -r "$candidate/dxp480tplus.so" ]] && {
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
        _bios_log_debug "bios.binary_missing" "$BIOS_LAST_ERROR"
        return 127
    }
    plugin_dir=$(bios_ugreenctl_plugin_dir) || {
        BIOS_LAST_ERROR="未找到内置 UGREEN-NAS-Hardware 机型插件"
        _bios_log_debug "bios.plugins_missing" "$BIOS_LAST_ERROR" "binary=$binary"
        return 127
    }
    _bios_log_debug "bios.command_start" "正在调用 UGREEN-NAS-Hardware" \
        "binary=$binary" "plugin_dir=$plugin_dir" "action=$*"
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

bios_read_cli_fans() {
    local output line
    if ! output=$(bios_cli fan status 2>&1); then
        bios_set_error_from_output "$output" "读取 UGREEN-NAS-Hardware 风扇状态失败"
        BIOS_FAN_ERROR="$BIOS_LAST_ERROR"
        if declare -F ugreen_log_rate_limited >/dev/null; then
            ugreen_log_rate_limited "bios-fan-status-$(bios_detected_profile)" 300 WARN \
                "bios.fan_status_read_failed" "$BIOS_FAN_ERROR" \
                "model=$(bios_detected_profile)" "output=$output"
        else
            _bios_log_debug "bios.fan_status_read_failed" "$BIOS_FAN_ERROR" \
                "model=$(bios_detected_profile)" "output=$output"
        fi
        return 1
    fi

    BIOS_CHIP_ID=$BIOS_IT8613_ID
    BIOS_REVISION=0
    while IFS= read -r line; do
        case "$line" in
            fan\ cpu:\ *) bios_parse_fan_line cpu "${line#fan }" ;;
            fan\ sys:\ *) bios_parse_fan_line sys "${line#fan }" ;;
            fan\ sys1:\ *) bios_parse_fan_line sys1 "${line#fan }" ;;
            fan\ sys2:\ *) bios_parse_fan_line sys2 "${line#fan }" ;;
            cpu:\ *) bios_parse_fan_line cpu "$line" ;;
            sys:\ *) bios_parse_fan_line sys "$line" ;;
            sys1:\ *) bios_parse_fan_line sys1 "$line" ;;
            sys2:\ *) bios_parse_fan_line sys2 "$line" ;;
        esac
    done <<< "$output"
    BIOS_FAN_ERROR=""
    BIOS_LAST_ERROR=""
    _bios_log_debug "bios.fan_status_read" "BIOS 风扇状态读取完成" \
        "model=$(bios_detected_profile)" "cpu_pwm=$BIOS_CPU_PWM" "sys_pwm=$BIOS_SYS_PWM" \
        "sys2_pwm=$BIOS_SYS2_PWM" "cpu_rpm=$BIOS_CPU_RPM" "sys_rpm=$BIOS_SYS_RPM" "sys2_rpm=$BIOS_SYS2_RPM"
}

bios_read_cli_startup() {
    local output startup
    if ! output=$(bios_cli power startup get 2>&1); then
        bios_set_error_from_output "$output" "读取来电启动策略失败"
        BIOS_STARTUP_ERROR="$BIOS_LAST_ERROR"
        if declare -F ugreen_log_rate_limited >/dev/null; then
            ugreen_log_rate_limited "bios-startup-status-$(bios_detected_profile)" 300 WARN \
                "bios.startup_status_read_failed" "$BIOS_STARTUP_ERROR" \
                "model=$(bios_detected_profile)" "output=$output"
        fi
        return 1
    fi
    startup=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)
    [[ "$startup" == "restore" ]] && startup=last
    case "$startup" in
        on|off|last) BIOS_STARTUP_POLICY="$startup" ;;
        *)
            BIOS_STARTUP_ERROR="来电启动策略返回了未知值：${startup:-<empty>}"
            return 1
            ;;
    esac
    BIOS_STARTUP_ERROR=""
    BIOS_LAST_ERROR=""
    _bios_log_debug "bios.startup_status_read" "来电启动策略读取完成" \
        "model=$(bios_detected_profile)" "policy=$BIOS_STARTUP_POLICY"
}

bios_read_status() {
    BIOS_LAST_ERROR=""
    BIOS_FAN_ERROR=""
    BIOS_STARTUP_ERROR=""
    BIOS_SUPPORTED=false
    BIOS_AVAILABLE=false
    BIOS_STARTUP_AVAILABLE=false
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
    BIOS_CPU_FAN_PRESENT=true
    BIOS_FAN_MODE_WRITABLE=false
    BIOS_PWM_READABLE=true
    BIOS_WRITE_CONFIRMATION_REQUIRED=false
    BIOS_DIRECT_FAN_FALLBACK=false

    if ! bios_supported_model; then
        BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S 与 DXP480T Plus"
        return 0
    fi
    BIOS_SUPPORTED=true
    if [[ "$BIOS_MODEL" == "dxp480t_plus" ]]; then
        BIOS_FAN_WRITE_TARGET="all"
    elif [[ "$BIOS_MODEL" == "dxp4800s" ]]; then
        BIOS_EXPERIMENTAL=true
        BIOS_MIN_PWM=40
        BIOS_CPU_FAN_PRESENT=false
        BIOS_PWM_READABLE=true
        BIOS_WRITE_CONFIRMATION_REQUIRED=true
    fi
    if bios_direct_fan_fallback_active; then
        BIOS_DIRECT_FAN_FALLBACK=true
        BIOS_WRITE_CONFIRMATION_REQUIRED=true
    fi
    BIOS_BACKEND=$(bios_backend)
    if [[ "$BIOS_BACKEND" != "ugreenctl" ]]; then
        BIOS_LAST_ERROR="内置 UGREEN-NAS-Hardware 控制程序或机型插件不可用"
        if declare -F ugreen_log_rate_limited >/dev/null; then
            ugreen_log_rate_limited "bios-backend-${BIOS_MODEL}" 300 WARN \
                "bios.backend_unavailable" "$BIOS_LAST_ERROR" \
                "model=$BIOS_MODEL" "product=$BIOS_PRODUCT_NAME" "backend=$BIOS_BACKEND"
        fi
        BIOS_FAN_ERROR="$BIOS_LAST_ERROR"
        BIOS_STARTUP_ERROR="$BIOS_LAST_ERROR"
        return 1
    fi
    if bios_read_cli_fans; then
        BIOS_AVAILABLE=true
    fi
    if bios_read_cli_startup; then
        BIOS_STARTUP_AVAILABLE=true
    fi
    BIOS_LAST_ERROR="$BIOS_FAN_ERROR"
    $BIOS_AVAILABLE || $BIOS_STARTUP_AVAILABLE
}

bios_set_fan() {
    local channel="$1" pwm="$2" model output
    # Direct Super I/O is an experimental fallback when it87 hwmon has been
    # intentionally removed. --force is an explicit acknowledgement only;
    # ugreenctl still requires exact DMI, chip-ID and owner checks.
    local -a args=(--force --apply)
    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S 与 DXP480T Plus"; return 1; }
    model=$(bios_detected_profile)
    case "$model" in
        dxp4800s)
            [[ "$pwm" =~ ^[0-9]+$ ]] && (( pwm >= 40 && pwm <= 255 )) || {
                BIOS_LAST_ERROR="DXP4800S PWM 必须在 40 到 255 之间"
                return 1
            }
            [[ "$channel" == "sys" ]] || {
                BIOS_LAST_ERROR="DXP4800S 仅支持系统风扇写入"
                return 1
            }
            ;;
        dxp480t_plus)
            [[ "$pwm" =~ ^[0-9]+$ ]] && (( pwm >= 40 && pwm <= 255 )) || {
                BIOS_LAST_ERROR="PWM 必须在 40 到 255 之间"
                return 1
            }
            [[ "$channel" == "cpu" || "$channel" == "all" ]] || {
                BIOS_LAST_ERROR="DXP480T Plus 仅支持 CPU 或全部风扇写入"
                return 1
            }
            ;;
        *)
            [[ "$pwm" =~ ^[0-9]+$ ]] && (( pwm >= 40 && pwm <= 255 )) || {
                BIOS_LAST_ERROR="PWM 必须在 40 到 255 之间"
                return 1
            }
            [[ "$channel" == "cpu" || "$channel" == "sys" ]] || {
                BIOS_LAST_ERROR="未知风扇通道"
                return 1
            }
            ;;
    esac
    if ! output=$(bios_cli "${args[@]}" fan set "$channel" "$pwm" 2>&1); then
        bios_set_error_from_output "$output" "设置风扇 PWM 失败"
        _bios_log_error "bios.fan_set_failed" "$BIOS_LAST_ERROR" \
            "model=$model" "channel=$channel" "pwm=$pwm" "forced=$([[ "$model" == "dxp4800s" ]] && echo true || echo false)" \
            "output=$output"
        return 1
    fi
    _bios_log_info "bios.fan_set" "风扇 PWM 写入成功" \
        "model=$model" "channel=$channel" "pwm=$pwm" "forced=true"
}

bios_set_fan_mode() {
    local channel="$1" mode="$2"
    BIOS_LAST_ERROR=""
    BIOS_LAST_ERROR="暂时只开放手动 PWM 写入；pwm*_enable=2 不是原厂 hwmonitor 软件温控曲线"
    _bios_log_debug "bios.fan_mode_rejected" "$BIOS_LAST_ERROR" \
        "channel=$channel" "mode=$mode"
    return 1
}

bios_set_startup() {
    local policy="$1" upstream_policy output model
    local -a args=(--apply)
    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DXP4800 Plus / Pro、DXP4800S 与 DXP480T Plus"; return 1; }
    model=$(bios_detected_profile)
    [[ "$model" == "dxp4800s" ]] && args=(--force --apply)
    case "$policy" in
        on|off) upstream_policy="$policy" ;;
        last) upstream_policy="restore" ;;
        *) BIOS_LAST_ERROR="未知来电启动策略"; return 1 ;;
    esac
    if ! output=$(bios_cli "${args[@]}" power startup set "$upstream_policy" 2>&1); then
        bios_set_error_from_output "$output" "设置来电启动策略失败"
        _bios_log_error "bios.startup_set_failed" "$BIOS_LAST_ERROR" \
            "model=$model" "policy=$policy" "upstream_policy=$upstream_policy" "output=$output"
        return 1
    fi
    _bios_log_info "bios.startup_set" "来电启动策略写入成功" \
        "model=$model" "policy=$policy" "upstream_policy=$upstream_policy" \
        "forced=$([[ "$model" == "dxp4800s" ]] && echo true || echo false)"
}
