#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/App.Native.UGreenLED/app/server/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
export SETTINGS_FILE="$TMP/settings.conf" UGREEN_PRODUCT_NAME=DX4600
export BIOS_UGREENCTL="$TMP/ugreenctl" BIOS_UGREENCTL_PLUGIN_DIR="$TMP/models"
export TEST_STATE="$TMP/hardware" TEST_CALLS="$TMP/calls" TEST_FAIL="$TMP/fail"
mkdir -p "$BIOS_UGREENCTL_PLUGIN_DIR"
for model in dx4600 dxp4800 dxp4800plus dxp4800s dxp480tplus dxp6800pro; do
    touch "$BIOS_UGREENCTL_PLUGIN_DIR/$model.so"
done
cat > "$BIOS_UGREENCTL" <<'EOF'
#!/bin/bash
echo "$*" >> "$TEST_CALLS"
[[ ! -f "$TEST_FAIL" ]] || { echo 'error: simulated readback failure'; exit 1; }
case " $* " in
    *' power startup set '*) echo "${@: -1}" > "$TEST_STATE" ;;
    *' power startup get '*) cat "$TEST_STATE" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$BIOS_UGREENCTL"
source "$LIB/settings.sh"
source "$LIB/hardware_profile.sh"
source "$LIB/bios_control.sh"

# A fresh install must not change the firmware's policy.
bios_startup_restore
[[ ! -e "$TEST_CALLS" ]] || fail 'unconfigured restore wrote hardware'
for policy in on off last; do
    bios_set_startup_saved "$policy"
    [[ "$(settings_get "$SETTINGS_FILE" bios startup_selection)" == "DX4600|$policy" ]] || fail 'selection not saved'
    echo off > "$TEST_STATE"
    # Restart from a clean shell so in-memory variables cannot mask lost state.
    bash -c 'source "$1/settings.sh"; source "$1/hardware_profile.sh"; source "$1/bios_control.sh"; bios_startup_restore' _ "$LIB"
    expected="$policy"; [[ "$policy" != last ]] || expected=restore
    [[ "$(cat "$TEST_STATE")" == "$expected" ]] || fail "lost $policy after restart"
done
grep -q -- '--force --apply power startup set on' "$TEST_CALLS" || fail 'missing guarded upstream write'

touch "$TEST_FAIL"
! bios_set_startup_saved on || fail 'failed hardware write reported success'
[[ "$(settings_get "$SETTINGS_FILE" bios startup_selection)" == 'DX4600|last' ]] || fail 'failed write replaced saved policy'
! bios_startup_restore || fail 'failed restore reported success'
rm "$TEST_FAIL"
! bios_set_startup_saved invalid || fail 'invalid choice accepted'

: > "$TEST_CALLS"
UGREEN_PRODUCT_NAME='DX4600 Pro' bios_startup_restore
UGREEN_PRODUCT_NAME='DX4600 Engineering' bios_startup_restore
UGREEN_PRODUCT_NAME='DXP4800' bios_startup_restore
[[ ! -s "$TEST_CALLS" ]] || fail 'selection replayed on another model'
settings_set "$SETTINGS_FILE" bios startup_selection 'DX4600|invalid'
! bios_startup_restore || fail 'corrupt policy accepted'
[[ ! -s "$TEST_CALLS" ]] || fail 'corrupt policy reached hardware'

# Configuration failure must not be presented as a persistent success.
settings_set() { return 1; }
! bios_set_startup_saved on || fail 'save failure reported success'
[[ "$BIOS_LAST_ERROR" == *保存失败* ]] || fail 'missing persistence error'
echo 'Startup persistence tests passed'
