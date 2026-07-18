#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/App.Native.UGreenLED/app/server/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

BIN="$TMP/ugreenctl"
PLUGINS="$TMP/models"
ARGS="$TMP/args"
STATUS="$TMP/status"
mkdir -p "$PLUGINS"
: > "$PLUGINS/dxp4800plus.so"
: > "$PLUGINS/dxp4800s.so"
: > "$PLUGINS/dxp480tplus.so"
cat > "$BIN" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$UGREENCTL_ARGS"
case " $* " in
  *" info "*) cat "$UGREENCTL_STATUS" ;;
  *" fan status "*) sed -n 's/^fan /fan /p' "$UGREENCTL_STATUS" ;;
  *" power startup get "*) sed -n 's/^startup: //p' "$UGREENCTL_STATUS" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$BIN"

UGREEN_PRODUCT_NAME="UGREEN DXP4800 Plus"
UGREENCTL_ARGS="$ARGS"
UGREENCTL_STATUS="$STATUS"
BIOS_UGREENCTL="$BIN"
BIOS_UGREENCTL_PLUGIN_DIR="$PLUGINS"
export UGREENCTL_ARGS UGREENCTL_STATUS
source "$LIB/hardware_profile.sh"
source "$LIB/bios_control.sh"

bios_supported_model || fail "DXP4800 Plus should expose BIOS control"
UGREEN_PRODUCT_NAME="UGREEN DXP4800"
! bios_supported_model || fail "DXP4800 must not expose BIOS control"
UGREEN_PRODUCT_NAME="UGREEN DXP4800 Pro"
bios_supported_model || fail "DXP4800 Pro is supported by the upstream plugin"
BIOS_TEST_IT87_MODULE_PATH="$TMP/it87-module"
bios_write_confirmation_required || fail "direct fallback must require explicit acknowledgement"
mkdir -p "$BIOS_TEST_IT87_MODULE_PATH"
! bios_write_confirmation_required || fail "loaded it87 must keep normal writes on the hwmon path"
unset BIOS_TEST_IT87_MODULE_PATH
UGREEN_PRODUCT_NAME="DXP4800S"
bios_supported_model || fail "DXP4800S should expose guarded BIOS control"
UGREEN_PRODUCT_NAME="UGREEN DXP4800S"
! bios_supported_model || fail "DXP4800S must follow the exact upstream DMI string"
UGREEN_PRODUCT_NAME="DXP4800S Engineering"
! bios_supported_model || fail "DXP4800S BIOS control must require an exact DMI product name"
UGREEN_PRODUCT_NAME="UGREEN DXP480T Plus"
bios_supported_model || fail "DXP480T Plus should expose BIOS control"
UGREEN_PRODUCT_NAME="UGREEN DXP480T Plus Engineering"
! bios_supported_model || fail "DXP480T Plus BIOS control must require an exact DMI product name"
UGREEN_PRODUCT_NAME="UGREEN DXP480T"
! bios_supported_model || fail "plain DXP480T must not bypass the exact DMI guard"
UGREEN_PRODUCT_NAME="UGREEN DXP4800 Plus"

assert_eq "$(bios_backend)" "ugreenctl"
cat > "$STATUS" <<'EOF'
model: dxp4800plus (UGREEN DXP4800 Plus / DXP4800 Pro)
controller: ITE IT8613 Super I/O
startup: restore
fan cpu: pwm=120 mode=manual tach=675 rpm=1000
fan sys: pwm=88 mode=auto tach=750 rpm=900
EOF
bios_read_status
assert_eq "$BIOS_MODEL" "dxp4800_plus"
assert_eq "$BIOS_BACKEND" "ugreenctl"
assert_eq "$BIOS_STARTUP_POLICY" "last"
assert_eq "$BIOS_CPU_PWM" "120"
assert_eq "$BIOS_CPU_RPM" "1000"
assert_eq "$BIOS_SYS_PWM" "88"
assert_eq "$BIOS_SYS_RPM" "900"

bios_set_fan cpu 120
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --force --apply fan set cpu 120 "
! bios_set_fan cpu 39 || fail "PWM below the upstream safety floor must be rejected"
! bios_set_fan_mode cpu auto || fail "fan auto mode must remain unavailable"
bios_set_startup last
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply power startup set restore "

