#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/App.Native.UGreenLED/app/server/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

mkdir -p "$TMP/proc/sys/kernel" "$TMP/sys/class/hwmon/hwmon0"
printf '%s\n' 'nas-preview' > "$TMP/proc/sys/kernel/hostname"
printf '%s\n' 'PRETTY_NAME="fnOS Test"' > "$TMP/os-release"
printf '%s\n' '90061.25 100.00' > "$TMP/proc/uptime"
printf '%s\n' '0.12 0.34 0.56 1/100 1234' > "$TMP/proc/loadavg"
printf '%s\n' \
    'processor : 0' \
    'model name : Intel Test CPU' \
    '' \
    'processor : 1' \
    'model name : Intel Test CPU' > "$TMP/proc/cpuinfo"
printf '%s\n' \
    'MemTotal:       16777216 kB' \
    'MemAvailable:   12582912 kB' \
    'MemFree:         1048576 kB' \
    'Buffers:          131072 kB' \
    'Cached:          2097152 kB' > "$TMP/proc/meminfo"
printf '%s\n' 'Package id 0' > "$TMP/sys/class/hwmon/hwmon0/temp1_label"
printf '%s\n' '47000' > "$TMP/sys/class/hwmon/hwmon0/temp1_input"

SYSTEM_INFO_PROC_ROOT="$TMP/proc"
SYSTEM_INFO_SYS_ROOT="$TMP/sys"
SYSTEM_INFO_OS_RELEASE="$TMP/os-release"
SYSTEM_INFO_HOSTNAME_FILE="$TMP/proc/sys/kernel/hostname"
source "$LIB/system_info.sh"

assert_eq "$(system_info_hostname)" "nas-preview"
assert_eq "$(system_info_os_name)" "fnOS Test"
assert_eq "$(system_info_uptime_seconds)" "90061"
assert_eq "$(system_info_cpu_model)" "Intel Test CPU"
assert_eq "$(system_info_cpu_threads)" "2"
assert_eq "$(system_info_load_averages)" "0.12|0.34|0.56"
assert_eq "$(system_info_memory_metrics)" "16384|4096|25"
assert_eq "$(system_info_cpu_temperature)" "47.0"

echo "system info tests passed"
