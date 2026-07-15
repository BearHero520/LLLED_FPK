#!/bin/bash
# 可选 led-ugreen DKMS 后端。默认不安装；仅在用户主动操作后管理和恢复。

UGREEN_DRIVER_NAME="led-ugreen"
UGREEN_DRIVER_MODULE="led_ugreen"
UGREEN_DRIVER_VERSION="0.3"
I2C_SYSFS_ROOT="${I2C_SYSFS_ROOT:-/sys/bus/i2c/devices}"
DRIVER_PROBE_BUS=""
DRIVER_PROBE_CREATED=false

driver_source_dir() {
    printf '%s\n' "${SERVER_DIR}/driver/led-ugreen"
}

driver_target_dir() {
    printf '/usr/src/%s-%s\n' "$UGREEN_DRIVER_NAME" "$UGREEN_DRIVER_VERSION"
}

driver_managed_marker() {
    printf '%s\n' "${VAR_DIR}/driver-managed"
}

driver_managed_by_app() {
    [[ -f "$(driver_managed_marker)" ]]
}

driver_managed_bus() {
    local marker
    marker=$(driver_managed_marker)
    [[ -r "$marker" ]] || return 1
    sed -n 's/^bus=\([0-9][0-9]*\)$/\1/p' "$marker" | head -n 1
}

driver_write_managed_marker() {
    local bus="$1" created="${2:-false}" marker tmp
    marker=$(driver_managed_marker)
    tmp="${marker}.tmp.$$"
    mkdir -p "${marker%/*}" || return 1
    {
        printf 'version=%s\n' "$UGREEN_DRIVER_VERSION"
        printf 'bus=%s\n' "$bus"
        printf 'device_created=%s\n' "$created"
    } > "$tmp" || return 1
    mv "$tmp" "$marker"
}

driver_kernel_release() {
    uname -r
}

driver_headers_ready() {
    [[ -d "/lib/modules/$(driver_kernel_release)/build" ]]
}

driver_dkms_ready() {
    command -v dkms >/dev/null 2>&1
}

driver_module_loaded() {
    lsmod 2>/dev/null | grep -q "^${UGREEN_DRIVER_MODULE}[[:space:]]"
}

driver_vendor_conflict() {
    lsmod 2>/dev/null | grep -Eq '^(leds_mcu[^[:space:]]*|ugreen_leds|leds_ugreen)[[:space:]]'
}

driver_sysfs_ready() {
    local root="${LED_SYSFS_ROOT:-/sys/class/leds}"
    [[ -d "$root/power" && -w "$root/power/brightness" && -w "$root/power/color" ]]
}

driver_dkms_registered() {
    driver_dkms_ready || return 1
    [[ -n "$(dkms status -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" 2>/dev/null)" ]]
}

driver_dkms_installed() {
    driver_dkms_ready || return 1
    dkms status -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" -k "$(driver_kernel_release)" 2>/dev/null | grep -q 'installed'
}

driver_dkms_remove_all() {
    dkms remove -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" --all >/dev/null 2>&1 || true
}

driver_find_i2c_bus() {
    local protocol bus dev chip
    protocol=$(hardware_write_protocol)
    dev=$(i2cdetect -l 2>/dev/null | awk '/SMBus I801 adapter/ {print $1; exit}')
    if [[ -n "$dev" ]]; then
        echo "${dev#i2c-}"
        return
    fi
    [[ "$protocol" == "smbus-block" ]] || return 1
    while read -r dev; do
        [[ "$dev" =~ ^i2c-[0-9]+$ ]] || continue
        bus="${dev#i2c-}"
        if [[ -d "${I2C_SYSFS_ROOT}/${bus}-003a" ]]; then
            echo "$bus"
            return
        fi
        chip=$(i2cget -y "$bus" 0x3a 0x5a w 2>/dev/null || true)
        if [[ "$chip" == "0xc5b2" ]]; then
            echo "$bus"
            return
        fi
    done < <(i2cdetect -l 2>/dev/null | awk '/Synopsys DesignWare I2C adapter/ {print $1}')
    return 1
}

driver_find_led_i2c_bus() {
    local bus name_file current_name
    bus=$(driver_managed_bus 2>/dev/null || true)
    if [[ "$bus" =~ ^[0-9]+$ && -d "${I2C_SYSFS_ROOT}/${bus}-003a" ]]; then
        echo "$bus"
        return
    fi
    for name_file in "${I2C_SYSFS_ROOT}"/*-003a/name; do
        [[ -r "$name_file" ]] || continue
        current_name=$(<"$name_file")
        [[ "$current_name" == "led-ugreen" ]] || continue
        bus="${name_file%/name}"
        bus="${bus##*/}"
        echo "${bus%-003a}"
        return
    done
    return 1
}