UGREEN_PRODUCT_NAME="DXP4800S"
cat > "$STATUS" <<'EOF'
model: dxp4800s (UGREEN DXP4800S (firmware-reversed))
controller: ITE IT8613 Super I/O
startup: off
fan sys: pwm=unknown mode=unknown tach=750 rpm=900
EOF
bios_read_status
assert_eq "$BIOS_MODEL" "dxp4800s"
assert_eq "$BIOS_EXPERIMENTAL" "true"
assert_eq "$BIOS_MIN_PWM" "40"
assert_eq "$BIOS_CPU_FAN_PRESENT" "false"
assert_eq "$BIOS_FAN_MODE_WRITABLE" "false"
assert_eq "$BIOS_PWM_READABLE" "true"
assert_eq "$BIOS_WRITE_CONFIRMATION_REQUIRED" "true"
assert_eq "$BIOS_SYS_RPM" "900"
assert_eq "$BIOS_SYS_PWM" "-1"
assert_eq "$BIOS_STARTUP_POLICY" "off"
bios_write_confirmation_required || fail "DXP4800S must require explicit write acknowledgement"
bios_set_fan sys 40
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --force --apply fan set sys 40 "
! bios_set_fan sys 39 || fail "DXP4800S PWM below 40 must be rejected"
! bios_set_fan cpu 120 || fail "DXP4800S must not expose a CPU fan target"
! bios_set_fan_mode sys manual || fail "DXP4800S mode writes must remain unavailable"
bios_set_startup on
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --force --apply power startup set on "

UGREEN_PRODUCT_NAME="UGREEN DXP480T Plus"
cat > "$STATUS" <<'EOF'
model: dxp480tplus (UGREEN DXP480T Plus (hardware-verified))
controller: ITE IT8613 Super I/O
startup: on
fan cpu: pwm=120 mode=manual tach=675 rpm=1000
fan sys1: pwm=96 mode=manual tach=750 rpm=900
fan sys2: pwm=104 mode=auto tach=450 rpm=1500
EOF
bios_read_status
assert_eq "$BIOS_EXPERIMENTAL" "false"
assert_eq "$BIOS_CPU_RPM" "1000"
assert_eq "$BIOS_SYS_RPM" "900"
assert_eq "$BIOS_SYS2_RPM" "1500"
assert_eq "$BIOS_SYS_PWM" "96"
assert_eq "$BIOS_SYS2_PWM" "104"
assert_eq "$BIOS_SYS_MANUAL" "true"
assert_eq "$BIOS_SYS2_MANUAL" "false"
bios_set_fan cpu 120
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --force --apply fan set cpu 120 "
bios_set_fan all 100
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --force --apply fan set all 100 "
! bios_set_fan_mode cpu auto || fail "DXP480T fan auto mode must remain unavailable"
! bios_set_fan sys 100 || fail "DXP480T must not expose individual system fan writes"
! bios_set_fan all 39 || fail "DXP480T PWM below 40 must be rejected"
bios_set_startup on
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply power startup set on "

BIOS_TEST_IT87_MODULE_PATH="$TMP/it87-unloaded"
cat > "$STATUS" <<'EOF'
model: dxp480tplus (UGREEN DXP480T Plus (hardware-verified))
controller: ITE IT8613 Super I/O
startup: on
fan cpu: pwm=120 mode=manual tach=675 rpm=1000
fan sys1: pwm=120 mode=manual tach=750 rpm=900
fan sys2: pwm=unknown mode=unknown tach=450 rpm=1500
EOF
bios_read_status
assert_eq "$BIOS_DIRECT_FAN_FALLBACK" "true"
assert_eq "$BIOS_WRITE_CONFIRMATION_REQUIRED" "true"
assert_eq "$BIOS_CPU_PWM" "120"
assert_eq "$BIOS_SYS_PWM" "120"
assert_eq "$BIOS_SYS2_PWM" "-1"
assert_eq "$BIOS_SYS2_RPM" "1500"
bios_set_fan all 100
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --force --apply fan set all 100 "
unset BIOS_TEST_IT87_MODULE_PATH

echo "BIOS control tests passed"
