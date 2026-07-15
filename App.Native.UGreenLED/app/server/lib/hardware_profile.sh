#!/bin/bash
# 绿联机型档案：将 DMI 型号转换为控制协议、LED 布局与 HCTL 规则。

UGREEN_CLI_RELEASE="v0.4-beta"

hardware_detected_product_name() {
    local product="${UGREEN_PRODUCT_NAME:-}" file
    if [[ -z "$product" ]]; then
        for file in /sys/class/dmi/id/product_name /sys/devices/virtual/dmi/id/product_name; do
            if [[ -r "$file" ]]; then
                product=$(<"$file")
                [[ -n "$product" ]] && break
            fi
        done
    fi
    if [[ -z "$product" ]] && command -v dmidecode >/dev/null 2>&1; then
        product=$(dmidecode --string system-product-name 2>/dev/null || true)
    fi
    product="${product//$'\r'/}"
    product="${product//$'\n'/}"
    printf '%s\n' "$product"
}

hardware_profile_from_name() {
    local normalized="${1^^}"
    case "$normalized" in
        *IDX6011*PRO*) echo "idx6011_pro" ;;
        *IDX6011*) echo "idx6011" ;;
        *IDX6012*) echo "idx6012" ;;
        *DXP480T*) echo "dxp480t_plus" ;;
        *DXP2800*GT*) echo "dxp2800_gt" ;;
        *DXP2800*) echo "dxp2800" ;;
        *DXP4800*GT*) echo "dxp4800_gt" ;;
        *DXP4800*PLUS*) echo "dxp4800_plus" ;;
        *DXP4800*PRO*) echo "dxp4800_pro" ;;
        *DXP4800*) echo "dxp4800" ;;
        *DXP6800*) echo "dxp6800" ;;
        *DXP8800*) echo "dxp8800" ;;
        *DX4700*) echo "dx4700" ;;
        *DX4600*) echo "dx4600" ;;
        *) echo "unknown" ;;
    esac
}

hardware_profile_key() {
    local override="auto"
    if declare -F settings_get >/dev/null && [[ -n "${SETTINGS_FILE:-}" ]]; then
        override=$(settings_get "$SETTINGS_FILE" hardware profile "auto")
    fi
    case "$override" in
        dx4600|dx4700|dxp2800|dxp2800_gt|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800_gt|dxp6800|dxp8800|dxp480t_plus|idx6011|idx6011_pro|idx6012)
            echo "$override"
            ;;
        *)
            hardware_profile_from_name "$(hardware_detected_product_name)"
            ;;
    esac
}

hardware_profile_display_name() {
    case "${1:-$(hardware_profile_key)}" in
        dx4600) echo "UGREEN DX4600 Pro" ;;
        dx4700) echo "UGREEN DX4700+" ;;
        dxp2800) echo "UGREEN DXP2800" ;;
        dxp2800_gt) echo "UGREEN DXP2800 GT" ;;
        dxp4800) echo "UGREEN DXP4800" ;;
        dxp4800_plus) echo "UGREEN DXP4800 Plus" ;;
        dxp4800_pro) echo "UGREEN DXP4800 Pro" ;;
        dxp4800_gt) echo "UGREEN DXP4800 GT" ;;
        dxp6800) echo "UGREEN DXP6800 Pro" ;;
        dxp8800) echo "UGREEN DXP8800 Plus" ;;
        dxp480t_plus) echo "UGREEN DXP480T / DXP480T Plus" ;;
        idx6011) echo "UGREEN iDX6011" ;;
        idx6011_pro) echo "UGREEN iDX6011 Pro" ;;
        idx6012) echo "UGREEN iDX6012" ;;
        *) echo "未知机型" ;;
    esac
}

hardware_support_level() {
    case "${1:-$(hardware_profile_key)}" in
        dx4600|dx4700|dxp2800|dxp4800|dxp4800_plus|dxp6800|dxp8800) echo "stable" ;;
        dxp4800_gt|idx6011|idx6011_pro|idx6012) echo "experimental" ;;
        dxp2800_gt|dxp4800_pro) echo "unverified" ;;
        dxp480t_plus) echo "limited" ;;
        *) echo "unknown" ;;
    esac
}

hardware_write_protocol() {
    local override="auto"
    if declare -F settings_get >/dev/null && [[ -n "${SETTINGS_FILE:-}" ]]; then
        override=$(settings_get "$SETTINGS_FILE" hardware write_protocol "auto")
    fi
    case "$override" in
        legacy|smbus-block) echo "$override"; return ;;
    esac
    case "${1:-$(hardware_profile_key)}" in
        dxp4800_gt|idx6011|idx6011_pro|idx6012) echo "smbus-block" ;;
        *) echo "legacy" ;;
    esac
}

hardware_disk_count() {
    case "${1:-$(hardware_profile_key)}" in
        dxp2800|dxp2800_gt) echo 2 ;;
        dx4600|dx4700|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800_gt) echo 4 ;;
        dxp6800|idx6011|idx6011_pro|idx6012) echo 6 ;;
        dxp8800) echo 8 ;;
        dxp480t_plus) echo 0 ;;
        *) echo "" ;;
    esac
}

hardware_netdev_count() {
    case "${1:-$(hardware_profile_key)}" in
        idx6011_pro) echo 2 ;;
        dxp480t_plus) echo 0 ;;
        *) echo 1 ;;
    esac
}

hardware_driver_supported() {
    [[ "${1:-$(hardware_profile_key)}" != "dxp480t_plus" ]]
}

hardware_power26_controller() {
    [[ "${1:-$(hardware_profile_key)}" == "dxp480t_plus" ]]
}

hardware_hctl_profile() {
    case "${1:-$(hardware_profile_key)}" in
        dxp6800) echo "dxp6800" ;;
        *) echo "sequential" ;;
    esac
}

# v0.4-beta CLI 使用旧的 power/netdev/disk1... 编号。iDX6011 Pro 的第二个
# 网络灯占用原始 LED 2，因此六个物理硬盘灯需要整体后移一位。
hardware_cli_led_name() {
    local logical="$1" profile="${2:-$(hardware_profile_key)}" index
    if [[ "$profile" == "idx6011_pro" ]]; then
        case "$logical" in
            netdev2) echo "disk1"; return ;;
            disk[1-6])
                index="${logical#disk}"
                printf 'disk%s\n' "$((index + 1))"
                return
                ;;
        esac
    fi
    echo "$logical"
}

hardware_network_leds() {
    local count i
    count=$(hardware_netdev_count)
    for ((i = 1; i <= count; i++)); do
        if ((i == 1)); then echo "netdev"; else echo "netdev${i}"; fi
    done
}

hardware_profile_options() {
    cat <<'EOF'
auto|自动识别
dx4600|UGREEN DX4600 Pro
dx4700|UGREEN DX4700+
dxp2800|UGREEN DXP2800
dxp2800_gt|UGREEN DXP2800 GT（待验证）
dxp4800|UGREEN DXP4800
dxp4800_plus|UGREEN DXP4800 Plus
dxp4800_pro|UGREEN DXP4800 Pro（待验证）
dxp4800_gt|UGREEN DXP4800 GT（实验性）
dxp6800|UGREEN DXP6800 Pro
dxp8800|UGREEN DXP8800 Plus
dxp480t_plus|UGREEN DXP480T / DXP480T Plus（仅电源灯）
idx6011|UGREEN iDX6011（实验性）
idx6011_pro|UGREEN iDX6011 Pro（实验性）
EOF
}
