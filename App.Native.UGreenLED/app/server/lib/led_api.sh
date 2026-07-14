#!/bin/bash
# 绿联 LED 控制库 — 飞牛应用版
# 要点：灯处于关闭状态时，必须先 -on 再设置颜色（硬件限制）

UGREEN_CLI="${UGREEN_CLI:-}"
I2C_BUS="${I2C_BUS:-0}"
LED_API_CACHE_DIR="${LED_API_CACHE_DIR:-/tmp/ugreen-led-api}"

mkdir -p "$LED_API_CACHE_DIR" 2>/dev/null

_led_log() {
    [[ "${LED_DEBUG:-false}" == "true" ]] && echo "[led_api] $*" >&2
}

ensure_i2c() {
    if ! lsmod 2>/dev/null | grep -q i2c_dev; then
        modprobe i2c-dev 2>/dev/null || true
    fi
}

ensure_cli() {
    if [[ -z "$UGREEN_CLI" || ! -x "$UGREEN_CLI" ]]; then
        echo "ugreen_leds_cli 未找到或未可执行: ${UGREEN_CLI:-<empty>}" >&2
        return 1
    fi
    ensure_i2c
    return 0
}

# 解析 -status 输出中的 op_mode（off/on/blink/breath 或数字 0-3）
led_op_mode() {
    local led="$1"
    local raw
    raw=$("$UGREEN_CLI" "$led" -status 2>/dev/null) || return 1
    if [[ "$raw" =~ op_mode:([a-z]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$raw" =~ op_mode:([0-3]) ]]; then
        case "${BASH_REMATCH[1]}" in
            0) echo "off" ;;
            1) echo "on" ;;
            2) echo "blink" ;;
            3) echo "breath" ;;
        esac
        return 0
    fi
    echo "unknown"
    return 0
}

led_is_off() {
    local mode
    mode=$(led_op_mode "$1")
    [[ "$mode" == "off" || "$mode" == "0" ]]
}

# 带缓存的状态键，避免重复 I2C
_cache_file() {
    echo "$LED_API_CACHE_DIR/$(echo "$1" | tr '/' '_').state"
}

led_read_cached_state() {
    local f
    f=$(_cache_file "$1")
    [[ -f "$f" ]] && cat "$f"
}

led_write_cached_state() {
    local f
    f=$(_cache_file "$1")
    echo "$2" > "$f"
}

# 安全开灯（关闭状态下先 -on）
led_ensure_on() {
    local led="$1"
    if led_is_off "$led"; then
        _led_log "$led 处于关闭状态，先执行 -on"
        if ! timeout 5 "$UGREEN_CLI" "$led" -on >/dev/null 2>&1; then
            return 1
        fi
        sleep 0.08
    fi
    return 0
}

# 设置颜色与亮度（自动处理关灯先开）
# 用法: led_set_color disk1 255 0 0 64
led_set_color() {
    local led="$1" r="$2" g="$3" b="$4" brightness="${5:-64}"
    ensure_cli || return 1

    local key="${r},${g},${b},${brightness}"
    if [[ "$(led_read_cached_state "$led")" == "$key" ]]; then
        return 0
    fi

    led_ensure_on "$led" || return 1

    if timeout 5 "$UGREEN_CLI" "$led" -color "$r" "$g" "$b" -brightness "$brightness" -on >/dev/null 2>&1; then
        led_write_cached_state "$led" "$key"
        return 0
    fi

    # 二次尝试：显式先开再设色
    "$UGREEN_CLI" "$led" -on >/dev/null 2>&1
    sleep 0.1
    if timeout 5 "$UGREEN_CLI" "$led" -color "$r" "$g" "$b" -brightness "$brightness" -on >/dev/null 2>&1; then
        led_write_cached_state "$led" "$key"
        return 0
    fi
    return 1
}

led_set_off() {
    local led="$1"
    ensure_cli || return 1
    if [[ "$(led_read_cached_state "$led")" == "off" ]]; then
        return 0
    fi
    if timeout 5 "$UGREEN_CLI" "$led" -off >/dev/null 2>&1; then
        led_write_cached_state "$led" "off"
        return 0
    fi
    return 1
}

led_set_blink() {
    local led="$1" r="$2" g="$3" b="$4" period_ms="$5" on_ms="$6" brightness="${7:-64}"
    ensure_cli || return 1
    local key="blink,${r},${g},${b},${period_ms},${on_ms},${brightness}"
    if [[ "$(led_read_cached_state "$led")" == "$key" ]]; then
        return 0
    fi
    led_ensure_on "$led" || return 1
    if timeout 5 "$UGREEN_CLI" "$led" -color "$r" "$g" "$b" -blink "$period_ms" "$on_ms" -brightness "$brightness" -on >/dev/null 2>&1; then
        led_write_cached_state "$led" "$key"
        return 0
    fi
    return 1
}

led_all_status() {
    ensure_cli || return 1
    "$UGREEN_CLI" all -status 2>/dev/null
}

led_list_disk_slots() {
    local status line
    status=$(led_all_status) || return 1
    while IFS= read -r line; do
        if [[ "$line" =~ ^(disk[0-9]+): ]]; then
            echo "${BASH_REMATCH[1]}"
        elif [[ "$line" =~ LED[[:space:]]+(disk[0-9]+) ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done <<< "$status"
}

led_clear_cache() {
    rm -f "$LED_API_CACHE_DIR"/* 2>/dev/null
}
