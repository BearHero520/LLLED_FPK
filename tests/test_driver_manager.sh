#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/App.Native.UGreenLED/app/server/lib/driver_manager.sh"

for fn in driver_probe driver_install driver_unload driver_remove driver_cleanup_new_install; do
  "$fn" >/dev/null 2>&1 && { echo "FAIL: $fn unexpectedly succeeded" >&2; exit 1; } || [[ "$?" -eq 95 ]] || {
    echo "FAIL: $fn returned an unexpected status" >&2; exit 1;
  }
done
[[ "$(driver_error_message)" == *ugreen_leds_cli* ]] || {
  echo "FAIL: driver error did not direct callers to bundled CLI" >&2; exit 1;
}
echo "driver manager tests passed"
