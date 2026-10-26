#!/bin/sh
# Minimal read-only N76 evidence. No direct bus/port operations or control writes.
set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
LC_ALL=C
export PATH LC_ALL

usage() {
    cat <<'EOF'
Usage: sh scripts/collect-led-evidence.sh [--help] > led-evidence.txt

Only Linux with exact real DMI DH2600 or DXP480T Plus is accepted.
Reads a fixed allowlist of non-serial system metadata and LED attributes.
No scans, direct SMBus/port access, control writes, driver changes or uploads.
A verified stock N76 driver's mode getter may perform known hardware reads;
brightness/color/trigger caches do not prove current physical LED outputs.
Exit: 0 report (missing attributes are marked), 2 usage, 3 unsupported.
EOF
}

case "$#" in
    0) ;;
    1) case "$1" in --help|-h) usage; exit 0 ;; *) usage >&2; exit 2 ;; esac ;;
    *) usage >&2; exit 2 ;;
esac

if [ "$(uname -s 2>/dev/null)" != Linux ]; then
    printf '%s\n' 'unsupported: this collector requires Linux.' >&2
    exit 3
fi
if ! model=$(cat /sys/class/dmi/id/product_name 2>/dev/null); then
    printf '%s\n' 'unsupported: real DMI product_name is unavailable.' >&2
    exit 3
fi
case "$model" in
    DH2600) expected_module=leds_mcu_n76e003_dh2600; leds='power disk1 disk2' ;;
    'DXP480T Plus') expected_module=leds_mcu_n76e003; leds=power ;;
    *) printf '%s\n' 'unsupported: only exact DMI DH2600 or DXP480T Plus is accepted.' >&2; exit 3 ;;
esac

# Flatten control characters, including newlines, so values cannot inject
# additional report keys. Never read serial, UUID, network, block or log files.
value_attr() {
    if [ ! -r "$2" ]; then
        printf '%s=<unavailable>\n' "$1"
    elif value=$(cat "$2" 2>/dev/null); then
        printf '%s=' "$1"
        printf '%s' "$value" | tr '\000-\037\177' ' '
        printf '\n'
    else
        printf '%s=<read-failed>\n' "$1"
    fi
}
link_attr() {
    if target=$(readlink -f "$2" 2>/dev/null) && [ -e "$2" ]; then
        printf '%s=' "$1"
        printf '%s' "$target" | tr '\000-\037\177' ' '
        printf '\n'
    else
        printf '%s=<unbound-or-unavailable>\n' "$1"
    fi
}
present_attr() {
    if [ -e "$2" ]; then printf '%s=yes\n' "$1"; else printf '%s=no\n' "$1"; fi
}

printf '%s\n' 'UGREENCTL_LED_EVIDENCE_V1' '[scope]'
printf '%s\n' 'direct_bus_or_port_access=no' 'control_writes=no' 'uploads=no' \
    'known_mode_getter_policy=read_only_after_verified_stock_binding' \
    'known_bound_mode_getter=hardware_read_0x50_0x51_plus_led_offset' \
    'unknown_register_readability=not_tested' \
    'serial_uuid_mac_ip_hostname_disk_data=not_collected'
printf '%s\n' '[system]'
printf 'kernel.release=%s\nkernel.machine=%s\n' "$(uname -r)" "$(uname -m)"
for attribute in sys_vendor product_name product_version board_name board_version bios_vendor bios_version; do
    value_attr "dmi.$attribute" "/sys/class/dmi/id/$attribute"
done

printf '%s\n' '[related-modules]'
found=no
for module in /sys/module/*; do
    [ -d "$module" ] || continue
    name=${module##*/}
    case "$name" in
        leds_mcu*|leds_ugreen*|ledtrig*|i2c_i801|i2c_piix4|i2c_dev|ug_it86x*|it87)
            found=yes
            printf 'module=%s\n' "$name"
            value_attr "module.$name.version" "$module/version"
            value_attr "module.$name.srcversion" "$module/srcversion"
            value_attr "module.$name.initstate.metadata" "$module/initstate"
            ;;
    esac
done
printf 'related_modules_found=%s\n' "$found"

printf '%s\n' '[i2c-adapter-metadata]'
found=no
for adapter in /sys/class/i2c-adapter/i2c-*; do
    [ -d "$adapter" ] || continue
    found=yes
    name=${adapter##*/}
    printf 'adapter=%s\n' "$name"
    value_attr "adapter.$name.name" "$adapter/name"
    link_attr "adapter.$name.driver" "$adapter/device/driver"
done
printf 'i2c_adapters_found=%s\n' "$found"

printf '%s\n' '[i2c-client-bindings]'
found=no
for device in /sys/bus/i2c/devices/*; do
    [ -d "$device" ] || continue
    name=${device##*/}
    case "$name" in [0-9]*-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;; *) continue ;; esac
    found=yes
    printf 'client=%s\n' "$name"
    link_attr "client.$name.driver" "$device/driver"
    link_attr "client.$name.module" "$device/driver/module"
done
printf 'i2c_clients_found=%s\n' "$found"

printf '%s\n' '[expected-leds]'
printf 'expected_module=%s\n' "$expected_module"
for led in $leds; do
    directory=/sys/class/leds/$led
    printf 'led=%s\n' "$led"
    if [ ! -d "$directory" ]; then
        printf 'led.%s.present=no\n' "$led"
        continue
    fi
    printf 'led.%s.present=yes\n' "$led"
    link_attr "led.$led.device_driver" "$directory/device/driver"
    link_attr "led.$led.device_module" "$directory/device/driver/module"
    value_attr "led.$led.max_brightness.metadata" "$directory/max_brightness"
    value_attr "led.$led.trigger.cached_configuration" "$directory/trigger"
    for attribute in brightness rbrightness color delay_on delay_off mode; do
        present_attr "led.$led.$attribute.present" "$directory/$attribute"
    done

    # Match both the stock I2C driver and the model-specific module. Unknown
    # bindings only get metadata above; never invoke their mode/custom getter.
    resolved=$(readlink -f "$directory" 2>/dev/null) || resolved=
    driver=$(readlink -f "$directory/device/driver" 2>/dev/null) || driver=
    module=$(readlink -f "$directory/device/driver/module" 2>/dev/null) || module=
    verified=no
    case "$resolved" in /sys/devices/*)
        if [ "$driver" = /sys/bus/i2c/drivers/mcu_led ] && [ "$module" = "/sys/module/$expected_module" ]; then
            verified=yes
        fi
        ;;
    esac
    printf 'led.%s.verified_stock_binding=%s\n' "$led" "$verified"
    if [ "$verified" = yes ]; then
        for attribute in brightness rbrightness color delay_on delay_off; do
            value_attr "led.$led.$attribute.cached_configuration" "$directory/$attribute"
        done
        # Original mode_show reads only known mode registers, not current
        # output/brightness/timing registers. This is NOT a zero-I2C report.
        value_attr "led.$led.mode.hardware_mode_registers_only" "$directory/mode"
    else
        printf 'led.%s.custom_getters=skipped_unverified_binding\n' "$led"
    fi
done

printf '%s\n' '[limits]' \
    'cached_configuration_is_not_physical_readback=yes' \
    'mode_registers_do_not_prove_current_on_off_color_intensity_or_timing=yes' \
    'unknown_register_readability_requires_official_protocol_or_separate_designed_experiment=yes'
