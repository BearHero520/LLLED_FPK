#!/bin/bash
# BIOS/Super I/O control is provided by the bundled UGREEN-NAS-Hardware
# ugreenctl CLI.  Keep this file as the app-facing adapter: it preserves the
# HTTP API, while the upstream project owns
# the model plugins, register maps, DMI matching and hardware safeguards.

BIOS_UGREENCTL="${BIOS_UGREENCTL:-}"
BIOS_UGREENCTL_PLUGIN_DIR="${BIOS_UGREENCTL_PLUGIN_DIR:-}"
BIOS_UGREENCTL_FAND="${BIOS_UGREENCTL_FAND:-}"
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
BIOS_CPU_CELSIUS=-1
BIOS_CPU_PEAK_CELSIUS=-1
BIOS_HDD_CELSIUS=-1
BIOS_SSD_CELSIUS=-1
BIOS_THERMAL_ERROR=""
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
        "DXP6800 PRO") echo "dxp6800pro" ;;
        *) echo "unknown" ;;
    esac
}

bios_supported_model() {
    case "$(bios_detected_profile)" in
        dxp4800_plus|dxp4800_pro|dxp4800s|dxp480t_plus|dxp6800pro) return 0 ;;
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
    case "$(bios_detected_profile)" in
        dxp4800s|dxp6800pro) return 0 ;;
    esac
    bios_direct_fan_fallback_active
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

bios_ugreenctl_fand_binary() {
    local candidate
    for candidate in \
        "$BIOS_UGREENCTL_FAND" \
        "${SERVER_DIR:-}/bin/ugreenctl-fand" \
        "${APP_ROOT:-}/target/server/bin/ugreenctl-fand"; do
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
        [[ -n "$candidate" && -r "$candidate/dxp4800plus.so" && -r "$candidate/dxp4800s.so" && -r "$candidate/dxp480tplus.so" && -r "$candidate/dxp6800pro.so" ]] && {
            printf '%s\n' "$candidate"
            return 0
        }
    done
    return 1
}

bios_backend() {
    bios_ugreenctl_binary >/dev/null && bios_ugreenctl_plugin_dir >/dev/null && echo "ugreenctl" || echo "unavailable"
}

bios_fan_curve_config_path() { printf '%s\n' "${VAR_DIR:-/var/apps/App.Native.UGreenLED/var}/fan-curve.conf"; }
bios_fan_curve_state_path() { printf '%s\n' "${RUNTIME_DIR:-/run/App.Native.UGreenLED}/fan-curve.state"; }
bios_fan_curve_pid_path() { printf '%s\n' "${RUNTIME_DIR:-/run/App.Native.UGreenLED}/fan-curve.pid"; }
bios_fan_curve_log_path() { printf '%s\n' "${VAR_DIR:-/var/apps/App.Native.UGreenLED/var}/log/fan-curve.log"; }

bios_fan_curve_stock_profile_for_model() {
    case "$(bios_detected_profile)" in
        dxp4800s) echo "stock-4800s" ;;
        dxp4800_plus|dxp4800_pro) echo "stock-4800plus" ;;
        dxp480t_plus) echo "stock-480tplus" ;;
        dxp6800pro) echo "stock-6800pro" ;;
        *) return 1 ;;
    esac
}

