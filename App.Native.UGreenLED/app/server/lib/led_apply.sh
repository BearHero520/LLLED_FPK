#!/bin/bash
# 根据配置应用灯光（依赖 led_api.sh settings.sh）

apply_color_from_settings() {
    local led="$1" section="$2" state_key="$3" settings="$4"
    local color brightness

    color=$(settings_get "$settings" "${section}_colors" "$state_key" "")
    brightness=$(settings_get "$settings" "${section}_brightness" "$state_key" "64")

    if [[ "$color" == "off" || "$brightness" == "0" ]]; then
        led_set_off "$led"
        return 0
    fi

    led_set_color "$led" $color "$brightness"
}

apply_disk_state_led() {
    local led="$1" state="$2" settings="$3"
    apply_color_from_settings "$led" "disk" "$state" "$settings"
}

apply_netdev_state() {
    local state="$1" settings="$2"
    apply_color_from_settings "netdev" "netdev" "$state" "$settings"
}

apply_power_smart() {
    local settings="$1"
    local color brightness
    color=$(settings_get "$settings" power smart_color "100 100 100")
    brightness=$(settings_get "$settings" power brightness "40")
    led_set_color "power" $color "$brightness"
}

apply_power_all_on() {
    local settings="$1"
    local color brightness
    color=$(settings_get "$settings" power all_on_color "180 180 180")
    brightness=$(settings_get "$settings" power brightness "64")
    led_set_color "power" $color "$brightness"
}

led_all_off_full() {
    local s
    for s in power netdev $(led_list_disk_slots 2>/dev/null); do
        led_set_off "$s" 2>/dev/null
    done
    led_clear_cache
}

led_all_on_full() {
    local settings="${1:-}" s color brightness
    color="200 200 200"
    brightness="64"
    if [[ -n "$settings" ]]; then
        color=$(settings_get "$settings" power all_on_color "200 200 200")
        brightness=$(settings_get "$settings" disk_brightness active "96")
    fi
    for s in power netdev $(led_list_disk_slots 2>/dev/null); do
        led_set_color "$s" $color "$brightness"
    done
}
