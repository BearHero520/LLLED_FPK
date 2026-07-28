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
BIOS_WOL_ERROR=""
BIOS_SUPPORTED=false
BIOS_AVAILABLE=false
BIOS_STARTUP_AVAILABLE=false
BIOS_WOL_AVAILABLE=false
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
BIOS_WOL_POLICY="unknown"
BIOS_RTC_WAKE_EPOCH=0
BIOS_POWER_SCHEDULE_ENABLED=false
BIOS_POWER_SCHEDULE_DAYS=""
BIOS_POWER_SCHEDULE_WAKE_TIME=""
BIOS_POWER_SCHEDULE_SHUTDOWN_TIME=""
BIOS_POWER_SCHEDULE_AVAILABLE=false
BIOS_POWER_SCHEDULE_ERROR=""
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
        "DX4600"|"DX4600+"|"DX4600 PRO") echo "dx4600" ;;
        "DXP480T PLUS"|"UGREEN DXP480T PLUS") echo "dxp480t_plus" ;;
        "DXP4800") echo "dxp4800" ;;
        "DXP4800S") echo "dxp4800s" ;;
        "DXP4800 PLUS"|"UGREEN DXP4800 PLUS") echo "dxp4800_plus" ;;
        "DXP4800 PRO"|"UGREEN DXP4800 PRO") echo "dxp4800_pro" ;;
        "DXP6800 PRO") echo "dxp6800pro" ;;
        *) echo "unknown" ;;
    esac
}

bios_supported_model() {
    case "$(bios_detected_profile)" in
        dx4600|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800s|dxp480t_plus|dxp6800pro) return 0 ;;
        *) return 1 ;;
    esac
}

bios_wol_supported_model() {
    case "$(bios_detected_profile)" in
        dx4600|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800s|dxp480t_plus|dxp6800pro) return 0 ;;
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
        # WOL and RTC scheduled wake are firmware-reversed on every mapped model.
        dx4600|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800s|dxp480t_plus|dxp6800pro) return 0 ;;
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
        [[ -n "$candidate" && -r "$candidate/dx4600.so" && -r "$candidate/dxp4800.so" && -r "$candidate/dxp4800plus.so" && -r "$candidate/dxp4800s.so" && -r "$candidate/dxp480tplus.so" && -r "$candidate/dxp6800pro.so" ]] && {
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
        dx4600) echo "stock-4600" ;;
        dxp4800) echo "stock-4800" ;;
        dxp4800s) echo "stock-4800s" ;;
        dxp4800_plus|dxp4800_pro) echo "stock-4800plus" ;;
        dxp480t_plus) echo "stock-480tplus" ;;
        dxp6800pro) echo "stock-6800pro" ;;
        *) return 1 ;;
    esac
}

bios_fan_curve_stock_document() {
    local candidate
    for candidate in \
        "${BIOS_UGREENCTL_STOCK_DOCUMENT:-}" \
        "${SERVER_DIR:-}/vendor/UGREEN-NAS-Hardware/docs/FAN_CURVE.md" \
        "${APP_ROOT:-}/target/server/vendor/UGREEN-NAS-Hardware/docs/FAN_CURVE.md"; do
        [[ -n "$candidate" && -r "$candidate" && ! -L "$candidate" ]] && {
            printf '%s\n' "$candidate"
            return 0
        }
    done
    return 1
}