bios_fan_curve_running() {
    local pid_file pid
    pid_file=$(bios_fan_curve_pid_path)
    [[ -f "$pid_file" ]] || return 1
    pid=$(cat "$pid_file" 2>/dev/null || true)
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

bios_fan_curve_csv_thresholds_valid() {
    local value="$1" part previous=-1 count=0
    IFS=',' read -r -a parts <<< "$value"
    [[ ${#parts[@]} -eq 5 ]] || return 1
    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[0-9]+$ ]] && (( 10#$part <= 125 && 10#$part > previous )) || return 1
        previous=$((10#$part))
        ((count += 1))
    done
    (( count == 5 ))
}

bios_fan_curve_csv_pwm_valid() {
    local value="$1" minimum="$2" part previous=-1 count=0
    IFS=',' read -r -a parts <<< "$value"
    [[ ${#parts[@]} -eq 4 ]] || return 1
    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[0-9]+$ ]] && (( 10#$part >= 10#$minimum && 10#$part <= 255 && 10#$part >= previous )) || return 1
        previous=$((10#$part))
        ((count += 1))
    done
    (( count == 4 ))
}

bios_fan_curve_read_state() {
    local key="$1" default="${2:-}" state_file value
    state_file=$(bios_fan_curve_state_path)
    [[ -f "$state_file" ]] || { printf '%s' "$default"; return 0; }
    value=$(sed -n "s/^${key}=//p" "$state_file" 2>/dev/null | tail -n 1)
    printf '%s' "${value:-$default}"
}

bios_fan_curve_status_json() {
    local enabled=false running=false config state pid profile interval downshift minimum require_storage cpu_curve hdd_curve ssd_curve pwm_curve
    local timestamp model status cpu hdd ssd desired applied desired_cpu desired_system applied_cpu applied_system detail
    config=$(bios_fan_curve_config_path)
    state=$(bios_fan_curve_state_path)
    pid=$(bios_fan_curve_pid_path)
    [[ "$(settings_get "$SETTINGS_FILE" fan_curve enabled false)" == "true" ]] && enabled=true
    bios_fan_curve_running && running=true
    profile=$(sed -n 's/^profile=//p' "$config" 2>/dev/null | tail -n 1); profile="${profile:-custom}"
    interval=$(sed -n 's/^interval_seconds=//p' "$config" 2>/dev/null | tail -n 1); interval="${interval:-10}"
    downshift=$(sed -n 's/^downshift_delay_seconds=//p' "$config" 2>/dev/null | tail -n 1); downshift="${downshift:-60}"
    minimum=$(sed -n 's/^minimum_pwm=//p' "$config" 2>/dev/null | tail -n 1); minimum="${minimum:-64}"
    require_storage=$(sed -n 's/^require_storage_sensor=//p' "$config" 2>/dev/null | tail -n 1); require_storage="${require_storage:-false}"
    cpu_curve=$(sed -n 's/^cpu=//p' "$config" 2>/dev/null | tail -n 1); cpu_curve="${cpu_curve:-50,55,75,80,90}"
    hdd_curve=$(sed -n 's/^hdd=//p' "$config" 2>/dev/null | tail -n 1); hdd_curve="${hdd_curve:-40,45,50,55,70}"
    ssd_curve=$(sed -n 's/^ssd=//p' "$config" 2>/dev/null | tail -n 1); ssd_curve="${ssd_curve:-45,50,60,65,70}"
    pwm_curve=$(sed -n 's/^pwm=//p' "$config" 2>/dev/null | tail -n 1); pwm_curve="${pwm_curve:-64,128,204,255}"
    timestamp=$(bios_fan_curve_read_state timestamp 0); model=$(bios_fan_curve_read_state model unknown)
    status=$(bios_fan_curve_read_state status stopped); cpu=$(bios_fan_curve_read_state cpu_celsius -1)
    cpu_peak=$(bios_fan_curve_read_state cpu_peak_celsius -1)
    hdd=$(bios_fan_curve_read_state hdd_celsius -1); ssd=$(bios_fan_curve_read_state ssd_celsius -1)
    desired=$(bios_fan_curve_read_state desired_pwm -1); applied=$(bios_fan_curve_read_state applied_pwm -1)
    desired_cpu=$(bios_fan_curve_read_state desired_cpu_pwm -1); desired_system=$(bios_fan_curve_read_state desired_system_pwm -1)
    applied_cpu=$(bios_fan_curve_read_state applied_cpu_pwm -1); applied_system=$(bios_fan_curve_read_state applied_system_pwm -1)
    detail=$(bios_fan_curve_read_state detail "")
    [[ "$timestamp" =~ ^[0-9]+$ ]] || timestamp=0
    [[ "$cpu" =~ ^-?[0-9]+$ ]] || cpu=-1; [[ "$cpu_peak" =~ ^-?[0-9]+$ ]] || cpu_peak=-1
    [[ "$hdd" =~ ^-?[0-9]+$ ]] || hdd=-1
    [[ "$ssd" =~ ^-?[0-9]+$ ]] || ssd=-1; [[ "$desired" =~ ^-?[0-9]+$ ]] || desired=-1
    [[ "$applied" =~ ^-?[0-9]+$ ]] || applied=-1
    [[ "$desired_cpu" =~ ^-?[0-9]+$ ]] || desired_cpu=-1; [[ "$desired_system" =~ ^-?[0-9]+$ ]] || desired_system=-1
    [[ "$applied_cpu" =~ ^-?[0-9]+$ ]] || applied_cpu=-1; [[ "$applied_system" =~ ^-?[0-9]+$ ]] || applied_system=-1
    printf '{"enabled":%s,"running":%s,"profile":"%s","interval_seconds":%s,"downshift_delay_seconds":%s,"minimum_pwm":%s,"require_storage_sensor":%s,"cpu_curve":"%s","hdd_curve":"%s","ssd_curve":"%s","pwm_curve":"%s","timestamp":%s,"model":"%s","status":"%s","cpu_celsius":%s,"cpu_peak_celsius":%s,"hdd_celsius":%s,"ssd_celsius":%s,"desired_pwm":%s,"applied_pwm":%s,"desired_cpu_pwm":%s,"desired_system_pwm":%s,"applied_cpu_pwm":%s,"applied_system_pwm":%s,"detail":"%s"}' \
        "$enabled" "$running" "$(json_str "$profile")" "$interval" "$downshift" "$minimum" "$require_storage" \
        "$(json_str "$cpu_curve")" "$(json_str "$hdd_curve")" "$(json_str "$ssd_curve")" "$(json_str "$pwm_curve")" "$timestamp" \
        "$(json_str "$model")" "$(json_str "$status")" "$cpu" "$cpu_peak" "$hdd" "$ssd" "$desired" "$applied" "$desired_cpu" "$desired_system" "$applied_cpu" "$applied_system" "$(json_str "$detail")"
}

bios_fan_curve_stop() {
    local preserve_enabled="${1:-false}" pid_file pid
    pid_file=$(bios_fan_curve_pid_path)
    if [[ -f "$pid_file" ]]; then
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
    [[ "$preserve_enabled" == "true" ]] || settings_set "$SETTINGS_FILE" fan_curve enabled false
    _bios_log_info "bios.fan_curve_stopped" "温控曲线守护进程已停止"
}

bios_fan_curve_start() {
    local profile="$1" interval="$2" downshift="$3" minimum="$4" cpu="$5" hdd="$6" ssd="$7" pwm="$8" require_storage="$9" confirmed="${10:-false}"
    local config state pid log binary daemon plugins model stock_profile allow_unvalidated=false
    local -a command

    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="当前机型不支持受保护的风扇温控曲线"; return 1; }
    model=$(bios_detected_profile)
    stock_profile=$(bios_fan_curve_stock_profile_for_model) || { BIOS_LAST_ERROR="当前机型没有已验证的原厂温控预设"; return 1; }
    [[ "$profile" == "custom" || "$profile" == "$stock_profile" ]] || {
        BIOS_LAST_ERROR="原厂兼容曲线必须与检测到的精确机型匹配"; return 1;
    }
    [[ "$interval" =~ ^[0-9]+$ ]] && (( 10#$interval >= 2 && 10#$interval <= 300 )) || { BIOS_LAST_ERROR="检测间隔必须为 2 到 300 秒"; return 1; }
    [[ "$downshift" =~ ^[0-9]+$ ]] && (( 10#$downshift <= 3600 )) || { BIOS_LAST_ERROR="降速延迟必须为 0 到 3600 秒"; return 1; }
    [[ "$minimum" =~ ^[0-9]+$ ]] && (( 10#$minimum >= 40 && 10#$minimum <= 255 )) || { BIOS_LAST_ERROR="最低 PWM 必须在 40 到 255 之间"; return 1; }
    [[ "$require_storage" =~ ^(true|false)$ ]] || { BIOS_LAST_ERROR="存储温度保护参数无效"; return 1; }
    if [[ "$profile" == "custom" ]]; then
        bios_fan_curve_csv_thresholds_valid "$cpu" && bios_fan_curve_csv_thresholds_valid "$hdd" && bios_fan_curve_csv_thresholds_valid "$ssd" && bios_fan_curve_csv_pwm_valid "$pwm" "$minimum" || {
            BIOS_LAST_ERROR="曲线阈值或 PWM 档位无效"; return 1;
        }
    fi
    if bios_write_confirmation_required; then
        [[ "$confirmed" == "true" ]] || { BIOS_LAST_ERROR="受保护机型启动自动温控前需要确认风险"; return 1; }
        allow_unvalidated=true
    fi
    binary=$(bios_ugreenctl_binary) || { BIOS_LAST_ERROR="未找到内置 ugreenctl"; return 1; }
    daemon=$(bios_ugreenctl_fand_binary) || { BIOS_LAST_ERROR="未找到内置温控守护程序"; return 1; }
    plugins=$(bios_ugreenctl_plugin_dir) || { BIOS_LAST_ERROR="未找到内置机型插件"; return 1; }
    config=$(bios_fan_curve_config_path); state=$(bios_fan_curve_state_path); pid=$(bios_fan_curve_pid_path); log=$(bios_fan_curve_log_path)
    mkdir -p "$(dirname "$config")" "$(dirname "$state")" "$(dirname "$log")" || { BIOS_LAST_ERROR="无法创建温控运行目录"; return 1; }
    bios_fan_curve_stop true
    umask 077
    cat > "${config}.tmp" <<EOF
profile=${profile}
interval_seconds=${interval}
downshift_delay_seconds=${downshift}
minimum_pwm=${minimum}
failsafe_pwm=255
require_storage_sensor=${require_storage}
allow_unvalidated_writes=${allow_unvalidated}
cpu=${cpu}
hdd=${hdd}
ssd=${ssd}
pwm=${pwm}
EOF
    mv "${config}.tmp" "$config" || { BIOS_LAST_ERROR="无法保存温控曲线配置"; return 1; }
    command=("$daemon" --config "$config" --state "$state" --ugreenctl "$binary" --plugin-dir "$plugins")
    nohup "${command[@]}" < /dev/null >> "$log" 2>&1 &
    echo $! > "$pid"
    sleep 0.05
    if ! bios_fan_curve_running; then
        BIOS_LAST_ERROR="温控守护程序未能启动，请查看 fan-curve.log"
        settings_set "$SETTINGS_FILE" fan_curve enabled false
        return 1
    fi
    settings_set "$SETTINGS_FILE" fan_curve enabled true
    _bios_log_info "bios.fan_curve_started" "温控曲线守护进程已启动" \
        "model=$model" "profile=$profile" "interval=$interval" "downshift=$downshift" "minimum_pwm=$minimum" \
        "require_storage=$require_storage" "allow_unvalidated=$allow_unvalidated"
}

bios_fan_curve_restore() {
    local config profile interval downshift minimum cpu hdd ssd pwm storage confirmed=false
    [[ "$(settings_get "$SETTINGS_FILE" fan_curve enabled false)" == "true" ]] || return 0
    bios_fan_curve_running && return 0
    config=$(bios_fan_curve_config_path)
    [[ -r "$config" ]] || return 0
    profile=$(sed -n 's/^profile=//p' "$config" | tail -n 1); interval=$(sed -n 's/^interval_seconds=//p' "$config" | tail -n 1)
    downshift=$(sed -n 's/^downshift_delay_seconds=//p' "$config" | tail -n 1); minimum=$(sed -n 's/^minimum_pwm=//p' "$config" | tail -n 1)
    cpu=$(sed -n 's/^cpu=//p' "$config" | tail -n 1); hdd=$(sed -n 's/^hdd=//p' "$config" | tail -n 1)
    ssd=$(sed -n 's/^ssd=//p' "$config" | tail -n 1); pwm=$(sed -n 's/^pwm=//p' "$config" | tail -n 1)
    storage=$(sed -n 's/^require_storage_sensor=//p' "$config" | tail -n 1)
    [[ "$(sed -n 's/^allow_unvalidated_writes=//p' "$config" | tail -n 1)" == "true" ]] && confirmed=true
    bios_fan_curve_start "$profile" "$interval" "$downshift" "$minimum" "$cpu" "$hdd" "$ssd" "$pwm" "$storage" "$confirmed"
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

bios_thermal_value() {
    local output="$1" key="$2" value
    value=$(printf '%s\n' "$output" | tr ' ' '\n' | sed -n "s/^${key}=//p" | tail -n 1)
    [[ "$value" =~ ^-?[0-9]+$ ]] || value=-1
    printf '%s' "$value"
}

bios_read_thermal_snapshot() {
    local output
    BIOS_CPU_CELSIUS=-1
    BIOS_CPU_PEAK_CELSIUS=-1
    BIOS_HDD_CELSIUS=-1
    BIOS_SSD_CELSIUS=-1
    BIOS_THERMAL_ERROR=""
    if ! output=$(bios_cli thermal status 2>&1); then
        BIOS_THERMAL_ERROR=$(printf '%s\n' "$output" | sed -n 's/^error:[[:space:]]*//p' | head -n 1)
        [[ -n "$BIOS_THERMAL_ERROR" ]] || BIOS_THERMAL_ERROR="温度快照读取失败"
        return 1
    fi
    BIOS_CPU_CELSIUS=$(bios_thermal_value "$output" cpu_celsius)
    BIOS_CPU_PEAK_CELSIUS=$(bios_thermal_value "$output" cpu_peak_celsius)
    BIOS_HDD_CELSIUS=$(bios_thermal_value "$output" hdd_celsius)
    BIOS_SSD_CELSIUS=$(bios_thermal_value "$output" ssd_celsius)
    return 0
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
    BIOS_CPU_CELSIUS=-1
    BIOS_CPU_PEAK_CELSIUS=-1
    BIOS_HDD_CELSIUS=-1
    BIOS_SSD_CELSIUS=-1
    BIOS_THERMAL_ERROR=""
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
    elif [[ "$BIOS_MODEL" == "dxp6800pro" ]]; then
        BIOS_EXPERIMENTAL=true
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
    bios_read_thermal_snapshot >/dev/null 2>&1 || true
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
        dxp6800pro)
            [[ "$pwm" =~ ^[0-9]+$ ]] && (( pwm >= 40 && pwm <= 255 )) || {
                BIOS_LAST_ERROR="DXP6800 Pro PWM 必须在 40 到 255 之间"
                return 1
            }
            [[ "$channel" == "cpu" || "$channel" == "sys" ]] || {
                BIOS_LAST_ERROR="DXP6800 Pro 仅支持 CPU 或成对系统风扇写入"
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
        "model=$model" "channel=$channel" "pwm=$pwm" "forced=$([[ "$model" == "dxp4800s" || "$model" == "dxp6800pro" ]] && echo true || echo false)" \
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
    [[ "$model" == "dxp4800s" || "$model" == "dxp6800pro" ]] && args=(--force --apply)
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
        "forced=$([[ "$model" == "dxp4800s" || "$model" == "dxp6800pro" ]] && echo true || echo false)"
}