driver_release_i2c_bus() {
    local bus="$1" dev_path delete_file current_name i
    [[ "$bus" =~ ^[0-9]+$ ]] || return 1
    dev_path="${I2C_SYSFS_ROOT}/${bus}-003a"
    [[ -d "$dev_path" ]] || return 0
    if [[ -r "$dev_path/name" ]]; then
        current_name=$(<"$dev_path/name")
        [[ "$current_name" == "led-ugreen" ]] || return 1
    fi
    delete_file="${I2C_SYSFS_ROOT}/i2c-${bus}/delete_device"
    [[ -w "$delete_file" ]] || return 1
    printf '0x3a\n' > "$delete_file" || return 1
    for ((i = 0; i < 20; i++)); do
        [[ ! -e "$dev_path" ]] && return 0
        sleep 0.05
    done
    return 1
}

driver_release_i2c_device() {
    local bus
    bus=$(driver_find_led_i2c_bus 2>/dev/null || true)
    [[ -n "$bus" ]] || return 0
    driver_release_i2c_bus "$bus"
}

driver_probe() {
    local protocol netdev_count disk_count bus dev_path current_name created=false
    DRIVER_PROBE_BUS=""
    DRIVER_PROBE_CREATED=false
    protocol=$(hardware_write_protocol)
    netdev_count=$(hardware_netdev_count)
    disk_count=$(hardware_disk_count)

    modprobe i2c-dev 2>/dev/null || true
    if ! driver_module_loaded; then
        local -a args=("$UGREEN_DRIVER_NAME" "write_protocol=$protocol" "num_netdev_leds=$netdev_count")
        [[ "$disk_count" =~ ^[0-9]+$ && "$disk_count" -gt 0 ]] && args+=("num_disk_leds=$disk_count")
        modprobe "${args[@]}" || return 1
    fi

    bus=$(driver_find_i2c_bus) || return 2
    DRIVER_PROBE_BUS="$bus"
    dev_path="${I2C_SYSFS_ROOT}/${bus}-003a"
    if [[ ! -d "$dev_path" ]]; then
        printf 'led-ugreen 0x3a\n' > "${I2C_SYSFS_ROOT}/i2c-${bus}/new_device" || return 3
        created=true
        DRIVER_PROBE_CREATED=true
    elif [[ -r "$dev_path/name" ]]; then
        current_name=$(<"$dev_path/name")
        [[ "$current_name" == "led-ugreen" ]] || return 4
    fi
    driver_sysfs_ready || return 5
    driver_write_managed_marker "$bus" "$created"
}

driver_cleanup_new_install() {
    local target="$1"
    driver_release_i2c_device >/dev/null 2>&1 || true
    if [[ "$DRIVER_PROBE_BUS" =~ ^[0-9]+$ ]]; then
        driver_release_i2c_bus "$DRIVER_PROBE_BUS" >/dev/null 2>&1 || true
    fi
    modprobe -r "$UGREEN_DRIVER_NAME" >/dev/null 2>&1 || true
    driver_dkms_remove_all
    rm -rf "$target"
}

driver_restore_previous() {
    local backup="$1" target="$2" kernel="$3"
    [[ -d "$backup" ]] || return 1
    driver_cleanup_new_install "$target"
    mkdir -p "$target" || return 1
    cp -a "$backup/." "$target/" || return 1
    dkms add -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" || return 1
    dkms install -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" -k "$kernel" || return 1
    depmod -a "$kernel" 2>/dev/null || true
    driver_probe
}

