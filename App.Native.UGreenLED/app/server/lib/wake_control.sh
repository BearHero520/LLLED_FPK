#!/bin/bash
# Application adapter only. Eligibility, NIC identity and RTC access belong to
# the upstream built-in wake commands, independently of fan/power plugins.
BIOS_WOL_SUPPORTED=false
BIOS_RTC_SUPPORTED=false
BIOS_WOL_AUTOMATIC=false
BIOS_WAKE_MODEL=""
BIOS_WAKE_CACHE_KEY=""

bios_wake_cli() {
    local binary
    binary=$(bios_ugreenctl_binary) || { echo '内置唤醒控制程序不可用' >&2; return 127; }
    "$binary" "$@"
}

bios_load_wake_profiles() {
    local product id name details rest wol_records rtc_records complete=true
    product=$(hardware_detected_product_name) || return 1
    [[ -n "$product" ]] || return 1
    [[ "$BIOS_WAKE_CACHE_KEY" == "$product" ]] && return 0
    BIOS_WOL_SUPPORTED=false; BIOS_RTC_SUPPORTED=false; BIOS_WOL_AUTOMATIC=false; BIOS_WAKE_MODEL=""
    # Do not cache failures: the backend may be temporarily unavailable.
    wol_records=$(bios_wake_cli network wol models 2>/dev/null) || complete=false
    rtc_records=$(bios_wake_cli power rtc-wake models 2>/dev/null) || complete=false
    while IFS=$'\t' read -r id name details rest; do
        [[ "$name" == "$product" ]] || continue
        BIOS_WOL_SUPPORTED=true; BIOS_WAKE_MODEL="$id"
        [[ "$details" == 'wol=automatic-or-explicit' ]] && BIOS_WOL_AUTOMATIC=true
    done <<< "$wol_records"
    while IFS=$'\t' read -r id name details rest; do
        [[ "$name" == "$product" ]] || continue
        BIOS_RTC_SUPPORTED=true; BIOS_WAKE_MODEL="$id"
    done <<< "$rtc_records"
    "$complete" && BIOS_WAKE_CACHE_KEY="$product"
    return 0
}

bios_rtc_supported_model() { bios_load_wake_profiles && "$BIOS_RTC_SUPPORTED"; }

bios_wol_interface_valid() {
    [[ -z "$1" ]] || { [[ "$1" =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] && [[ "$1" != '.' && "$1" != '..' ]]; }
}

bios_selected_wol_interface() {
    local selection product
    declare -F settings_get >/dev/null && [[ -n "${SETTINGS_FILE:-}" ]] || return 0
    selection=$(settings_get "$SETTINGS_FILE" bios wol_interface_selection '')
    product=$(hardware_detected_product_name)
    [[ "$selection" == "$product|"* ]] || return 0
    selection=${selection#*|}
    bios_wol_interface_valid "$selection" && printf '%s' "$selection"
}

bios_wol_cli() {
    local interface="$1"; shift
    bios_wol_interface_valid "$interface" || { echo '网卡名称无效' >&2; return 1; }
    if [[ -n "$interface" ]]; then bios_wake_cli "$@" --interface "$interface"
    else bios_wake_cli "$@"; fi
}

bios_set_wol_saved() {
    local policy="$1" interface="$2" product
    bios_wol_interface_valid "$interface" || { BIOS_LAST_ERROR='网卡名称无效'; return 1; }
    bios_set_wol "$policy" "$interface" || return 1
    product=$(hardware_detected_product_name) || return 1
    settings_set "$SETTINGS_FILE" bios wol_interface_selection "$product|$interface" || {
        BIOS_LAST_ERROR='WOL 已写入，但网卡选择保存失败，请重新保存'; return 1;
    }
}

bios_wol_query_json() {
    local interface="${1-$(bios_selected_wol_interface)}" available=false
    BIOS_WOL_POLICY=unknown; BIOS_WOL_ERROR=''
    if ! bios_wol_interface_valid "$interface"; then
        printf '{"ok":false,"error":"网卡名称无效"}'; return
    fi
    if bios_wol_supported_model; then
        bios_read_cli_wol "$interface" && available=true
    else BIOS_WOL_ERROR='当前机型没有上游 WOL 映射'; fi
    printf '{"ok":true,"supported":%s,"automatic":%s,"available":%s,"interface":"%s","policy":"%s","error":"%s"}' \
        "$BIOS_WOL_SUPPORTED" "$BIOS_WOL_AUTOMATIC" "$available" "$(json_str "$interface")" "$(json_str "$BIOS_WOL_POLICY")" "$(json_str "$BIOS_WOL_ERROR")"
}
