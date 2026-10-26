#!/bin/sh
# Read-only Linux topology evidence for model/revision and physical-slot research.
# Reads cached sysfs attributes only. It does not probe disks, write registers,
# trigger a rescan, load drivers, or upload the report.
set -eu

if [ "$#" -ne 0 ]; then
    printf '%s\n' 'Usage: sh scripts/collect-disk-evidence.sh > topology.txt' >&2
    exit 2
fi
if [ ! -d /sys/class/block ]; then
    printf '%s\n' 'Linux sysfs is unavailable.' >&2
    exit 3
fi

text_attr() {
    if [ -r "$1" ]; then
        printf '%s=' "$1"
        if tr '\000' '|' < "$1"; then :; else printf '[unavailable]'; fi
        printf '\n'
    fi
}

link_attr() {
    if [ -e "$1" ]; then
        printf '%s=' "$1"
        readlink -f "$1" || :
    fi
}

printf '%s\n' 'UGREENCTL_TOPOLOGY_EVIDENCE_V1' '[system]'
uname -rm
for item in product_name product_version board_name bios_vendor bios_version; do
    text_attr "/sys/class/dmi/id/$item"
done
text_attr /sys/firmware/devicetree/base/model
text_attr /sys/firmware/devicetree/base/compatible

printf '%s\n' '[smbios-type9-raw]'
for item in /sys/firmware/dmi/entries/9-*/raw; do
    [ -r "$item" ] || continue
    printf '%s\n' "$item"
    od -An -v -tx1 "$item" || :
done

printf '%s\n' '[pci-slots]'
for item in /sys/bus/pci/slots/*; do
    [ -d "$item" ] || continue
    text_attr "$item/address"
done

printf '%s\n' '[pci-functions]'
for item in /sys/bus/pci/devices/*; do
    [ -d "$item" ] || continue
    link_attr "$item"
    for attr in class vendor device subsystem_vendor subsystem_device physical_slot; do
        text_attr "$item/$attr"
    done
    link_attr "$item/driver"
    link_attr "$item/of_node"
    link_attr "$item/firmware_node"
    text_attr "$item/firmware_node/path"
    text_attr "$item/of_node/compatible"
done

printf '%s\n' '[ata-ports]'
for item in /sys/class/ata_port/*; do
    [ -d "$item" ] || continue
    link_attr "$item"
    text_attr "$item/port_no"
done

printf '%s\n' '[block-identity-and-topology]'
for item in /sys/class/block/sd* /sys/class/block/nvme*n*; do
    [ -d "$item" ] || continue
    [ ! -e "$item/partition" ] || continue
    link_attr "$item"
    for attr in device/transport device/type device/vendor device/model; do
        text_attr "$item/$attr"
    done
done

printf '%s\n' '[end]'