driver_install() {
    local source target kernel stage backup rc
    local had_registered=false rollback_available=false
    [[ "$(id -u)" == "0" ]] || return 10
    if declare -F hardware_driver_supported >/dev/null; then
        hardware_driver_supported || return 21
    else
        [[ "$(hardware_support_level)" != "unsupported" ]] || return 21
    fi
    driver_vendor_conflict && return 11
    driver_dkms_ready || return 12
    driver_headers_ready || return 13
    source=$(driver_source_dir)
    [[ -f "$source/led-ugreen.c" && -f "$source/dkms.conf" ]] || return 14
    target=$(driver_target_dir)
    kernel=$(driver_kernel_release)
    stage="${VAR_DIR}/.driver-stage.$$"
    backup="${VAR_DIR}/.driver-backup.$$"

    if driver_dkms_registered; then
        driver_managed_by_app || return 19
        had_registered=true
    fi
    if driver_module_loaded; then
        driver_managed_by_app || return 19
    fi

    rm -rf "$stage" "$backup"
    mkdir -p "$stage" || return 15
    cp "$source/led-ugreen.c" "$source/led-ugreen.h" "$source/Makefile" "$source/dkms.conf" "$stage/" || {
        rm -rf "$stage"
        return 15
    }
    if $had_registered && [[ -d "$target" ]]; then
        mkdir -p "$backup" && cp -a "$target/." "$backup/" && rollback_available=true
    fi

    if driver_module_loaded || driver_find_led_i2c_bus >/dev/null 2>&1; then
        driver_unload || {
            rm -rf "$stage" "$backup"
            return 20
        }
    fi

    rm -rf "$target"
    mkdir -p "$target" || rc=15
    if [[ -z "${rc:-}" ]]; then
        cp -a "$stage/." "$target/" || rc=15
    fi
    if [[ -z "${rc:-}" ]]; then
        driver_dkms_remove_all
        dkms add -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" || rc=16
    fi
    if [[ -z "${rc:-}" ]]; then
        dkms install -m "$UGREEN_DRIVER_NAME" -v "$UGREEN_DRIVER_VERSION" -k "$kernel" || rc=17
    fi
    if [[ -z "${rc:-}" ]]; then
        depmod -a "$kernel" 2>/dev/null || true
        driver_probe || rc=18
    fi

    if [[ -n "${rc:-}" ]]; then
        if $rollback_available; then
            driver_restore_previous "$backup" "$target" "$kernel" >/dev/null 2>&1 || true
        else
            driver_cleanup_new_install "$target"
            rm -f "$(driver_managed_marker)"
        fi
        rm -rf "$stage" "$backup"
        return "$rc"
    fi

    rm -rf "$stage" "$backup"
    return 0
}

driver_unload() {
    local bus=""
    [[ "$(id -u)" == "0" ]] || return 10
    bus=$(driver_find_led_i2c_bus 2>/dev/null || true)
    if driver_module_loaded || [[ -n "$bus" ]]; then
        driver_managed_by_app || return 19
    else
        return 0
    fi
    if [[ -n "$bus" ]]; then
        driver_release_i2c_bus "$bus" || return 22
    fi
    if driver_module_loaded && ! modprobe -r "$UGREEN_DRIVER_NAME"; then
        driver_probe >/dev/null 2>&1 || true
        return 20
    fi
    return 0
}

driver_remove() {
    [[ "$(id -u)" == "0" ]] || return 10
    driver_unload 2>/dev/null || true
    if driver_dkms_ready; then
        driver_dkms_remove_all
    fi
    rm -rf "$(driver_target_dir)"
    rm -f "$(driver_managed_marker)"
}

driver_error_message() {
    case "$1" in
        10) echo "需要 root 权限" ;;
        11) echo "检测到系统厂商 LED 驱动，拒绝抢占设备" ;;
        12) echo "系统未安装 DKMS" ;;
        13) echo "缺少当前内核的 headers" ;;
        14) echo "FPK 内驱动源码不完整" ;;
        15) echo "无法准备 DKMS 源码目录" ;;
        16) echo "DKMS 注册失败" ;;
        17) echo "驱动编译或安装失败" ;;
        18) echo "驱动已安装但 LED MCU 探测失败" ;;
        19) echo "系统已存在非本应用管理的 led-ugreen，拒绝覆盖" ;;
        20) echo "无法安全卸载当前驱动以执行重建" ;;
        21) echo "当前机型使用不同的 LED 控制器，不支持此 DKMS 驱动" ;;
        22) echo "无法释放 LED MCU 的 I2C 设备，已拒绝切换到 CLI" ;;
        *) echo "未知驱动错误" ;;
    esac
}
