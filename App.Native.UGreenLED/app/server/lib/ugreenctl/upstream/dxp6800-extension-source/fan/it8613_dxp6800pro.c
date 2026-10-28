#include "fan/it8613_dxp6800pro.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "fan/it8613_direct.h"
#include "fan/it8613_hwmon.h"

/* The stock DXP6800 branch reads CPU, sysfan1, then sysfan2 from these
 * IT8613 tachometer pairs. Linux it87 exposes their PWM outputs as 2, 3, 4. */
static const struct it8613_hwmon_channel status_channels[] = {
    {"cpu", 2, 2},
    {"sys1", 3, 3},
    {"sys2", 4, 4}
};

/* ug_it86x-cpufan's "set <pwm>" command updates both system fan outputs in
 * this order. It does not expose an independent system-fan command. */
static const struct it8613_hwmon_channel system_write_channels[] = {
    {"sys1", 3, 3},
    {"sys2", 4, 4}
};

static const struct it8613_direct_channel direct_status_channels[] = {
    {"cpu", 0x16, 0x6b, 0x0e, 0x19, true},
    {"sys1", 0x17, 0x73, 0x0f, 0x1a, true},
    {"sys2", 0x1e, 0x7b, 0x80, 0x81, true}
};

int it8613_dxp6800pro_read_fans(struct ugreenctl_fan_status *fans, size_t *fan_count,
                                 char *error, size_t error_size)
{
    int result = it8613_hwmon_read_fans(status_channels, 3, fans, fan_count,
                                        error, error_size);

    if (result != -ENODEV) {
        return result;
    }
    return it8613_direct_read_fans(direct_status_channels, 3, fans, fan_count,
                                   error, error_size);
}

int it8613_dxp6800pro_set_fan_pwm(bool force, const char *fan_id, uint8_t pwm,
                                   char *error, size_t error_size)
{
    const struct it8613_hwmon_channel *hwmon_channels;
    const struct it8613_direct_channel *direct_channels;
    size_t channel_count;
    int result;

    if (strcmp(fan_id, "cpu") == 0) {
        hwmon_channels = &status_channels[0];
        direct_channels = &direct_status_channels[0];
        channel_count = 1;
    } else if (strcmp(fan_id, "sys") == 0) {
        hwmon_channels = system_write_channels;
        direct_channels = &direct_status_channels[1];
        channel_count = 2;
    } else {
        (void)snprintf(error, error_size,
                       "unknown DXP6800 Pro fan target '%s' (expected cpu or sys)", fan_id);
        return -EINVAL;
    }

    result = it8613_hwmon_set_manual_pwm(hwmon_channels, channel_count, pwm,
                                          error, error_size);
    if (result != -ENODEV) {
        return result;
    }
    if (!force) {
        (void)snprintf(error, error_size,
                       "direct Super I/O fan writes require --force together with --apply");
        return -EPERM;
    }
    return it8613_direct_set_manual_pwm(direct_channels, channel_count, pwm,
                                        error, error_size);
}