bios_fan_curve_stock_csv() {
    local source="$1" system_pwm="${2:-}" expected="$3" normalized
    normalized=$(printf '%s' "$source" | tr -d '` ')
    if [[ "$normalized" == "samechannel" ]]; then
        printf '%s' "$system_pwm"
        return 0
    fi
    if [[ "$normalized" == disabled* ]]; then
        printf '0,0,0,0,0'
        return 0
    fi
    normalized=$(printf '%s' "$normalized" | tr '/' ',' | tr -cd '0-9,')
    IFS=',' read -r -a values <<< "$normalized"
    [[ ${#values[@]} -eq "$expected" ]] || return 1
    printf '%s' "$(IFS=,; echo "${values[*]}")"
}

# The recovered stock policy remains authored by UGREEN-NAS-Hardware.  This
# adapter only exposes its bundled FAN_CURVE.md record to the application.
bios_fan_curve_stock_json() {
    local profile document row dmi cpu hdd ssd system_pwm cpu_pwm ignored
    local cpu_csv hdd_csv ssd_csv system_csv cpu_pwm_csv
    profile=$(bios_fan_curve_stock_profile_for_model) || {
        printf '{"available":false}'
        return 0
    }
    document=$(bios_fan_curve_stock_document) || {
        printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"
        return 0
    }
    row=$(awk -F'|' -v profile="\`$profile\`" '$0 ~ profile { print; exit }' "$document")
    [[ -n "$row" ]] || {
        printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"
        return 0
    }
    IFS='|' read -r ignored dmi ignored cpu hdd ssd system_pwm cpu_pwm ignored <<< "$row"
    cpu_csv=$(bios_fan_curve_stock_csv "$cpu" "" 5) || { printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"; return 0; }
    hdd_csv=$(bios_fan_curve_stock_csv "$hdd" "" 5) || { printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"; return 0; }
    ssd_csv=$(bios_fan_curve_stock_csv "$ssd" "" 5) || { printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"; return 0; }
    system_csv=$(bios_fan_curve_stock_csv "$system_pwm" "" 4) || { printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"; return 0; }
    cpu_pwm_csv=$(bios_fan_curve_stock_csv "$cpu_pwm" "$system_csv" 4) || { printf '{"available":false,"profile":"%s"}' "$(json_str "$profile")"; return 0; }
    printf '{"available":true,"profile":"%s","cpu":"%s","hdd":"%s","ssd":"%s","system_pwm":"%s","cpu_pwm":"%s"}' \
        "$(json_str "$profile")" "$cpu_csv" "$hdd_csv" "$ssd_csv" "$system_csv" "$cpu_pwm_csv"
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
    local timestamp model status cpu hdd ssd desired applied desired_cpu desired_system applied_cpu applied_system detail stock_curve
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
    stock_curve=$(bios_fan_curve_stock_json)
    [[ "$timestamp" =~ ^[0-9]+$ ]] || timestamp=0
    [[ "$cpu" =~ ^-?[0-9]+$ ]] || cpu=-1; [[ "$cpu_peak" =~ ^-?[0-9]+$ ]] || cpu_peak=-1
    [[ "$hdd" =~ ^-?[0-9]+$ ]] || hdd=-1
    [[ "$ssd" =~ ^-?[0-9]+$ ]] || ssd=-1; [[ "$desired" =~ ^-?[0-9]+$ ]] || desired=-1
    [[ "$applied" =~ ^-?[0-9]+$ ]] || applied=-1
    [[ "$desired_cpu" =~ ^-?[0-9]+$ ]] || desired_cpu=-1; [[ "$desired_system" =~ ^-?[0-9]+$ ]] || desired_system=-1
    [[ "$applied_cpu" =~ ^-?[0-9]+$ ]] || applied_cpu=-1; [[ "$applied_system" =~ ^-?[0-9]+$ ]] || applied_system=-1
    printf '{"enabled":%s,"running":%s,"profile":"%s","interval_seconds":%s,"downshift_delay_seconds":%s,"minimum_pwm":%s,"require_storage_sensor":%s,"cpu_curve":"%s","hdd_curve":"%s","ssd_curve":"%s","pwm_curve":"%s","stock_curve":%s,"timestamp":%s,"model":"%s","status":"%s","cpu_celsius":%s,"cpu_peak_celsius":%s,"hdd_celsius":%s,"ssd_celsius":%s,"desired_pwm":%s,"applied_pwm":%s,"desired_cpu_pwm":%s,"desired_system_pwm":%s,"applied_cpu_pwm":%s,"applied_system_pwm":%s,"detail":"%s"}' \
        "$enabled" "$running" "$(json_str "$profile")" "$interval" "$downshift" "$minimum" "$require_storage" \
        "$(json_str "$cpu_curve")" "$(json_str "$hdd_curve")" "$(json_str "$ssd_curve")" "$(json_str "$pwm_curve")" "$stock_curve" "$timestamp" \
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

bios_read_cli_wol() {
    local output policy

    if ! output=$(bios_cli network wol get 2>&1); then
        bios_set_error_from_output "$output" "读取网络唤醒状态失败"
        BIOS_WOL_ERROR="$BIOS_LAST_ERROR"
        if declare -F ugreen_log_rate_limited >/dev/null; then
            ugreen_log_rate_limited "bios-wol-status-$(bios_detected_profile)" 300 WARN \
                "bios.wol_status_read_failed" "$BIOS_WOL_ERROR" \
                "model=$(bios_detected_profile)" "output=$output"
        fi
        return 1
    fi
    policy=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)
    case "$policy" in
        on|off) BIOS_WOL_POLICY="$policy" ;;
        *)
            BIOS_WOL_ERROR="网络唤醒返回了未知值：${policy:-<empty>}"
            return 1
            ;;
    esac
    BIOS_WOL_ERROR=""
    BIOS_LAST_ERROR=""
    _bios_log_debug "bios.wol_status_read" "网络唤醒状态读取完成" \
        "model=$(bios_detected_profile)" "policy=$BIOS_WOL_POLICY"
}

bios_schedule_days_valid() {
    local days="$1" day seen=","
    local -a schedule_days

    [[ "$days" =~ ^[1-7](,[1-7])*$ ]] || return 1
    IFS=',' read -r -a schedule_days <<< "$days"
    for day in "${schedule_days[@]}"; do
        [[ "$seen" != *",${day},"* ]] || return 1
        seen+="${day},"
    done
}

bios_schedule_time_valid() {
    local time_value="$1" hour minute

    [[ "$time_value" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]] || return 1
    hour=${time_value%:*}
    minute=${time_value#*:}
    (( 10#$hour <= 23 && 10#$minute <= 59 ))
}

bios_schedule_next_epoch() {
    local days="$1" wake_time="$2" offset day candidate now

    now=$(date +%s) || return 1
    for ((offset = 0; offset <= 7; ++offset)); do
        candidate=$(date -d "today +${offset} days ${wake_time}" +%s 2>/dev/null) || return 1
        day=$(date -d "@${candidate}" +%u 2>/dev/null) || return 1
        [[ ",$days," == *",${day},"* ]] || continue
        (( candidate > now + 60 )) || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

bios_read_cli_rtc_wake() {
    local output epoch

    if ! output=$(bios_cli power rtc-wake get 2>&1); then
        bios_set_error_from_output "$output" "读取定时开机 RTC 状态失败"
        BIOS_POWER_SCHEDULE_ERROR="$BIOS_LAST_ERROR"
        return 1
    fi
    epoch=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)
    [[ "$epoch" =~ ^[0-9]+$ ]] || {
        BIOS_POWER_SCHEDULE_ERROR="RTC 定时开机返回了无效时间"
        return 1
    }
    BIOS_RTC_WAKE_EPOCH="$epoch"
    BIOS_POWER_SCHEDULE_ERROR=""
    BIOS_LAST_ERROR=""
}

bios_schedule_cron_file() {
    printf '%s\n' "${BIOS_SCHEDULE_CRON_FILE:-/etc/cron.d/app-native-ugreen-led-power}"
}

bios_schedule_install_shutdown_cron() {
    local days="$1" shutdown_time="$2" cron_file temp minute hour

    cron_file=$(bios_schedule_cron_file)
    minute=${shutdown_time#*:}
    hour=${shutdown_time%:*}
    mkdir -p "$(dirname "$cron_file")" || { BIOS_LAST_ERROR="无法创建定时关机目录"; return 1; }
    temp=$(mktemp "${cron_file}.tmp.XXXXXX") || { BIOS_LAST_ERROR="无法创建定时关机配置"; return 1; }
    {
        printf '%s\n' '# Managed by App.Native.UGreenLED. Do not edit manually.'
        printf '%s\n' 'SHELL=/bin/bash'
        printf '%s %s * * %s root %q shutdown\n' "$minute" "$hour" "$days" "${SERVER_DIR}/scheduled_power.sh"
    } > "$temp" || { rm -f "$temp"; BIOS_LAST_ERROR="无法写入定时关机配置"; return 1; }
    chmod 0644 "$temp" || { rm -f "$temp"; BIOS_LAST_ERROR="无法设置定时关机配置权限"; return 1; }
    mv "$temp" "$cron_file" || { rm -f "$temp"; BIOS_LAST_ERROR="无法启用定时关机配置"; return 1; }
}

bios_schedule_remove_shutdown_cron() {
    local cron_file

    cron_file=$(bios_schedule_cron_file)
    [[ -e "$cron_file" ]] || return 0
    rm -f -- "$cron_file" || { BIOS_LAST_ERROR="无法移除定时关机配置"; return 1; }
}

bios_schedule_rearm() {
    local days="$1" wake_time="$2" epoch output

    bios_schedule_days_valid "$days" && bios_schedule_time_valid "$wake_time" || {
        BIOS_LAST_ERROR="定时开机日期或时间无效"
        return 1
    }
    epoch=$(bios_schedule_next_epoch "$days" "$wake_time") || {
        BIOS_LAST_ERROR="无法计算下一次定时开机时间"
        return 1
    }
    if ! output=$(bios_cli --force --apply power rtc-wake set "$epoch" 2>&1); then
        bios_set_error_from_output "$output" "设置 RTC 定时开机失败"
        return 1
    fi
    BIOS_RTC_WAKE_EPOCH="$epoch"
    BIOS_LAST_ERROR=""
    _bios_log_info "bios.power_schedule_rearmed" "RTC 定时开机已重设" \
        "model=$(bios_detected_profile)" "days=$days" "wake_time=$wake_time" "epoch=$epoch"
}

bios_power_schedule_set() {
    local settings_file="$1" enabled="$2" days="$3" wake_time="$4" shutdown_time="$5"

    BIOS_LAST_ERROR=""
    bios_wol_supported_model || { BIOS_LAST_ERROR="当前机型没有固件映射的 RTC 定时开机路径"; return 1; }
    case "$enabled" in
        true)
            bios_schedule_days_valid "$days" && bios_schedule_time_valid "$wake_time" && \
                bios_schedule_time_valid "$shutdown_time" || {
                    BIOS_LAST_ERROR="定时开关机的日期或时间无效"
                    return 1
                }
            bios_schedule_install_shutdown_cron "$days" "$shutdown_time" || return 1
            if ! bios_schedule_rearm "$days" "$wake_time"; then
                bios_schedule_remove_shutdown_cron >/dev/null 2>&1 || true
                return 1
            fi
            if ! settings_apply_updates "$settings_file" <<EOF
power_schedule.enabled=true
power_schedule.days=$days
power_schedule.wake_time=$wake_time
power_schedule.shutdown_time=$shutdown_time
EOF
            then
                BIOS_LAST_ERROR="无法保存定时开关机配置"
                bios_schedule_remove_shutdown_cron >/dev/null 2>&1 || true
                bios_cli --force --apply power rtc-wake clear >/dev/null 2>&1 || true
                return 1
            fi
            ;;
        false)
            bios_schedule_remove_shutdown_cron || return 1
            if ! bios_cli --force --apply power rtc-wake clear >/dev/null 2>&1; then
                BIOS_LAST_ERROR="清除 RTC 定时开机失败"
                return 1
            fi
            BIOS_RTC_WAKE_EPOCH=0
            if ! settings_apply_updates "$settings_file" <<'EOF'
power_schedule.enabled=false
power_schedule.days=
power_schedule.wake_time=
power_schedule.shutdown_time=
EOF
            then
                BIOS_LAST_ERROR="无法保存定时开关机配置"
                return 1
            fi
            ;;
        *) BIOS_LAST_ERROR="定时开关机开关无效"; return 1 ;;
    esac
}

bios_read_power_schedule() {
    local settings_file="$1"

    if ! declare -F settings_get >/dev/null; then
        BIOS_POWER_SCHEDULE_ENABLED=false
        BIOS_POWER_SCHEDULE_DAYS=""
        BIOS_POWER_SCHEDULE_WAKE_TIME=""
        BIOS_POWER_SCHEDULE_SHUTDOWN_TIME=""
        BIOS_POWER_SCHEDULE_AVAILABLE=false
        BIOS_POWER_SCHEDULE_ERROR="定时开关机配置服务不可用"
        BIOS_RTC_WAKE_EPOCH=0
        return 0
    fi
    BIOS_POWER_SCHEDULE_ENABLED=$(settings_get "$settings_file" power_schedule enabled false)
    BIOS_POWER_SCHEDULE_DAYS=$(settings_get "$settings_file" power_schedule days "")
    BIOS_POWER_SCHEDULE_WAKE_TIME=$(settings_get "$settings_file" power_schedule wake_time "")
    BIOS_POWER_SCHEDULE_SHUTDOWN_TIME=$(settings_get "$settings_file" power_schedule shutdown_time "")
    BIOS_POWER_SCHEDULE_AVAILABLE=false
    BIOS_POWER_SCHEDULE_ERROR=""
    BIOS_RTC_WAKE_EPOCH=0
    if bios_wol_supported_model && bios_read_cli_rtc_wake; then
        BIOS_POWER_SCHEDULE_AVAILABLE=true
    fi
}

bios_read_status() {
    BIOS_LAST_ERROR=""
    BIOS_FAN_ERROR=""
    BIOS_STARTUP_ERROR=""
    BIOS_WOL_ERROR=""
    BIOS_SUPPORTED=false
    BIOS_AVAILABLE=false
    BIOS_STARTUP_AVAILABLE=false
    BIOS_WOL_AVAILABLE=false
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
    BIOS_WOL_POLICY="unknown"
    BIOS_RTC_WAKE_EPOCH=0
    BIOS_POWER_SCHEDULE_ENABLED=false
    BIOS_POWER_SCHEDULE_DAYS=""
    BIOS_POWER_SCHEDULE_WAKE_TIME=""
    BIOS_POWER_SCHEDULE_SHUTDOWN_TIME=""
    BIOS_POWER_SCHEDULE_AVAILABLE=false
    BIOS_POWER_SCHEDULE_ERROR=""
    BIOS_CPU_FAN_PRESENT=true
    BIOS_FAN_MODE_WRITABLE=false
    BIOS_PWM_READABLE=true
    BIOS_WRITE_CONFIRMATION_REQUIRED=false
    BIOS_DIRECT_FAN_FALLBACK=false

    if ! bios_supported_model; then
        BIOS_LAST_ERROR="BIOS 控制仅支持 DX4600 / DX4600+ / DX4600 Pro、DXP4800、DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro"
        return 0
    fi
    BIOS_SUPPORTED=true
    if [[ "$BIOS_MODEL" == "dxp480t_plus" ]]; then
        BIOS_FAN_WRITE_TARGET="all"
    elif [[ "$BIOS_MODEL" == "dx4600" || "$BIOS_MODEL" == "dxp4800" || "$BIOS_MODEL" == "dxp4800s" ]]; then
        BIOS_EXPERIMENTAL=true
        BIOS_MIN_PWM=40
        BIOS_CPU_FAN_PRESENT=false
        BIOS_PWM_READABLE=true
        BIOS_WRITE_CONFIRMATION_REQUIRED=true
    elif [[ "$BIOS_MODEL" == "dxp6800pro" ]]; then
        BIOS_EXPERIMENTAL=true
    fi
    bios_write_confirmation_required && BIOS_WRITE_CONFIRMATION_REQUIRED=true
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
        BIOS_WOL_ERROR="$BIOS_LAST_ERROR"
        return 1
    fi
    if bios_read_cli_fans; then
        BIOS_AVAILABLE=true
    fi
    if bios_read_cli_startup; then
        BIOS_STARTUP_AVAILABLE=true
    fi
    if bios_wol_supported_model && bios_read_cli_wol; then
        BIOS_WOL_AVAILABLE=true
    fi
    bios_read_power_schedule "${SETTINGS_FILE:-${VAR_DIR:-/tmp}/settings.conf}"
    bios_read_thermal_snapshot >/dev/null 2>&1 || true
    BIOS_LAST_ERROR="$BIOS_FAN_ERROR"
    $BIOS_AVAILABLE || $BIOS_STARTUP_AVAILABLE || $BIOS_WOL_AVAILABLE
}

bios_set_fan() {
    local channel="$1" pwm="$2" model output
    # Direct Super I/O is an experimental fallback when it87 hwmon has been
    # intentionally removed. --force is an explicit acknowledgement only;
    # ugreenctl still requires exact DMI, chip-ID and owner checks.
    local -a args=(--force --apply)
    BIOS_LAST_ERROR=""
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DX4600 / DX4600+ / DX4600 Pro、DXP4800、DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro"; return 1; }
    model=$(bios_detected_profile)
    case "$model" in
        dx4600|dxp4800|dxp4800s)
            [[ "$pwm" =~ ^[0-9]+$ ]] && (( pwm >= 40 && pwm <= 255 )) || {
                BIOS_LAST_ERROR="DX4600 / DXP4800 系列 PWM 必须在 40 到 255 之间"
                return 1
            }
            [[ "$channel" == "sys" ]] || {
                BIOS_LAST_ERROR="DX4600 / DXP4800 单风扇机型仅支持系统风扇写入"
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
                BIOS_LAST_ERROR="DXP480T Plus 仅支持 CPU 或系统风扇对写入"
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
        "model=$model" "channel=$channel" "pwm=$pwm" "forced=$([[ "$model" == "dx4600" || "$model" == "dxp4800" || "$model" == "dxp4800s" || "$model" == "dxp6800pro" ]] && echo true || echo false)" \
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
    bios_supported_model || { BIOS_LAST_ERROR="BIOS 控制仅支持 DX4600 / DX4600+ / DX4600 Pro、DXP4800、DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro"; return 1; }
    model=$(bios_detected_profile)
    # DXP4800 Plus / Pro use the firmware-recovered IT8613 AC-recovery
    # path too.  Keep the app adapter aligned with ugreenctl: every
    # protected startup-policy write carries both explicit write guards.
    [[ "$model" == "dx4600" || "$model" == "dxp4800" || "$model" == "dxp4800_plus" || "$model" == "dxp4800_pro" || "$model" == "dxp4800s" || "$model" == "dxp6800pro" ]] && args=(--force --apply)
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
        "forced=$([[ "$model" == "dx4600" || "$model" == "dxp4800" || "$model" == "dxp4800_plus" || "$model" == "dxp4800_pro" || "$model" == "dxp4800s" || "$model" == "dxp6800pro" ]] && echo true || echo false)"
}

bios_set_wol() {
    local policy="$1" output model

    BIOS_LAST_ERROR=""
    model=$(bios_detected_profile)
    bios_wol_supported_model || {
        BIOS_LAST_ERROR="网络唤醒仅在固件已映射的 DX4600 系列、DXP4800、DXP4800 Plus / Pro、DXP4800S、DXP480T Plus 与 DXP6800 Pro 上可用"
        return 1
    }
    [[ "$policy" =~ ^(on|off)$ ]] || {
        BIOS_LAST_ERROR="未知网络唤醒策略"
        return 1
    }
    if ! output=$(bios_cli --force --apply network wol set "$policy" 2>&1); then
        bios_set_error_from_output "$output" "设置网络唤醒失败"
        _bios_log_error "bios.wol_set_failed" "$BIOS_LAST_ERROR" \
            "model=$model" "policy=$policy" "output=$output"
        return 1
    fi
    _bios_log_info "bios.wol_set" "网络唤醒策略写入成功" \
        "model=$model" "policy=$policy" "forced=true"
}
