#!/bin/bash
# The application deliberately has no kernel LED backend.  Keep these
# compatibility functions so older callers can report a clear, non-mutating
# error, while all LED I/O remains in ugreen_leds_cli.

UGREEN_DRIVER_NAME="led-ugreen"
UGREEN_DRIVER_MODULE="led_ugreen"

driver_module_loaded() { return 1; }
driver_vendor_conflict() { return 1; }
driver_sysfs_ready() { return 1; }
driver_headers_ready() { return 1; }
driver_dkms_ready() { return 1; }
driver_dkms_installed() { return 1; }
driver_dkms_registered() { return 1; }
driver_managed_by_app() { return 1; }
driver_managed_bus() { return 1; }
driver_find_i2c_bus() { return 1; }
driver_find_led_i2c_bus() { return 1; }
driver_release_i2c_bus() { return 1; }
driver_release_i2c_device() { return 1; }
driver_probe() { return 95; }
driver_install() { return 95; }
driver_unload() { return 95; }
driver_remove() { return 95; }
driver_cleanup_new_install() { return 95; }
driver_restore_previous() { return 95; }
driver_dkms_remove_all() { return 95; }

driver_error_message() {
    printf '%s\n' "kernel LED backends are disabled; use bundled ugreen_leds_cli"
}
