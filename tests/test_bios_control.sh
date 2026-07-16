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
: > "$PLUGINS/dxp480tplus.so"
cat > "$BIN" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$UGREENCTL_ARGS"
case " $* " in
  *" info "*) cat "$UGREENCTL_STATUS" ;;
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
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan set cpu 120 "
! bios_set_fan cpu 39 || fail "PWM below the upstream safety floor must be rejected"
bios_set_fan_mode cpu auto
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan mode cpu auto "
bios_set_fan_mode sys manual
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan mode sys manual "
bios_set_startup last
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply power startup set restore "

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
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan set cpu 120 "
bios_set_fan all 100
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan set all 100 "
bios_set_fan_mode cpu auto
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan mode cpu auto "
bios_set_fan_mode all auto
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply fan mode all auto "
! bios_set_fan_mode sys auto || fail "DXP480T must not expose individual system fan mode writes"
! bios_set_fan sys 100 || fail "DXP480T must not expose individual system fan writes"
! bios_set_fan all 39 || fail "DXP480T PWM below 40 must be rejected"
bios_set_startup on
assert_eq "$(tr '\n' ' ' < "$ARGS")" "--plugin-dir $PLUGINS --apply power startup set on "

echo "BIOS control tests passed"
